import AppKit
import AudioToolbox
import CoreAudio

/// Per-app volume (with boost past 100%) and per-app output device, using CoreAudio process taps.
/// A tap exists only for apps the user has adjusted; everything else plays untouched.
@MainActor
final class VolumeMixer: ObservableObject {
    struct Channel: Identifiable, Equatable {
        let processObject: AudioObjectID
        let pid: pid_t
        let name: String
        let bundleID: String?
        let isPlaying: Bool
        let volume: Double
        let deviceUID: String?
        var id: AudioObjectID { processObject }
    }

    private struct Setting: Codable {
        let volume: Double
        let deviceUID: String?
    }

    private static let settingsKey = "mixer.settings"
    private static let enabledKey = "mixer.enabled"
    private static let pinnedKey = "mixer.pinned"
    static let maxVolume = 2.0

    @Published var isEnabled: Bool { didSet { store.set(isEnabled, forKey: Self.enabledKey); refresh() } }
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var devices: [AudioHW.OutputDevice] = []
    @Published private(set) var defaultOutputUID: String?
    @Published var lastError: String?
    /// Favorite apps (bundle ID or name), shown first in this order even while silent.
    @Published private(set) var pinned: [String]

    private let store: UserDefaults
    private var settings: [String: Setting]
    private var taps: [AudioObjectID: TapHandle] = [:]

    init(store: UserDefaults) {
        self.store = store
        isEnabled = store.bool(forKey: Self.enabledKey)
        settings = (store.data(forKey: Self.settingsKey)).flatMap { try? JSONDecoder().decode([String: Setting].self, from: $0) } ?? [:]
        pinned = store.stringArray(forKey: Self.pinnedKey) ?? []
    }

    /// Re-reads audio processes and devices, and (re)applies remembered settings.
    func refresh() {
        devices = AudioHW.outputDevices()
        defaultOutputUID = AudioHW.deviceUID(AudioHW.defaultOutputDevice())
        guard isEnabled else {
            removeAllTaps()
            channels = []
            return
        }
        let processes = AudioHW.audioProcesses().filter { $0.pid != getpid() }
        channels = processes
            .filter { $0.isPlaying || taps[$0.object] != nil || $0.key.map(pinned.contains) == true }
            .map { process in
                let setting = process.key.flatMap { settings[$0] }
                return Channel(processObject: process.object, pid: process.pid, name: process.name, bundleID: process.bundleID,
                               isPlaying: process.isPlaying, volume: setting?.volume ?? 1, deviceUID: setting?.deviceUID)
            }
            .sorted(by: order)
        let alive = Set(processes.map(\.object))
        for object in taps.keys where !alive.contains(object) { removeTap(object) }
        channels.forEach(apply)
    }

    func key(of channel: Channel) -> String { channel.bundleID ?? channel.name }

    func isPinned(_ channel: Channel) -> Bool { pinned.contains(key(of: channel)) }

    func togglePin(_ channel: Channel) {
        let key = key(of: channel)
        pinned = pinned.contains(key) ? pinned.filter { $0 != key } : pinned + [key]
        store.set(pinned, forKey: Self.pinnedKey)
        refresh()
    }

    /// Moves a pinned app up (-1) or down (+1) among the favorites.
    func movePinned(_ channel: Channel, by offset: Int) {
        let key = key(of: channel)
        guard let index = pinned.firstIndex(of: key) else { return }
        let target = min(max(index + offset, 0), pinned.count - 1)
        guard target != index else { return }
        var reordered = pinned
        reordered.swapAt(index, target)
        pinned = reordered
        store.set(pinned, forKey: Self.pinnedKey)
        refresh()
    }

    private func order(_ lhs: Channel, _ rhs: Channel) -> Bool {
        let left = pinned.firstIndex(of: key(of: lhs)) ?? Int.max
        let right = pinned.firstIndex(of: key(of: rhs)) ?? Int.max
        return left != right ? left < right : lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    func setVolume(_ channel: Channel, _ volume: Double) {
        remember(channel, Setting(volume: volume, deviceUID: channel.deviceUID))
    }

    func setDevice(_ channel: Channel, _ uid: String?) {
        remember(channel, Setting(volume: channel.volume, deviceUID: uid))
        removeTap(channel.processObject)
        refresh()
    }

    func setDefaultOutput(_ uid: String) {
        guard let device = devices.first(where: { $0.uid == uid }) else { return }
        AudioHW.setDefaultOutputDevice(device.id)
        // Taps follow the default device, so rebuild them on the new one.
        removeAllTaps()
        refresh()
    }

    func shutdown() { removeAllTaps() }

    // MARK: Taps

    private func remember(_ channel: Channel, _ setting: Setting) {
        guard let key = channel.bundleID ?? Optional(channel.name) else { return }
        settings[key] = setting
        if let data = try? JSONEncoder().encode(settings) { store.set(data, forKey: Self.settingsKey) }
        channels = channels.map {
            $0.id == channel.id ? Channel(processObject: $0.processObject, pid: $0.pid, name: $0.name, bundleID: $0.bundleID,
                                          isPlaying: $0.isPlaying, volume: setting.volume, deviceUID: setting.deviceUID) : $0
        }
        if let updated = channels.first(where: { $0.id == channel.id }) { apply(updated) }
    }

    private func apply(_ channel: Channel) {
        let needsTap = abs(channel.volume - 1) > 0.01 || channel.deviceUID != nil
        guard needsTap else { return removeTap(channel.processObject) }
        if let tap = taps[channel.processObject] {
            tap.gain = Float(channel.volume)
            return
        }
        guard let outputUID = channel.deviceUID ?? defaultOutputUID else { return }
        guard #available(macOS 14.2, *) else {
            lastError = "macOS 14.2+"
            return
        }
        do {
            let tap = try ProcessTap(process: channel.processObject, outputUID: outputUID, name: channel.name)
            tap.gain = Float(channel.volume)
            taps[channel.processObject] = tap
            lastError = nil
        } catch {
            lastError = "\(error.localizedDescription)"
        }
    }

