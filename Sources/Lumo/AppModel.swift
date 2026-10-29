import AppKit
import Combine
import LumoCore
import ServiceManagement
import SwiftUI

enum MenuBarText: String, CaseIterable, Identifiable {
    case none, cpu, memory, both, network

    var id: Self { self }

    func title(_ t: Localizer) -> String {
        switch self {
        case .none: return t("Только иконка", "Icon only")
        case .cpu: return "CPU %"
        case .memory: return t("Память %", "Memory %")
        case .both: return t("CPU и память", "CPU and memory")
        case .network: return t("Скорость сети", "Network speed")
        }
    }
}

/// Overview tiles the user can hide ("show only what you use").
enum OverviewTile: String, CaseIterable, Identifiable {
    case cores, network, battery, quickActions

    var id: Self { self }
}

@MainActor
final class AppModel: ObservableObject {
    enum Key {
        static let intensity = "intensity"
        static let autoEnabled = "autoEnabled"
        static let autoThreshold = "autoThreshold"
        static let closeApps = "closeApps"
        static let cleanCaches = "cleanCaches"
        static let purgeMemory = "purgeMemory"
        static let animateIcon = "animateIcon"
        static let menuBarText = "menuBarText"
        static let exceptions = "exceptions"
        static let language = "language"
        static let alerts = "alerts"
        static let hiddenTiles = "hiddenTiles"
        static let onboardingDone = "onboardingDone"
        static let keepDisplayAwake = "keepDisplayAwake"
        static let readouts = "readouts"
        static let readoutBars = "readoutBars"
    }

    static let autoThresholdRange = 0.1...1.0

    // MARK: Live state

    @Published private(set) var snapshot = MonitorSnapshot.empty
    @Published var groups: [UsageGroup] = []
    @Published var ports: [ListeningPort] = []
    @Published var isOptimizing = false
    @Published var lastReport: OptimizationReport?
    @Published var errorMessage: String?
    @Published var completedRuns = 0
    @Published var passwordlessPurge = false
    @Published var isConfiguringPurge = false
    @Published var keepAwake = KeepAwakeState.off
    @Published var darkMode = false
    @Published var desktopIconsHidden = false
    @Published private(set) var gpuLoad: Double?
    @Published private(set) var systemWatts: Double?

    // MARK: Settings

    @Published var intensity: Double { didSet { store.set(intensity, forKey: Key.intensity) } }
    @Published var autoEnabled: Bool { didSet { store.set(autoEnabled, forKey: Key.autoEnabled) } }
    @Published var autoThreshold: Double {
        didSet {
            store.set(autoThreshold, forKey: Key.autoThreshold)
            trigger.threshold = autoThreshold
        }
    }
    @Published var closeApps: Bool { didSet { store.set(closeApps, forKey: Key.closeApps) } }
    @Published var cleanCaches: Bool { didSet { store.set(cleanCaches, forKey: Key.cleanCaches) } }
    @Published var purgeMemory: Bool { didSet { store.set(purgeMemory, forKey: Key.purgeMemory) } }
    @Published var animateIcon: Bool { didSet { store.set(animateIcon, forKey: Key.animateIcon) } }
    @Published var menuBarText: MenuBarText { didSet { store.set(menuBarText.rawValue, forKey: Key.menuBarText) } }
    @Published var exceptions: [String] { didSet { store.set(exceptions, forKey: Key.exceptions) } }
    @Published var language: AppLanguage { didSet { store.set(language.rawValue, forKey: Key.language) } }
    @Published var enabledAlerts: Set<AlertKind> { didSet { store.set(enabledAlerts.map(\.rawValue), forKey: Key.alerts) } }
    @Published var hiddenTiles: Set<OverviewTile> { didSet { store.set(hiddenTiles.map(\.rawValue), forKey: Key.hiddenTiles) } }
    @Published var onboardingDone: Bool { didSet { store.set(onboardingDone, forKey: Key.onboardingDone) } }
    @Published var keepDisplayAwake: Bool { didSet { store.set(keepDisplayAwake, forKey: Key.keepDisplayAwake) } }
    @Published var readouts: Set<Readout> { didSet { store.set(readouts.map(\.rawValue), forKey: Key.readouts) } }
    @Published var readoutBars: Bool { didSet { store.set(readoutBars, forKey: Key.readoutBars) } }

    // MARK: Collaborators (used by the AppModel+Actions extension)

