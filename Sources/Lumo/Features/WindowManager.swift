import AppKit
import ApplicationServices
import Carbon
import LumoCore
import SwiftUI

/// Snaps the focused window with ⌃⌥ shortcuts or by dragging it to a screen edge.
@MainActor
final class WindowManager {
    struct Shortcut {
        let keyCode: UInt32
        let symbol: String
        let action: () -> Void
    }

    private let hotKeys = HotKeyCenter()
    private let preview = SnapPreviewPanel()
    private var previousFrames: [CFHashCode: CGRect] = [:]
    private var drag: DragState?
    private var grab: Grab?

    /// A window being moved (⌃⌥ + drag) or resized (⌃⌥⇧ + drag) from anywhere inside it.
    private struct Grab {
        let window: AXUIElement
        let start: CGPoint
        let frame: CGRect
        let resizing: Bool
        var lastApply: TimeInterval
    }

    private struct DragState {
        let window: AXUIElement
        let origin: CGPoint
        var lastCheck: TimeInterval
        var isMoving: Bool
        var action: WindowAction?
    }

    // MARK: Shortcuts

    func setShortcuts(enabled: Bool) {
        hotKeys.unregisterAll()
        guard enabled else { return }
        let actions: [(ShortcutID, WindowAction)] = [
            (.windowLeft, .leftHalf), (.windowRight, .rightHalf), (.windowTop, .topHalf), (.windowBottom, .bottomHalf),
            (.windowTopLeft, .topLeft), (.windowTopRight, .topRight), (.windowBottomLeft, .bottomLeft), (.windowBottomRight, .bottomRight),
            (.windowLeftThird, .leftThird), (.windowCenterThird, .centerThird), (.windowRightThird, .rightThird),
            (.windowMaximize, .maximize), (.windowCenter, .center),
        ]
        for (id, action) in actions {
            hotKeys.register(id) { [weak self] in self?.perform(action) }
        }
        hotKeys.register(.windowRestore) { [weak self] in self?.restore() }
        hotKeys.register(.windowNextDisplay) { [weak self] in self?.moveToNextDisplay() }
    }

    // MARK: Actions

    func perform(_ action: WindowAction) {
        guard let window = AXWindow.focused(), let current = AXWindow.frame(of: window) else { return }
        let screen = AXWindow.screen(containing: current)
        let target = WindowLayout.frame(for: action, in: AXWindow.axRect(screen.visibleFrame), current: current)
        previousFrames[CFHash(window)] = current
        AXWindow.setFrame(window, target)
    }

    func restore() {
        guard let window = AXWindow.focused(), let previous = previousFrames.removeValue(forKey: CFHash(window)) else { return }
        AXWindow.setFrame(window, previous)
    }

    func moveToNextDisplay() {
        let screens = NSScreen.screens
        guard screens.count > 1, let window = AXWindow.focused(), let current = AXWindow.frame(of: window) else { return }
        let source = AXWindow.screen(containing: current)
        let index = screens.firstIndex(of: source) ?? 0
        let from = AXWindow.axRect(source.visibleFrame)
        let to = AXWindow.axRect(screens[(index + 1) % screens.count].visibleFrame)
        let scaleX = to.width / from.width, scaleY = to.height / from.height
        let target = CGRect(x: to.minX + (current.minX - from.minX) * scaleX, y: to.minY + (current.minY - from.minY) * scaleY,
                            width: min(current.width * scaleX, to.width), height: min(current.height * scaleY, to.height))
        previousFrames[CFHash(window)] = current
        AXWindow.setFrame(window, target)
    }

    // MARK: Modifier drag

    var modifierDragHandler: (mask: CGEventMask, handle: InputTap.Handler) {
        (InputTap.mask(.leftMouseDown, .leftMouseDragged, .leftMouseUp), { [weak self] type, event in
            self?.handleGrab(type, event) ?? event
        })
    }

    private func handleGrab(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        let flags = event.flags
        let point = event.location
        switch type {
        case .leftMouseDown:
            guard flags.contains(.maskControl), flags.contains(.maskAlternate), !flags.contains(.maskCommand),
                  let window = AXWindow.window(at: point), let frame = AXWindow.frame(of: window)
            else { return event }
            grab = Grab(window: window, start: point, frame: frame, resizing: flags.contains(.maskShift), lastApply: 0)
            return nil
        case .leftMouseDragged:
            guard var current = grab else { return event }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - current.lastApply > 1.0 / 60 else { return nil }
            current.lastApply = now
            grab = current
            let dx = point.x - current.start.x, dy = point.y - current.start.y
            if current.resizing {
                var size = CGSize(width: max(current.frame.width + dx, 200), height: max(current.frame.height + dy, 120))
                if let value = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(current.window, kAXSizeAttribute as CFString, value) }
            } else {
                var origin = CGPoint(x: current.frame.minX + dx, y: current.frame.minY + dy)
                if let value = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(current.window, kAXPositionAttribute as CFString, value) }
            }
            return nil
        case .leftMouseUp:
            guard grab != nil else { return event }
            grab = nil
            return nil
        default:
            return event
        }
    }

    // MARK: Drag to snap

    var dragHandler: (mask: CGEventMask, handle: InputTap.Handler) {
        (InputTap.mask(.leftMouseDragged, .leftMouseUp), { [weak self] type, event in
            self?.handleDrag(type, event)
            return event
        })
    }

    private func handleDrag(_ type: CGEventType, _ event: CGEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        let point = event.location
        if type == .leftMouseUp {
            if let drag, drag.isMoving, let action = drag.action, let current = AXWindow.frame(of: drag.window) {
                let screen = AXWindow.screen(containing: CGRect(origin: point, size: .zero))
                let target = WindowLayout.frame(for: action, in: AXWindow.axRect(screen.visibleFrame), current: current)
                previousFrames[CFHash(drag.window)] = current
                AXWindow.setFrame(drag.window, target)
            }
            drag = nil
            preview.hide()
            return
        }
        // Accessibility queries are slow-ish: look at most every 60 ms while dragging.
        if var state = drag {
            guard now - state.lastCheck > 0.06 else { return }
            state.lastCheck = now
            if !state.isMoving, let frame = AXWindow.frame(of: state.window), frame.origin != state.origin {
                state.isMoving = true
            }
            if state.isMoving {
                let screen = AXWindow.screen(containing: CGRect(origin: point, size: .zero))
                state.action = WindowLayout.snapAction(for: point, in: AXWindow.axRect(screen.frame))
                if let action = state.action, let current = AXWindow.frame(of: state.window) {
                    let target = WindowLayout.frame(for: action, in: AXWindow.axRect(screen.visibleFrame), current: current)
                    preview.show(at: AXWindow.screenRect(target))
                } else {
                    preview.hide()
                }
            }
            drag = state
        } else if let window = AXWindow.focused(), let frame = AXWindow.frame(of: window) {
            drag = DragState(window: window, origin: frame.origin, lastCheck: now, isMoving: false, action: nil)
        }
    }
}

