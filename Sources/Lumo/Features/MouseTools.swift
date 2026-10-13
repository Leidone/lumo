import AppKit
import ApplicationServices
import IOKit
import LumoCore

/// Things an extra mouse button, a side-wheel tilt or a button-drag gesture can do.
enum MouseAction: String, CaseIterable, Identifiable, Codable {
    case none, back, forward, middleClick, missionControl, appExpose, desktopLeft, desktopRight, showDesktop, launchpad, copy, paste

    var id: Self { self }

    func title(_ t: Localizer) -> String {
        switch self {
        case .none: return t("Ничего", "Nothing")
        case .back: return t("Назад", "Back")
        case .forward: return t("Вперёд", "Forward")
        case .middleClick: return t("Средний клик", "Middle click")
        case .missionControl: return "Mission Control"
        case .appExpose: return t("Окна приложения", "App Exposé")
        case .desktopLeft: return t("Стол слева", "Space to the left")
        case .desktopRight: return t("Стол справа", "Space to the right")
        case .showDesktop: return t("Показать рабочий стол", "Show desktop")
        case .launchpad: return t("Приложения", "Apps")
        case .copy: return t("Скопировать", "Copy")
        case .paste: return t("Вставить", "Paste")
        }
    }
}

enum SidewaysModifier: String, CaseIterable, Identifiable {
    case none, shift, option, control

    var id: Self { self }
    var flag: CGEventFlags? {
        switch self {
        case .none: return nil
        case .shift: return .maskShift
        case .option: return .maskAlternate
        case .control: return .maskControl
        }
    }
}

/// Everything Lumo does to the mouse. Trackpads and the Magic Mouse send continuous events,
/// so scrolling changes never touch them.
@MainActor
final class MouseTools {
    private static let pixelsPerLine = 40.0
    private static let frameInterval = 1.0 / 120
    private static let backKey: CGKeyCode = 33 // [
    private static let forwardKey: CGKeyCode = 30 // ]
    private static let gestureThreshold = 80.0

    // Scrolling
    var smoothScroll = false
    var smoothness = 0.5 { didSet { resetGlides() } }
    var reverseMouse = false
    var linearScroll = false
    var linesPerNotch = 3
    var sideways = SidewaysModifier.none
    // Buttons
    var sideButtons = false
    var buttonActions: [Int: MouseAction] = [:]
    var tiltLeft = MouseAction.none
    var tiltRight = MouseAction.none
    var gestures = false
    var gestureActions: [MouseGesture: MouseAction] = [.left: .desktopLeft, .right: .desktopRight, .up: .missionControl, .down: .appExpose]
    var threeFingerMiddleClick = false { didSet { threeFingerMiddleClick ? Multitouch.shared.start() : Multitouch.shared.stop() } }
    // Behaviour
    var focusFollowsMouse = false
    var focusDelay = 0.4
    var clickFilter = false { didSet { clickDebouncer = PressDebouncer(threshold: clickThreshold) } }
    var clickThreshold = 0.06 { didSet { clickDebouncer = PressDebouncer(threshold: clickThreshold) } }
    var excludedApps: Set<String> = []

    private var vertical = ScrollGlide(response: 0.2)
    private var horizontal = ScrollGlide(response: 0.2)
    private var timer: DispatchSourceTimer?
    private var swallowedUps: Set<Int64> = []
    private var gestureStart: CGPoint?
    private var gestureMoved = CGPoint.zero
    private var convertingMiddle = false
    private var clickDebouncer = PressDebouncer(threshold: 0.06)
    private var focusWork: DispatchWorkItem?
    private var lastFocusMove: TimeInterval = 0

    private var isExcluded: Bool {
        guard !excludedApps.isEmpty, let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return excludedApps.contains(id)
    }

    var handlers: [(mask: CGEventMask, handle: InputTap.Handler)] {
        var result: [(mask: CGEventMask, handle: InputTap.Handler)] = []
        if clickFilter {
            result.append((InputTap.mask(.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp), { [weak self] type, event in
                self?.filterClick(type, event) ?? event
            }))
        }
        if threeFingerMiddleClick {
            result.append((InputTap.mask(.leftMouseDown, .leftMouseDragged, .leftMouseUp), { [weak self] type, event in
                self?.convertThreeFinger(type, event) ?? event
            }))
        }
        if smoothScroll || reverseMouse || linearScroll || sideways != .none || tiltLeft != .none || tiltRight != .none {
            result.append((InputTap.mask(.scrollWheel), { [weak self] _, event in self?.handleScroll(event) ?? event }))
        }
        if sideButtons || gestures || buttonActions.values.contains(where: { $0 != .none }) {
            result.append((InputTap.mask(.otherMouseDown, .otherMouseDragged, .otherMouseUp), { [weak self] type, event in
                self?.handleButton(type, event) ?? event
            }))
        }
        if focusFollowsMouse {
            result.append((InputTap.mask(.mouseMoved), { [weak self] _, event in
                self?.pointerMoved(event.location)
                return event
            }))
        }
        return result
    }