    let store: UserDefaults
    let monitor = MonitorService()
    let optimizer = Optimizer()
    let keepAwakeService = KeepAwakeService()
    let alerts = AlertService()
    let cleaner: CleanerStore
    let uninstaller = UninstallerStore()
    let sensors = SensorStore()
    let brew = BrewStore()
    let input: InputFeatures
    let clipboard: ClipboardStore
    let snippets: SnippetStore
    let capture: CaptureTools
    let recorder: ScreenRecorder
    let notes = NotesStore()
    let agents = AgentUsageStore()
    let commandBar: CommandBar
    let island: DynamicIsland
    let mixer: VolumeMixer
    let shelf: ShelfStore
    let audio: AudioDevices
    let clipExtras: ClipboardExtras
    let shelfPanel: ShelfPanelController
    let dmgInstaller: DMGInstaller
    let messaging: MessagingDownloads
    let power: EnergyTools
    let hub: FeatureHub
    let displayTools: DisplayTools
    let quickPanel: QuickPanel
    let radial: RadialMenu
    let scratchpad: ScratchpadWindow
    let cleaning = CleaningMode()
    let cameraMirror = CameraMirror()
    let energy = EnergyMonitor()
    let speedTest = SpeedTester()
    let fanControl = FanControl()
    let feedUpdates = FeedUpdates()
    /// Set while the Sensors page is on screen, so sensors are only polled when someone looks.
    var sensorsVisible = false
    var trigger: AutoTrigger
    var lastRecords: [ProcessRecord] = []
    var isScanning = false
    /// Animations in the popover pause while it is closed.
    @Published private(set) var isPopoverVisible = false
    var lastUserFrontmostPID: pid_t?
    var keepAwakeTimer: Timer?
    private var sampleTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(store: UserDefaults = .standard) {
        store.register(defaults: [
            Key.intensity: 0.5, Key.autoEnabled: false, Key.autoThreshold: 0.9, Key.closeApps: false,
            Key.cleanCaches: false, Key.purgeMemory: false, Key.animateIcon: true,
            Key.menuBarText: MenuBarText.cpu.rawValue, Key.exceptions: [String](),
            Key.language: AppLanguage.systemDefault.rawValue, Key.alerts: [String](), Key.hiddenTiles: [String](),
            Key.onboardingDone: false, Key.keepDisplayAwake: false, Key.readouts: [String](),
        ])
        let range = Self.autoThresholdRange
        let threshold = min(max(store.double(forKey: Key.autoThreshold), range.lowerBound), range.upperBound)
        self.store = store
        intensity = store.double(forKey: Key.intensity)
        autoEnabled = store.bool(forKey: Key.autoEnabled)
        autoThreshold = threshold
        closeApps = store.bool(forKey: Key.closeApps)
        cleanCaches = store.bool(forKey: Key.cleanCaches)
        purgeMemory = store.bool(forKey: Key.purgeMemory)
        animateIcon = store.bool(forKey: Key.animateIcon)
        menuBarText = MenuBarText(rawValue: store.string(forKey: Key.menuBarText) ?? "") ?? .cpu
        exceptions = store.stringArray(forKey: Key.exceptions) ?? []
        language = AppLanguage(rawValue: store.string(forKey: Key.language) ?? "") ?? .systemDefault
        enabledAlerts = Set((store.stringArray(forKey: Key.alerts) ?? []).compactMap(AlertKind.init(rawValue:)))
        hiddenTiles = Set((store.stringArray(forKey: Key.hiddenTiles) ?? []).compactMap(OverviewTile.init(rawValue:)))
        onboardingDone = store.bool(forKey: Key.onboardingDone)
        keepDisplayAwake = store.bool(forKey: Key.keepDisplayAwake)
        readouts = Set((store.stringArray(forKey: Key.readouts) ?? []).compactMap(Readout.init(rawValue:)))
        readoutBars = store.bool(forKey: Key.readoutBars)
        cleaner = CleanerStore(store: store)
        input = InputFeatures(store: store)
        clipboard = ClipboardStore(store: store)
        snippets = SnippetStore(store: store)
        capture = CaptureTools(store: store)
        recorder = ScreenRecorder(store: store)
        commandBar = CommandBar(store: store)
        island = DynamicIsland(store: store)
        mixer = VolumeMixer(store: store)
        shelf = ShelfStore(store: store)
        audio = AudioDevices(store: store)
        clipExtras = ClipboardExtras(store: store)
        shelfPanel = ShelfPanelController(shelf: shelf, store: store)
        dmgInstaller = DMGInstaller(store: store)
        messaging = MessagingDownloads(store: store)
        power = EnergyTools(store: store)
        hub = FeatureHub(store: store)
        displayTools = DisplayTools(store: store)
        quickPanel = QuickPanel(store: store)
        radial = RadialMenu(store: store)
        scratchpad = ScratchpadWindow(notes: notes)
        trigger = AutoTrigger(threshold: threshold)
    }

    // MARK: Derived

    var t: Localizer { Localizer(language: language) }
    var policy: OptimizationPolicy { OptimizationPolicy(intensity: intensity) }
    var plan: [PlanItem] { OptimizationPlanner.plan(groups, policy: policy, closeApps: closeApps) }
    var cpuLoad: Double { snapshot.cpuLoad }
    var memory: MemoryUsage { snapshot.memory }
    var systemLoad: Double { snapshot.systemLoad }
    var healthLoad: Double { snapshot.healthLoad }
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func isTileVisible(_ tile: OverviewTile) -> Bool { !hiddenTiles.contains(tile) }

