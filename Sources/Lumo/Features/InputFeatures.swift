import AppKit
import LumoCore

/// Settings and lifecycle for every window/keyboard/mouse tool. Owns the shared event tap and
/// rebuilds it whenever a setting or the Accessibility permission changes.
@MainActor
final class InputFeatures: ObservableObject {
    private enum Key {
        static let windowShortcuts = "input.windowShortcuts"
        static let snapByDragging = "input.snapByDragging"
        static let guardQuit = "input.guardQuit"
        static let guardClose = "input.guardClose"
        static let quitMode = "input.quitMode"
        static let quitExceptions = "input.quitExceptions"
        static let smoothScroll = "input.smoothScroll"
        static let smoothness = "input.smoothness"
        static let reverseMouse = "input.reverseMouse"
        static let sideButtons = "input.sideButtons"
        static let linearPointer = "input.linearPointer"
        static let linearPointerBefore = "input.linearPointerBefore"
        static let switcher = "input.switcher"
        static let switcherPreviews = "input.switcherPreviews"
        static let switcherCurrentDisplay = "input.switcherCurrentDisplay"
        static let switcherPerWindow = "input.switcherPerWindow"
        static let modifierDrag = "input.modifierDrag"
        static let linearScroll = "mouse.linearScroll"
        static let linesPerNotch = "mouse.linesPerNotch"
        static let sideways = "mouse.sideways"
        static let buttonActions = "mouse.buttonActions"
        static let tiltLeft = "mouse.tiltLeft"
        static let tiltRight = "mouse.tiltRight"
        static let gestures = "mouse.gestures"
        static let threeFinger = "mouse.threeFinger"
        static let focusFollows = "mouse.focusFollows"
        static let focusDelay = "mouse.focusDelay"
        static let clickFilter = "mouse.clickFilter"
        static let clickThreshold = "mouse.clickThreshold"
        static let mouseExclusions = "mouse.exclusions"
    }

    @Published var windowShortcuts: Bool { didSet { save(windowShortcuts, Key.windowShortcuts) } }
    @Published var snapByDragging: Bool { didSet { save(snapByDragging, Key.snapByDragging) } }
    @Published var guardQuit: Bool { didSet { save(guardQuit, Key.guardQuit) } }
    @Published var guardClose: Bool { didSet { save(guardClose, Key.guardClose) } }
    @Published var quitMode: QuitGuard.Mode { didSet { save(quitMode.rawValue, Key.quitMode) } }
    @Published var quitExceptions: [String] { didSet { save(quitExceptions, Key.quitExceptions) } }
    @Published var smoothScroll: Bool { didSet { save(smoothScroll, Key.smoothScroll) } }
    @Published var smoothness: Double { didSet { save(smoothness, Key.smoothness) } }
    @Published var reverseMouse: Bool { didSet { save(reverseMouse, Key.reverseMouse) } }
    @Published var sideButtons: Bool { didSet { save(sideButtons, Key.sideButtons) } }
    @Published var linearPointer: Bool {
        didSet {
            if linearPointer {
                store.set(PointerAcceleration.isLinear, forKey: Key.linearPointerBefore)
                PointerAcceleration.setLinear(true)
            } else {
                PointerAcceleration.setLinear(store.bool(forKey: Key.linearPointerBefore))
            }
            save(linearPointer, Key.linearPointer)
        }
    }
    @Published var switcherEnabled: Bool { didSet { save(switcherEnabled, Key.switcher) } }
    @Published var switcherPreviews: Bool { didSet { save(switcherPreviews, Key.switcherPreviews) } }
    @Published var switcherCurrentDisplay: Bool { didSet { save(switcherCurrentDisplay, Key.switcherCurrentDisplay) } }
    @Published var switcherPerWindow: Bool { didSet { save(switcherPerWindow, Key.switcherPerWindow) } }
    @Published var modifierDrag: Bool { didSet { save(modifierDrag, Key.modifierDrag) } }
    @Published var linearScroll: Bool { didSet { save(linearScroll, Key.linearScroll) } }
    @Published var linesPerNotch: Int { didSet { save(linesPerNotch, Key.linesPerNotch) } }
    @Published var sideways: SidewaysModifier { didSet { save(sideways.rawValue, Key.sideways) } }
    @Published var buttonActions: [Int: MouseAction] {
        didSet { save(Dictionary(uniqueKeysWithValues: buttonActions.map { (String($0.key), $0.value.rawValue) }), Key.buttonActions) }
    }
    @Published var tiltLeft: MouseAction { didSet { save(tiltLeft.rawValue, Key.tiltLeft) } }
    @Published var tiltRight: MouseAction { didSet { save(tiltRight.rawValue, Key.tiltRight) } }
    @Published var gestures: Bool { didSet { save(gestures, Key.gestures) } }
    @Published var threeFingerMiddleClick: Bool { didSet { save(threeFingerMiddleClick, Key.threeFinger) } }
    @Published var focusFollowsMouse: Bool { didSet { save(focusFollowsMouse, Key.focusFollows) } }
    @Published var focusDelay: Double { didSet { save(focusDelay, Key.focusDelay) } }
    @Published var clickFilter: Bool { didSet { save(clickFilter, Key.clickFilter) } }
    @Published var clickThreshold: Double { didSet { save(clickThreshold, Key.clickThreshold) } }
    @Published var mouseExclusions: [String] { didSet { save(mouseExclusions, Key.mouseExclusions) } }

    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var screenRecordingGranted = CGPreflightScreenCaptureAccess()

