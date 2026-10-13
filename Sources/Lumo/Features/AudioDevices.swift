import AppKit
import AudioToolbox
import Carbon
import CoreAudio

/// Outputs and microphones: a shortcut to cycle outputs, a volume drop when headphones go away,
/// a preferred microphone, its input level, a "mute every mic" shortcut and the Music launch blocker.
@MainActor
final class AudioDevices: ObservableObject {
    struct Device: Identifiable, Hashable {
        let id: AudioObjectID
        let uid: String
        let name: String
        let transport: UInt32

        var symbol: String {
            switch transport {
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "airpodspro"
            case kAudioDeviceTransportTypeUSB: return "cable.connector"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
            case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
            default: return "speaker.wave.2.fill"
            }
        }
    }

    private enum Key {
        static let outputHotKey = "audio.outputHotKey"
        static let headphoneGuard = "audio.headphoneGuard"
        static let guardVolume = "audio.guardVolume"
        static let preferredInput = "audio.preferredInput"
        static let muteHotKey = "audio.muteHotKey"
        static let musicBlocker = "audio.musicBlocker"
    }

    private static let builtInSpeakerSource: UInt32 = 0x6973_706B // 'ispk'
    private static let headphoneSource: UInt32 = 0x6864_706E // 'hdpn'
    private static let musicBundleID = "com.apple.Music"
    private static let playKeyWindow: TimeInterval = 4

    @Published private(set) var outputs: [Device] = []
    @Published private(set) var inputs: [Device] = []
    @Published private(set) var defaultOutput: AudioObjectID = 0
    @Published private(set) var defaultInput: AudioObjectID = 0
    @Published private(set) var inputLevel: Double?
    @Published private(set) var micsMuted = false
    @Published private(set) var blockedLaunches = 0

    @Published var outputHotKey: Bool { didSet { store.set(outputHotKey, forKey: Key.outputHotKey); registerHotKeys() } }
    @Published var headphoneGuard: Bool { didSet { store.set(headphoneGuard, forKey: Key.headphoneGuard) } }
    @Published var guardVolume: Double { didSet { store.set(guardVolume, forKey: Key.guardVolume) } }
    @Published var preferredInputUID: String? { didSet { store.set(preferredInputUID, forKey: Key.preferredInput); enforcePreferredInput() } }
    @Published var muteHotKey: Bool { didSet { store.set(muteHotKey, forKey: Key.muteHotKey); registerHotKeys() } }
    @Published var musicBlocker: Bool { didSet { store.set(musicBlocker, forKey: Key.musicBlocker); configureBlocker() } }

    var t = Localizer(language: .english)

    private let store: UserDefaults
    private let hotKeys = HotKeyCenter()
    private let tap = InputTap()
    private var lastOutputWasHeadphones = false
    private var lastPlayKey = Date.distantPast
    private var mutedVolumes: [AudioObjectID: Float32] = [:]
    private var launchObserver: NSObjectProtocol?
    private var listening = false

    init(store: UserDefaults) {
        store.register(defaults: [Key.guardVolume: 0.25])
        self.store = store
        outputHotKey = store.bool(forKey: Key.outputHotKey)
        headphoneGuard = store.bool(forKey: Key.headphoneGuard)
        guardVolume = store.double(forKey: Key.guardVolume)
        preferredInputUID = store.string(forKey: Key.preferredInput)
        muteHotKey = store.bool(forKey: Key.muteHotKey)
        musicBlocker = store.bool(forKey: Key.musicBlocker)
    }

    func start() {
        reload()
        lastOutputWasHeadphones = isHeadphoneLike(defaultOutput)
        listen()
        registerHotKeys()
        configureBlocker()
        enforcePreferredInput()
    }

    func shutdown() {
        tap.stop()
        if micsMuted { setMicsMuted(false) }
    }

    // MARK: Devices