// MARK: - Accessibility helpers

@MainActor
enum AXWindow {
    static func focused() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    /// The top-level window under a point (top-left screen coordinates).
    static func window(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
              var current = element
        else { return nil }
        for _ in 0..<12 {
            if string(current, kAXRoleAttribute) == kAXWindowRole { return current }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success, let parent,
                  CFGetTypeID(parent) == AXUIElementGetTypeID()
            else { break }
            current = parent as! AXUIElement
        }
        var window: CFTypeRef?
        if AXUIElementCopyAttributeValue(current, kAXWindowAttribute as CFString, &window) == .success, let window,
           CFGetTypeID(window) == AXUIElementGetTypeID() {
            return (window as! AXUIElement)
        }
        return nil
    }

    static func windows(pid: pid_t) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success
        else { return [] }
        return value as? [AXUIElement] ?? []
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Brings the window with this title to the front of its app.
    static func raise(pid: pid_t, title: String) {
        guard let window = windows(pid: pid).first(where: { string($0, kAXTitleAttribute) == title }) else { return }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    /// Size, then position, then size again: some apps clamp the size until they've moved.
    static func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        var size = frame.size
        var origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }

    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// AppKit (bottom-left origin) → Accessibility (top-left origin).
    static func axRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Accessibility → AppKit, for placing our own windows.
    static func screenRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func screen(containing axFrame: CGRect) -> NSScreen {
        let center = CGPoint(x: axFrame.midX, y: primaryHeight - axFrame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

// MARK: - Global hot keys (Carbon; needs no permission)

@MainActor
final class HotKeyCenter {
    private var references: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?
    /// Shared across all centers: every Carbon handler sees every hot key, so IDs must be unique.
    private static var nextID: UInt32 = 1
    private static let signature: OSType = 0x4C554D4F // "LUMO"

    /// Re-run after the user changes a shortcut, so every registration picks up its new keys.
    private var installers: [() -> Void] = []
    private var changeObserver: NSObjectProtocol?

    /// Registers a user-configurable shortcut; it follows changes made on the Shortcuts page.
    func register(_ id: ShortcutID, action: @escaping () -> Void) {
        let installer: () -> Void = { [weak self] in
            guard let binding = ShortcutStore.shared.binding(id) else { return }
            self?.install(keyCode: binding.keyCode, modifiers: binding.carbonModifiers, action: action)
        }
        installers.append(installer)
        installer()
        observeChanges()
    }

    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        let installer: () -> Void = { [weak self] in self?.install(keyCode: keyCode, modifiers: modifiers, action: action) }
        installers.append(installer)
        installer()
    }

    private func observeChanges() {
        guard changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(forName: .lumoShortcutsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reinstall() }
        }
    }

    private func reinstall() {
        references.forEach { UnregisterEventHotKey($0) }
        references = []
        actions = [:]
        installers.forEach { $0() }
    }

    private func install(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        let id = Self.nextID
        Self.nextID += 1
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference) == noErr,
              let reference
        else { return }
        references.append(reference)
        actions[id] = action
    }

    func unregisterAll() {
        references.forEach { UnregisterEventHotKey($0) }
        references = []
        actions = [:]
        installers = []
    }

    /// Returns false for hot keys owned by another center, so the event keeps propagating.
    fileprivate func fire(_ id: UInt32) -> Bool {
        guard let action = actions[id] else { return false }
        action()
        return true
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, info in
            guard let event, let info else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let center = Unmanaged<HotKeyCenter>.fromOpaque(info).takeUnretainedValue()
            let handled = MainActor.assumeIsolated { center.fire(hotKeyID.id) }
            return handled ? noErr : OSStatus(eventNotHandledErr)
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}

// MARK: - Snap preview

/// A soft glass rectangle showing where the window will land.
@MainActor
final class SnapPreviewPanel {
    private var panel: NSPanel?

    func show(at frame: CGRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let inset = frame.insetBy(dx: 6, dy: 6)
        if !panel.isVisible {
            panel.setFrame(inset, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(inset, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.orderOut(nil) })
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.contentView = NSHostingView(rootView: SnapPreviewShape())
        return panel
    }
}

private struct SnapPreviewShape: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.blue.color.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Palette.cyan.color, Palette.blue.color, Palette.purple.color],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
    }
}