    // MARK: Scrolling

    private func handleScroll(_ event: CGEvent) -> CGEvent? {
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0, !isExcluded else { return event }
        // Side wheel tilts can trigger actions instead of scrolling sideways.
        let tilt = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        if tilt != 0, event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 0 {
            let action = tilt > 0 ? tiltLeft : tiltRight
            if action != .none {
                perform(action)
                return nil
            }
        }
        if let flag = sideways.flag, event.flags.contains(flag) { Self.swapAxes(event) }
        if reverseMouse { Self.reverse(event) }
        if linearScroll { Self.linearize(event, lines: linesPerNotch) }
        guard smoothScroll else { return event }
        let lines = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let columns = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        if lines != 0 { vertical.add(lines * Self.pixelsPerLine) }
        if columns != 0 { horizontal.add(columns * Self.pixelsPerLine) }
        startGlide()
        return nil
    }

    private static let axes: [(CGEventField, CGEventField, CGEventField)] = [
        (.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1),
        (.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2),
    ]

    private static func reverse(_ event: CGEvent) {
        for (delta, point, fixed) in axes {
            event.setIntegerValueField(delta, value: -event.getIntegerValueField(delta))
            event.setIntegerValueField(point, value: -event.getIntegerValueField(point))
            event.setDoubleValueField(fixed, value: -event.getDoubleValueField(fixed))
        }
    }

    /// Every notch moves the same number of lines, however fast the wheel spins.
    private static func linearize(_ event: CGEvent, lines: Int) {
        for (delta, point, fixed) in axes {
            let value = event.getIntegerValueField(delta)
            guard value != 0 else { continue }
            let sign: Int64 = value > 0 ? 1 : -1
            event.setIntegerValueField(delta, value: sign * Int64(lines))
            event.setIntegerValueField(point, value: sign * Int64(lines) * Int64(pixelsPerLine / 4))
            event.setDoubleValueField(fixed, value: Double(sign) * Double(lines))
        }
    }

    private static func swapAxes(_ event: CGEvent) {
        let (delta1, point1, fixed1) = axes[0]
        let (delta2, point2, fixed2) = axes[1]
        let values = (event.getIntegerValueField(delta1), event.getIntegerValueField(point1), event.getDoubleValueField(fixed1))
        event.setIntegerValueField(delta1, value: event.getIntegerValueField(delta2))
        event.setIntegerValueField(point1, value: event.getIntegerValueField(point2))
        event.setDoubleValueField(fixed1, value: event.getDoubleValueField(fixed2))
        event.setIntegerValueField(delta2, value: values.0)
        event.setIntegerValueField(point2, value: values.1)
        event.setDoubleValueField(fixed2, value: values.2)
    }

    private func resetGlides() {
        let response = 0.08 + (1 - smoothness) * 0.32
        vertical = ScrollGlide(response: response)
        horizontal = ScrollGlide(response: response)
    }