    func reload() {
        let all = AudioHW.ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        func devices(_ scope: AudioObjectPropertyScope) -> [Device] {
            all.compactMap { id in
                guard Self.hasStreams(id, scope), let uid = AudioHW.deviceUID(id),
                      let name = AudioHW.string(id, kAudioObjectPropertyName), !name.hasPrefix("Lumo ")
                else { return nil }
                let transport = AudioHW.scalar(id, kAudioDevicePropertyTransportType, initial: UInt32(0)) ?? 0
                return transport == kAudioDeviceTransportTypeAggregate ? nil : Device(id: id, uid: uid, name: name, transport: transport)
            }
        }
        outputs = devices(kAudioObjectPropertyScopeOutput)
        inputs = devices(kAudioObjectPropertyScopeInput)
        defaultOutput = AudioHW.defaultOutputDevice()
        defaultInput = AudioHW.scalar(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice,
                                      initial: AudioObjectID(kAudioObjectUnknown)) ?? 0
        inputLevel = Self.volume(defaultInput, scope: kAudioObjectPropertyScopeInput).map(Double.init)
    }

    func setOutput(_ device: Device) {
        AudioHW.setDefaultOutputDevice(device.id)
        reload()
    }

    func setInput(_ device: Device) {
        Self.setSystemDevice(kAudioHardwarePropertyDefaultInputDevice, device.id)
        reload()
    }

    func setInputLevel(_ level: Double) {
        Self.setVolume(defaultInput, scope: kAudioObjectPropertyScopeInput, Float32(level))
        inputLevel = level
    }

    /// Next output in the list; announced with a toast.
    func cycleOutput() {
        reload()
        guard !outputs.isEmpty else { return }
        let index = outputs.firstIndex { $0.id == defaultOutput } ?? -1
        let next = outputs[(index + 1) % outputs.count]
        setOutput(next)
        Toast.show(next.symbol, t("Выход: ", "Output: ") + next.name, tint: Palette.blue.color)
    }

    func toggleMicsMuted() {
        setMicsMuted(!micsMuted)
        Toast.show(micsMuted ? "mic.slash.fill" : "mic.fill",
                   micsMuted ? t("Все микрофоны выключены", "All microphones muted") : t("Микрофоны включены", "Microphones on"),
                   tint: micsMuted ? Palette.red.color : Palette.green.color)
    }

    private func setMicsMuted(_ muted: Bool) {
        reload()
        for device in inputs {
            if Self.setMute(device.id, muted) { continue }
            // Devices without a mute switch get their input volume zeroed and later restored.
            if muted {
                mutedVolumes[device.id] = Self.volume(device.id, scope: kAudioObjectPropertyScopeInput) ?? 1
                Self.setVolume(device.id, scope: kAudioObjectPropertyScopeInput, 0)
            } else if let previous = mutedVolumes.removeValue(forKey: device.id) {
                Self.setVolume(device.id, scope: kAudioObjectPropertyScopeInput, previous)
            }
        }
        micsMuted = muted
    }

    // MARK: Watching changes