    private func removeTap(_ object: AudioObjectID) {
        taps.removeValue(forKey: object)?.stop()
    }

    private func removeAllTaps() {
        taps.values.forEach { $0.stop() }
        taps = [:]
    }
}

// MARK: - One app's tap → private aggregate device → output

protocol TapHandle: AnyObject {
    var gain: Float { get set }
    func stop()
}

@available(macOS 14.2, *)
final class ProcessTap: TapHandle, @unchecked Sendable {
    struct Failure: LocalizedError {
        let step: String
        let status: OSStatus
        var errorDescription: String? { "Audio \(step) failed (\(status)) — allow Lumo in Privacy & Security → Screen & System Audio Recording." }
    }

    /// Read on the real-time audio thread; a 32-bit store is atomic on Apple silicon and Intel.
    var gain: Float = 1

    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "lumo.mixer", qos: .userInteractive)

    init(process: AudioObjectID, outputUID: String, name: String) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: [process])
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { throw Failure(step: "tap", status: status) }

        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Lumo Mixer · \(name)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        status = AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregate)
        guard status == noErr else {
            AudioHardwareDestroyProcessTap(tap)
            throw Failure(step: "device", status: status)
        }
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, queue) { [weak self] _, input, _, output, _ in
            self?.render(input, output)
        }
        guard status == noErr, let procID else {
            stop()
            throw Failure(step: "render", status: status)
        }
        status = AudioDeviceStart(aggregate, procID)
        guard status == noErr else {
            stop()
            throw Failure(step: "start", status: status)
        }
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregate, procID)
            AudioDeviceDestroyIOProcID(aggregate, procID)
        }
        procID = nil
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        aggregate = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
    }

    /// Copies the tapped (interleaved Float32) audio to the output with gain; boosts are soft-clipped.
    private func render(_ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let gain = self.gain
        guard inputs.count > 0 else { return }
        for index in 0..<outputs.count {
            let out = outputs[index]
            guard let outData = out.mData else { continue }
            let outSamples = outData.assumingMemoryBound(to: Float.self)
            let outChannels = max(Int(out.mNumberChannels), 1)
            let outFrames = Int(out.mDataByteSize) / MemoryLayout<Float>.size / outChannels
            let source = inputs[min(index, inputs.count - 1)]
            guard let inData = source.mData else {
                memset(outData, 0, Int(out.mDataByteSize))
                continue
            }
            let inSamples = inData.assumingMemoryBound(to: Float.self)
            let inChannels = max(Int(source.mNumberChannels), 1)
            let frames = min(outFrames, Int(source.mDataByteSize) / MemoryLayout<Float>.size / inChannels)
            for frame in 0..<frames {
                for channel in 0..<outChannels {
                    let value = inSamples[frame * inChannels + min(channel, inChannels - 1)] * gain
                    outSamples[frame * outChannels + channel] = gain > 1 ? value / (1 + abs(value) * 0.25) * 1.25 : value
                }
            }
            if frames < outFrames {
                memset(outSamples + frames * outChannels, 0, (outFrames - frames) * outChannels * MemoryLayout<Float>.size)
            }
        }
    }
}

// MARK: - CoreAudio helpers

enum AudioHW {
    struct OutputDevice: Identifiable, Hashable {
        let id: AudioObjectID
        let uid: String
        let name: String
    }

    struct AudioProcess {
        let object: AudioObjectID
        let pid: pid_t
        let bundleID: String?
        let name: String
        let isPlaying: Bool
        var key: String? { bundleID ?? name }
    }

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    static func audioProcesses() -> [AudioProcess] {
        ids(system, kAudioHardwarePropertyProcessObjectList).map { object in
            let pid = scalar(object, kAudioProcessPropertyPID, initial: pid_t(-1)) ?? -1
            let bundleID = string(object, kAudioProcessPropertyBundleID).flatMap { $0.isEmpty ? nil : $0 }
            let app = NSRunningApplication(processIdentifier: pid)
            let name = app?.localizedName ?? bundleID ?? "PID \(pid)"
            let playing = (scalar(object, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0)) ?? 0) != 0
            return AudioProcess(object: object, pid: pid, bundleID: bundleID ?? app?.bundleIdentifier, name: name, isPlaying: playing)
        }
    }

    static func outputDevices() -> [OutputDevice] {
        ids(system, kAudioHardwarePropertyDevices).compactMap { id in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0,
                  let uid = deviceUID(id), let name = string(id, kAudioObjectPropertyName), !name.hasPrefix("Lumo Mixer")
            else { return nil }
            return OutputDevice(id: id, uid: uid, name: name)
        }
    }

    static func defaultOutputDevice() -> AudioObjectID {
        scalar(system, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(kAudioObjectUnknown)) ?? AudioObjectID(kAudioObjectUnknown)
    }

    static func setDefaultOutputDevice(_ id: AudioObjectID) {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = id
        AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value)
    }

    static func deviceUID(_ id: AudioObjectID) -> String? {
        id == kAudioObjectUnknown ? nil : string(id, kAudioDevicePropertyDeviceUID)
    }

    static func scalar<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static func ids(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var items = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &items) == noErr else { return [] }
        return items
    }
}