    func setTile(_ tile: OverviewTile, visible: Bool) {
        hiddenTiles = visible ? hiddenTiles.subtracting([tile]) : hiddenTiles.union([tile])
    }

    // MARK: Lifecycle

    func start() {
        lastUserFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        observeSystem()
        refreshPasswordlessStatus()
        refreshQuickToggles()
        monitor.prime()
        input.localizer = t
        input.apply()
        capture.onRecordToggle = { [weak recorder] in recorder?.toggle() }
        capture.recorder = recorder
        commandBar.clipboard = clipboard
        commandBar.snippets = snippets
        commandBar.actions = { [weak self] in self?.commands() ?? [] }
        island.model = self
        Toast.island = island
        audio.start()
        clipExtras.start()
        agents.onTaskFinished = { [weak self] agent, project in self?.announceFinished(agent, project: project) }
        shelfPanel.start()
        dmgInstaller.start()
        quickPanel.model = self
        hub.model = self
        radial.model = self
        clipExtras.onChange = { [weak self] in self?.input.apply() }
        input.externalHandlers = { [weak self] in (self?.clipExtras.handlers ?? []) + (self?.displayTools.handlers ?? []) }
        displayTools.onChange = { [weak self] in self?.input.apply() }
        displayTools.refresh()
        power.start()
        input.keyboard.perform = { [weak self] action in
            switch action {
            case .commandBar: self?.commandBar.toggle()
            case .quickPanel: self?.quickPanel.toggle()
            default: break
            }
        }
        island.start()
        mixer.refresh()
        applyLanguage()
        sample()
        scheduleSampling()
    }

    /// On battery or in Low Power Mode Lumo samples less often and keeps the menu bar icon still.
    var isSavingPower: Bool {
        (snapshot.battery.map { !$0.isPluggedIn } ?? false) || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// Re-arms the sample timer when the right cadence changes (popover, readouts, power source).
    private func scheduleSampling() {
        let interval = SampleCadence.interval(
            foreground: isPopoverVisible || sensorsVisible || island.isExpanded,
            liveReadouts: !readouts.isEmpty,
            onBattery: snapshot.battery.map { !$0.isPluggedIn } ?? false,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
        guard sampleTimer?.timeInterval != interval else { return }
        sampleTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
    }

    func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
        scheduleSampling()
        guard visible else { return }
        refreshProcesses()
        refreshPorts()
        refreshQuickToggles()
    }

    private func sample() {
        let now = Date()
        let wantsSensors = sensorsVisible || readouts.contains(.temperature) || readouts.contains(.fan)
            || enabledAlerts.contains(.temperature) || island.isExpanded
        if wantsSensors { sensors.sample() }
        // GPU and power reads walk the I/O Registry, so they run only while something shows them.
        if sensorsVisible || island.isExpanded || readouts.contains(.gpu) || readouts.contains(.power) || isPopoverVisible {
            gpuLoad = HardwareExtras.gpuUtilization()
            systemWatts = HardwareExtras.systemPowerWatts()
        }
        snapshot = monitor.sample(after: snapshot, now: now)
        cleaner.autoCleanIfDue(now: now)
        messaging.autoCleanIfDue(now: now)
        if power.hasRules { power.evaluate(battery: snapshot.battery) }
        input.refreshPermissions()
        snippets.refreshPermission()
        if input.localizer.language != language { applyLanguage() }
        if isPopoverVisible { refreshProcesses() }
        alerts.evaluate(snapshot, temperature: sensors.socTemperature, enabled: enabledAlerts, t: t, now: now)
        if autoEnabled, !isOptimizing, trigger.feed(load: systemLoad, now: now) {
            optimize(automatic: true)
        }
        scheduleSampling()
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.noteActivated(pid: pid) }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshQuickToggles() }
        })
    }

    private func applyLanguage() {
        input.localizer = t
        capture.t = t
        recorder.t = t
        commandBar.t = t
        audio.t = t
        clipExtras.t = t
        shelfPanel.t = t
        dmgInstaller.t = t
        messaging.t = t
        power.t = t
        displayTools.t = t
        radial.t = t
        scratchpad.t = t
        cleaning.t = t
    }

    /// Lumo's own commands for the Command Bar: every one-tap tool.
    private func commands() -> [CommandBar.Command] {
        let t = t
        return LumoTool.allCases.map { tool in
            CommandBar.Command(id: "lumo.\(tool.rawValue)", title: tool.title(t), subtitle: "Lumo", icon: .symbol(tool.symbol, tool.colors)) {
                [weak self] in
                guard let self else { return }
                tool.run(self)
            }
        }
    }

    private func noteActivated(pid: pid_t?) {
        guard let pid, pid != getpid() else { return }
        lastUserFrontmostPID = pid
    }
}