    private func listen() {
        guard !listening else { return }
        listening = true
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(system, &address, DispatchQueue.main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.devicesChanged() }
            }
        }
        // The built-in jack switches data source instead of device.
        if let builtIn = outputs.first(where: { $0.transport == kAudioDeviceTransportTypeBuiltIn }) {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource, mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(builtIn.id, &address, DispatchQueue.main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.devicesChanged() }
            }
        }
    }

    private func devicesChanged() {
        reload()
        let headphones = isHeadphoneLike(defaultOutput)
        if headphoneGuard, lastOutputWasHeadphones, !headphones {
            Self.setVolume(defaultOutput, scope: kAudioObjectPropertyScopeOutput, Float32(guardVolume))
            Toast.show("speaker.wave.1.fill", t("Наушники отключены — тише", "Headphones gone — volume lowered"),
                       subtitle: Format.percent(guardVolume), tint: Palette.orange.color)
        }
        lastOutputWasHeadphones = headphones
        enforcePreferredInput()
    }

    private func isHeadphoneLike(_ id: AudioObjectID) -> Bool {
        guard let device = outputs.first(where: { $0.id == id }) else { return false }
        switch device.transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE, kAudioDeviceTransportTypeUSB: return true
        case kAudioDeviceTransportTypeBuiltIn:
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource, mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var source: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &source) == noErr && source == Self.headphoneSource
        default: return false
        }
    }

    /// Switches back to the preferred microphone whenever it is connected but not in use.
    private func enforcePreferredInput() {
        guard let uid = preferredInputUID, let device = inputs.first(where: { $0.uid == uid }), device.id != defaultInput else { return }
        Self.setSystemDevice(kAudioHardwarePropertyDefaultInputDevice, device.id)
        defaultInput = device.id
        inputLevel = Self.volume(device.id, scope: kAudioObjectPropertyScopeInput).map(Double.init)
    }

    private func registerHotKeys() {
        hotKeys.unregisterAll()
        if outputHotKey { hotKeys.register(.nextOutput) { [weak self] in self?.cycleOutput() } }
        if muteHotKey { hotKeys.register(.muteMics) { [weak self] in self?.toggleMicsMuted() } }
    }

    // MARK: Music blocker

    /// Watches the Play key (needs Accessibility) and closes Music if it launches right after it.
    private func configureBlocker() {
        tap.stop()
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        launchObserver = nil
        guard musicBlocker else { return }
        let systemDefined = CGEventType(rawValue: 14)!
        tap.configure([(InputTap.mask(systemDefined), { [weak self] _, event in
            if let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 {
                let key = (ns.data1 & 0xFFFF_0000) >> 16
                let pressed = (ns.data1 & 0xFF00) >> 8 == 0x0A
                if key == Int(NX_KEYTYPE_PLAY), pressed { self?.lastPlayKey = Date() }
            }
            return event
        })])
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.musicLaunched(app) }
        }
    }

    private func musicLaunched(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier == Self.musicBundleID,
              Date().timeIntervalSince(lastPlayKey) < Self.playKeyWindow
        else { return }
        app.forceTerminate()
        blockedLaunches += 1
        Toast.show("music.note.slash", t("Music не запустится от кнопки ▶︎", "Music kept from launching on ▶︎"), tint: Palette.pink.color)
    }

    // MARK: CoreAudio helpers

    private static func hasStreams(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func setSystemDevice(_ selector: AudioObjectPropertySelector, _ id: AudioObjectID) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value)
    }

    /// Main volume where the device has one, else the first channel.
    static func volume(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Float32? {
        guard id != 0 else { return nil }
        for (selector, element) in [(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain),
                                    (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
                                    (kAudioDevicePropertyVolumeScalar, 1)] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(id, &address), AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr { return value }
        }
        return nil
    }

    static func setVolume(_ id: AudioObjectID, scope: AudioObjectPropertyScope, _ value: Float32) {
        guard id != 0 else { return }
        var volume = min(max(value, 0), 1)
        for (selector, elements) in [(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, [kAudioObjectPropertyElementMain]),
                                     (kAudioDevicePropertyVolumeScalar, [kAudioObjectPropertyElementMain]),
                                     (kAudioDevicePropertyVolumeScalar, [1, 2])] {
            var done = false
            for element in elements {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
                var settable: DarwinBoolean = false
                guard AudioObjectHasProperty(id, &address), AudioObjectIsPropertySettable(id, &address, &settable) == noErr,
                      settable.boolValue
                else { continue }
                done = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume) == noErr || done
            }
            if done { return }
        }
    }

    private static func setMute(_ id: AudioObjectID, _ muted: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(id, &address), AudioObjectIsPropertySettable(id, &address, &settable) == noErr, settable.boolValue
        else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}
