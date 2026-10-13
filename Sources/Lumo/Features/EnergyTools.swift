import AppKit
import IOKit.pwr_mgt
import LumoCore

/// Smarter "stay awake": while chosen apps run, while on power or with an external display;
/// plus lid-closed mode and Bluetooth off during sleep.
@MainActor
final class EnergyTools: ObservableObject {
    private enum Key {
        static let apps = "energy.awakeApps"
        static let onPower = "energy.awakeOnPower"
        static let withDisplay = "energy.awakeWithDisplay"
        static let bluetoothSleep = "energy.bluetoothSleep"
    }

    @Published var awakeApps: [String] { didSet { store.set(awakeApps, forKey: Key.apps); evaluate() } }
    @Published var awakeOnPower: Bool { didSet { store.set(awakeOnPower, forKey: Key.onPower); evaluate() } }
    @Published var awakeWithDisplay: Bool { didSet { store.set(awakeWithDisplay, forKey: Key.withDisplay); evaluate() } }
    @Published var bluetoothOnSleep: Bool { didSet { store.set(bluetoothOnSleep, forKey: Key.bluetoothSleep) } }
    /// Why the Mac is being kept awake right now, if a rule applies.
    @Published private(set) var activeReason: String?
    @Published private(set) var lidSleepDisabled = false
    @Published private(set) var isChangingLid = false

    var t = Localizer(language: .english)
    private let store: UserDefaults
    private var assertion: IOPMAssertionID?
    private var observers: [NSObjectProtocol] = []
    private var bluetoothTurnedOff = false

    init(store: UserDefaults) {
        self.store = store
        awakeApps = store.stringArray(forKey: Key.apps) ?? []
        awakeOnPower = store.bool(forKey: Key.onPower)
        awakeWithDisplay = store.bool(forKey: Key.withDisplay)
        bluetoothOnSleep = store.bool(forKey: Key.bluetoothSleep)
    }

    func start() {
        refreshLidState()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.willSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })
        evaluate()
    }

    func shutdown() {
        release()
    }

    var hasRules: Bool { !awakeApps.isEmpty || awakeOnPower || awakeWithDisplay || activeReason != nil }

    func toggleApp(_ bundleID: String) {
        awakeApps = awakeApps.contains(bundleID) ? awakeApps.filter { $0 != bundleID } : awakeApps + [bundleID]
    }

    // MARK: Rules

    /// Called every sample: holds a power assertion while any rule applies.
    func evaluate(battery: BatteryReading? = BatterySampler.read()) {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var reason: String?
        if let app = awakeApps.first(where: running.contains) {
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app).map { FileManager.default.displayName(atPath: $0.path) } ?? app
            reason = t("Открыто: ", "Open: ") + name.replacingOccurrences(of: ".app", with: "")
        } else if awakeOnPower, battery.map({ $0.isPluggedIn }) ?? true {
            reason = t("Mac на зарядке", "Mac is plugged in")
        } else if awakeWithDisplay, NSScreen.screens.contains(where: { !Self.isBuiltIn($0) }) {
            reason = t("Подключён монитор", "External display connected")
        }
        if reason != activeReason { activeReason = reason }
        reason == nil ? release() : hold()
    }

    private func hold() {
        guard assertion == nil else { return }
        var identifier: IOPMAssertionID = 0
        if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                       "Lumo: stay-awake rule" as CFString, &identifier) == kIOReturnSuccess {
            assertion = identifier
        }
    }

    private func release() {
        guard let assertion else { return }
        IOPMAssertionRelease(assertion)
        self.assertion = nil
    }

    static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    // MARK: Lid closed

    func refreshLidState() {
        Task.detached(priority: .utility) {
            let output = Self.run("/usr/bin/pmset", ["-g"])
            let disabled = output.components(separatedBy: .newlines).contains { $0.contains("SleepDisabled") && $0.trimmingCharacters(in: .whitespaces).hasSuffix("1") }
            await MainActor.run { [weak self] in self?.lidSleepDisabled = disabled }
        }
    }

    /// Keeps the Mac running with the lid closed. macOS asks for the administrator password each time.
    func setLidSleepDisabled(_ disabled: Bool) {
        guard !isChangingLid else { return }
        isChangingLid = true
        Task {
            let result = await AdminTasks.runAsAdmin(["/usr/bin/pmset", "-a", "disablesleep", disabled ? "1" : "0"],
                                                     prompt: disabled ? t("Lumo: не засыпать с закрытой крышкой.", "Lumo: stay awake with the lid closed.")
                                                                      : t("Lumo: снова засыпать с закрытой крышкой.", "Lumo: sleep with the lid closed again."), t: t)
            isChangingLid = false
            if case .failure(let failure) = result {
                Toast.show("xmark.octagon.fill", failure.message, tint: Palette.red.color)
            }
            refreshLidState()
        }
    }

    // MARK: Bluetooth during sleep

    private func willSleep() {
        guard bluetoothOnSleep, Bluetooth.isOn else { return }
        Bluetooth.setOn(false)
        bluetoothTurnedOff = true
    }

    private func didWake() {
        guard bluetoothTurnedOff else { return }
        bluetoothTurnedOff = false
        Bluetooth.setOn(true)
    }

    nonisolated private static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// The Bluetooth power switch (the same private call the menu bar's Bluetooth toggle uses).
enum Bluetooth {
    private typealias GetState = @convention(c) () -> Int32
    private typealias SetState = @convention(c) (Int32) -> Void
    private static let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY)

    static var isOn: Bool {
        guard let symbol = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState") else { return false }
        return unsafeBitCast(symbol, to: GetState.self)() != 0
    }

    static func setOn(_ on: Bool) {
        guard let symbol = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") else { return }
        unsafeBitCast(symbol, to: SetState.self)(on ? 1 : 0)
    }
}