    private func startGlide() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: Self.frameInterval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.emitFrame() } }
        timer.resume()
        self.timer = timer
    }

    private func emitFrame() {
        let dy = vertical.step()
        let dx = horizontal.step()
        if dy != 0 || dx != 0,
           let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                               wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) {
            event.setIntegerValueField(.eventSourceUserData, value: InputTap.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
        if vertical.isIdle && horizontal.isIdle {
            timer?.cancel()
            timer = nil
        }
    }

    // MARK: Buttons and gestures

    private func handleButton(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        guard !isExcluded else { return event }
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let mapped = buttonActions[button] ?? .none
        let usesGesture = gestures && button == 2
        let usesSide = sideButtons && (button == 3 || button == 4) && mapped == .none
        guard usesGesture || usesSide || mapped != .none else { return event }

        switch type {
        case .otherMouseDown:
            swallowedUps.insert(Int64(button))
            if usesGesture {
                gestureStart = event.location
                gestureMoved = .zero
            } else if usesSide {
                Self.pressCommand(button == 3 ? Self.backKey : Self.forwardKey)
            } else {
                perform(mapped)
            }
            return nil
        case .otherMouseDragged:
            if usesGesture, let start = gestureStart {
                gestureMoved = CGPoint(x: event.location.x - start.x, y: event.location.y - start.y)
                return nil
            }
            return event
        default: // up
            guard swallowedUps.remove(Int64(button)) != nil else { return event }
            if usesGesture {
                defer { gestureStart = nil }
                if let direction = MouseGesture.direction(dx: gestureMoved.x, dy: gestureMoved.y, threshold: Self.gestureThreshold) {
                    perform(gestureActions[direction] ?? .none)
                } else if mapped != .none {
                    perform(mapped)
                } else {
                    Self.postMiddleClick(at: event.location)
                }
            }
            return nil
        }
    }

    func perform(_ action: MouseAction) {
        switch action {
        case .none: break
        case .back: Self.pressCommand(Self.backKey)
        case .forward: Self.pressCommand(Self.forwardKey)
        case .middleClick: Self.postMiddleClick(at: CGEvent(source: nil)?.location ?? .zero)
        case .missionControl: Self.open("/System/Applications/Mission Control.app")
        case .appExpose: Self.open("/System/Applications/Mission Control.app", arguments: ["2"])
        case .desktopLeft: Self.pressKey(123, flags: .maskControl)
        case .desktopRight: Self.pressKey(124, flags: .maskControl)
        case .showDesktop: Self.open("/System/Applications/Mission Control.app", arguments: ["1"])
        case .launchpad:
            let apps = ["/System/Applications/Apps.app", "/System/Applications/Launchpad.app"]
            apps.first(where: FileManager.default.fileExists(atPath:)).map { Self.open($0) }
        case .copy: Self.pressKey(8, flags: .maskCommand)
        case .paste: Self.pressKey(9, flags: .maskCommand)
        }
    }

    private static func open(_ path: String, arguments: [String] = []) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration)
    }

    private static func pressCommand(_ key: CGKeyCode) { pressKey(key, flags: .maskCommand) }

    private static func pressKey(_ key: CGKeyCode, flags: CGEventFlags) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: InputTap.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    private static func postMiddleClick(at point: CGPoint) {
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .center) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: InputTap.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: Three-finger middle click

    private func convertThreeFinger(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if type == .leftMouseDown { convertingMiddle = Multitouch.shared.fingers == 3 && !isExcluded }
        guard convertingMiddle else { return event }
        switch type {
        case .leftMouseDown: event.type = .otherMouseDown
        case .leftMouseDragged: event.type = .otherMouseDragged
        default:
            event.type = .otherMouseUp
            convertingMiddle = false
        }
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        return event
    }

    // MARK: Click filter

    private func filterClick(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        let now = ProcessInfo.processInfo.systemUptime
        let key: Int64 = (type == .leftMouseDown || type == .leftMouseUp) ? 0 : 1
        let drop = (type == .leftMouseDown || type == .rightMouseDown)
            ? clickDebouncer.dropDown(key: key, at: now)
            : clickDebouncer.dropUp(key: key, at: now)
        return drop ? nil : event
    }

    // MARK: Focus follows mouse

    private func pointerMoved(_ point: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFocusMove > 0.05 else { return }
        lastFocusMove = now
        focusWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.focusWindow(at: point) }
        focusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + focusDelay, execute: work)
    }

    private func focusWindow(at point: CGPoint) {
        guard NSEvent.pressedMouseButtons == 0, !isExcluded,
              let current = CGEvent(source: nil)?.location, hypot(current.x - point.x, current.y - point.y) < 4,
              let top = AppSwitcher.onScreenWindows().first(where: { $0.bounds.contains(point) }),
              top.pid != NSWorkspace.shared.frontmostApplication?.processIdentifier, top.pid != getpid(),
              let app = NSRunningApplication(processIdentifier: top.pid), app.activationPolicy == .regular,
              let window = AXWindow.window(at: point)
        else { return }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        app.activate()
    }
}

/// The same switch as System Settings → Mouse → Pointer acceleration (macOS 14+).
enum PointerAcceleration {
    private static let key = "com.apple.mouse.linear" as CFString
    private static let hidKey = "HIDUseLinearScalingMouseAcceleration" as CFString

    static var isLinear: Bool {
        (CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Bool) ?? false
    }

    static func setLinear(_ linear: Bool) {
        CFPreferencesSetValue(key, linear as CFBoolean, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        applyLive(linear)
    }

    /// Pushes the value to the HID system so it takes effect without logging out.
    private static func applyLive(_ linear: Bool) {
        typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
        typealias SetProperty = @convention(c) (AnyObject, CFString, AnyObject) -> Bool
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let createSymbol = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let setSymbol = dlsym(handle, "IOHIDEventSystemClientSetProperty"),
              let client = unsafeBitCast(createSymbol, to: CreateClient.self)(kCFAllocatorDefault)?.takeRetainedValue()
        else { return }
        _ = unsafeBitCast(setSymbol, to: SetProperty.self)(client, hidKey, (linear ? 1 : 0) as NSNumber)
    }
}