    let windows = WindowManager()
    let quitProtection = QuitProtection()
    let mouse = MouseTools()
    let switcher = AppSwitcher()
    let dock: DockTools
    let keyboard: KeyboardTools
    /// Event-tap handlers owned by other features (Finder shortcuts), merged into the shared tap.
    var externalHandlers: () -> [(mask: CGEventMask, handle: InputTap.Handler)] = { [] }
    var localizer = Localizer(language: .english) { didSet { quitProtection.t = localizer } }

    private let store: UserDefaults
    private let tap = InputTap()

    init(store: UserDefaults) {
        store.register(defaults: [Key.quitMode: QuitGuard.Mode.hold.rawValue, Key.smoothness: 0.5, Key.switcherPreviews: true,
                                  Key.linesPerNotch: 3, Key.focusDelay: 0.4, Key.clickThreshold: 0.06])
        self.store = store
        windowShortcuts = store.bool(forKey: Key.windowShortcuts)
        snapByDragging = store.bool(forKey: Key.snapByDragging)
        guardQuit = store.bool(forKey: Key.guardQuit)
        guardClose = store.bool(forKey: Key.guardClose)
        quitMode = QuitGuard.Mode(rawValue: store.string(forKey: Key.quitMode) ?? "") ?? .hold
        quitExceptions = store.stringArray(forKey: Key.quitExceptions) ?? []
        smoothScroll = store.bool(forKey: Key.smoothScroll)
        smoothness = store.double(forKey: Key.smoothness)
        reverseMouse = store.bool(forKey: Key.reverseMouse)
        sideButtons = store.bool(forKey: Key.sideButtons)
        linearPointer = store.bool(forKey: Key.linearPointer)
        switcherEnabled = store.bool(forKey: Key.switcher)
        switcherPreviews = store.bool(forKey: Key.switcherPreviews)
        switcherCurrentDisplay = store.bool(forKey: Key.switcherCurrentDisplay)
        switcherPerWindow = store.bool(forKey: Key.switcherPerWindow)
        modifierDrag = store.bool(forKey: Key.modifierDrag)
        linearScroll = store.bool(forKey: Key.linearScroll)
        linesPerNotch = max(store.integer(forKey: Key.linesPerNotch), 1)
        sideways = SidewaysModifier(rawValue: store.string(forKey: Key.sideways) ?? "") ?? .none
        let savedButtons = store.dictionary(forKey: Key.buttonActions) as? [String: String] ?? [:]
        buttonActions = Dictionary(uniqueKeysWithValues: savedButtons.compactMap { key, value in
            Int(key).flatMap { button in MouseAction(rawValue: value).map { (button, $0) } }
        })
        tiltLeft = MouseAction(rawValue: store.string(forKey: Key.tiltLeft) ?? "") ?? .none
        tiltRight = MouseAction(rawValue: store.string(forKey: Key.tiltRight) ?? "") ?? .none
        gestures = store.bool(forKey: Key.gestures)
        threeFingerMiddleClick = store.bool(forKey: Key.threeFinger)
        focusFollowsMouse = store.bool(forKey: Key.focusFollows)
        focusDelay = store.double(forKey: Key.focusDelay)
        clickFilter = store.bool(forKey: Key.clickFilter)
        clickThreshold = store.double(forKey: Key.clickThreshold)
        mouseExclusions = store.stringArray(forKey: Key.mouseExclusions) ?? []
        dock = DockTools(store: store)
        keyboard = KeyboardTools(store: store)
        dock.onChange = { [weak self] in self?.apply() }
        keyboard.onChange = { [weak self] in self?.apply() }
    }

    var usesAccessibility: Bool {
        windowShortcuts || snapByDragging || guardQuit || guardClose || smoothScroll || reverseMouse || sideButtons || switcherEnabled
            || modifierDrag || dock.usesAccessibility || keyboard.usesTap || linearScroll || sideways != .none || gestures
            || threeFingerMiddleClick || focusFollowsMouse || clickFilter || buttonActions.values.contains { $0 != .none }
            || tiltLeft != .none || tiltRight != .none
    }

    func refreshPermissions() {
        let accessibility = AXIsProcessTrusted()
        let screen = CGPreflightScreenCaptureAccess()
        if screen != screenRecordingGranted { screenRecordingGranted = screen }
        guard accessibility != accessibilityGranted else { return }
        accessibilityGranted = accessibility
        apply()
    }

    func apply() {
        windows.setShortcuts(enabled: windowShortcuts)
        quitProtection.guardQuit = guardQuit
        quitProtection.guardClose = guardClose
        quitProtection.mode = quitMode
        quitProtection.exceptions = Set(quitExceptions)
        mouse.smoothScroll = smoothScroll
        mouse.smoothness = smoothness
        mouse.reverseMouse = reverseMouse
        mouse.sideButtons = sideButtons
        mouse.linearScroll = linearScroll
        mouse.linesPerNotch = linesPerNotch
        mouse.sideways = sideways
        mouse.buttonActions = buttonActions
        mouse.tiltLeft = tiltLeft
        mouse.tiltRight = tiltRight
        mouse.gestures = gestures
        if mouse.threeFingerMiddleClick != threeFingerMiddleClick { mouse.threeFingerMiddleClick = threeFingerMiddleClick }
        mouse.focusFollowsMouse = focusFollowsMouse
        mouse.focusDelay = focusDelay
        mouse.clickFilter = clickFilter
        mouse.clickThreshold = clickThreshold
        mouse.excludedApps = Set(mouseExclusions)
        switcher.showsPreviews = switcherPreviews
        switcher.currentDisplayOnly = switcherCurrentDisplay
        switcher.perWindow = switcherPerWindow

        let switcherLive = switcherEnabled && accessibilityGranted
        switcher.setSystemSwitcherEnabled(!switcherLive)

        var handlers: [(mask: CGEventMask, handle: InputTap.Handler)] = []
        if switcherEnabled { handlers.append(switcher.keyHandler) }
        if guardQuit || guardClose { handlers.append(quitProtection.keyHandler) }
        if modifierDrag { handlers.append(windows.modifierDragHandler) }
        if snapByDragging { handlers.append(windows.dragHandler) }
        handlers += dock.handlers
        handlers += mouse.handlers
        handlers += keyboard.handlers
        handlers += externalHandlers()
        tap.configure(handlers)
    }

    /// Hands ⌘Tab back to macOS; called when Lumo quits.
    func shutdown() {
        tap.stop()
        keyboard.shutdown()
        switcher.setSystemSwitcherEnabled(true)
    }

    func toggleMouseExclusion(_ bundleID: String) {
        mouseExclusions = mouseExclusions.contains(bundleID) ? mouseExclusions.filter { $0 != bundleID } : mouseExclusions + [bundleID]
    }

    func toggleException(_ bundleID: String) {
        quitExceptions = quitExceptions.contains(bundleID) ? quitExceptions.filter { $0 != bundleID } : quitExceptions + [bundleID]
    }

    private func save(_ value: Any, _ key: String) {
        store.set(value, forKey: key)
        apply()
    }
}
