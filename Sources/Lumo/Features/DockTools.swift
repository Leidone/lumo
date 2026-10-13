import AppKit
import ApplicationServices
import LumoCore
import ScreenCaptureKit
import SwiftUI

/// Dock and window extras: window previews on hover, clicks on the active app's icon, the green
/// button that fills the screen without a new Space, a fixed Spaces order and quit-on-close.
@MainActor
final class DockTools: ObservableObject {
    enum ClickAction: String, CaseIterable, Identifiable {
        case none, minimize, hide, cycle

        var id: Self { self }
    }

    private enum Key {
        static let preview = "dock.preview"
        static let clickAction = "dock.clickAction"
        static let greenMaximize = "dock.greenMaximize"
        static let fixedSpaces = "dock.fixedSpaces"
        static let spacesBefore = "dock.spacesBefore"
        static let quitOnClose = "dock.quitOnClose"
    }

    private static let hoverDelay = 0.35
    private static let quitCheckInterval: TimeInterval = 2

    @Published var previewEnabled: Bool { didSet { save(previewEnabled, Key.preview) } }
    @Published var clickAction: ClickAction { didSet { save(clickAction.rawValue, Key.clickAction) } }
    @Published var greenMaximize: Bool { didSet { save(greenMaximize, Key.greenMaximize) } }
    @Published var fixedSpaces: Bool {
        didSet {
            store.set(fixedSpaces, forKey: Key.fixedSpaces)
            applySpacesOrder()
        }
    }
    @Published var quitOnClose: [String] {
        didSet {
            store.set(quitOnClose, forKey: Key.quitOnClose)
            configureQuitWatcher()
        }
    }

    /// Asks the owner to rebuild the shared event tap.
    var onChange: (() -> Void)?
    let preview = DockPreviewController()

    private let store: UserDefaults
    private var dockFrame: CGRect?
    private var dockFrameRead = Date.distantPast
    private var lastMove: TimeInterval = 0
    private var hovered: (bundle: URL, frame: CGRect)?
    private var hoverWork: DispatchWorkItem?
    private var swallowNextUp = false
    private var pendingGreen: AXUIElement?
    private var previousFrames: [CFHashCode: CGRect] = [:]
    private var quitTimer: Timer?
    private var hadWindows: [pid_t: Bool] = [:]

    init(store: UserDefaults) {
        self.store = store
        previewEnabled = store.bool(forKey: Key.preview)
        clickAction = ClickAction(rawValue: store.string(forKey: Key.clickAction) ?? "") ?? .none
        greenMaximize = store.bool(forKey: Key.greenMaximize)
        fixedSpaces = store.bool(forKey: Key.fixedSpaces)
        quitOnClose = store.stringArray(forKey: Key.quitOnClose) ?? []
        configureQuitWatcher()
    }

    var usesAccessibility: Bool { previewEnabled || clickAction != .none || greenMaximize || !quitOnClose.isEmpty }

    var handlers: [(mask: CGEventMask, handle: InputTap.Handler)] {
        var result: [(mask: CGEventMask, handle: InputTap.Handler)] = []
        if previewEnabled {
            result.append((InputTap.mask(.mouseMoved), { [weak self] _, event in
                self?.pointerMoved(event.location)
                return event
            }))
        }
        if clickAction != .none || greenMaximize {
            result.append((InputTap.mask(.leftMouseDown, .leftMouseUp), { [weak self] type, event in
                self?.handleClick(type, event) ?? event
            }))
        }
        return result
    }

    func toggleQuitOnClose(_ bundleID: String) {
        quitOnClose = quitOnClose.contains(bundleID) ? quitOnClose.filter { $0 != bundleID } : quitOnClose + [bundleID]
    }

    private func save(_ value: Any, _ key: String) {
        store.set(value, forKey: key)
        onChange?()
    }

    // MARK: Dock geometry

    private func currentDockFrame() -> CGRect? {
        if Date().timeIntervalSince(dockFrameRead) < 5 { return dockFrame }
        dockFrameRead = Date()
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(dock.processIdentifier), kAXChildrenAttribute as CFString, &children)
        let list = (children as? [AXUIElement])?.first { AXWindow.string($0, kAXRoleAttribute) == kAXListRole }
        dockFrame = list.flatMap(AXWindow.frame(of:))
        return dockFrame
    }

    /// The app icon under the pointer: its bundle URL and frame (top-left coordinates).
    private func dockItem(at point: CGPoint) -> (element: AXUIElement, bundle: URL, frame: CGRect)? {
        guard let frame = currentDockFrame(), frame.insetBy(dx: -2, dy: -2).contains(point) else { return nil }
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
              let element, AXWindow.string(element, kAXSubroleAttribute) == "AXApplicationDockItem"
        else { return nil }
        var url: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &url)
        guard let bundle = url as? URL, let itemFrame = AXWindow.frame(of: element) else { return nil }
        return (element, bundle, itemFrame)
    }

    private static func runningApp(_ bundle: URL) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == bundle.standardizedFileURL }
    }

    // MARK: Preview on hover

    private func pointerMoved(_ point: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMove > 0.05 else { return }
        lastMove = now
        if preview.contains(point) { return }
        guard let item = dockItem(at: point), let app = Self.runningApp(item.bundle) else {
            hoverWork?.cancel()
            hoverWork = nil
            hovered = nil
            preview.hideSoon()
            return
        }
        guard hovered?.bundle != item.bundle else { return }
        hovered = (item.bundle, item.frame)
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hovered?.bundle == item.bundle else { return }
            self.preview.show(app: app, near: item.frame, dockFrame: self.dockFrame ?? item.frame)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (preview.isVisible ? 0.08 : Self.hoverDelay), execute: work)
    }

    // MARK: Clicks

    private func handleClick(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        let point = event.location
        if type == .leftMouseUp {
            if let window = pendingGreen {
                pendingGreen = nil
                toggleMaximize(window)
                return nil
            }
            if swallowNextUp {
                swallowNextUp = false
                return nil
            }
            return event
        }
        if greenMaximize, !event.flags.contains(.maskAlternate), let window = greenButtonWindow(at: point) {
            pendingGreen = window
            return nil
        }
        guard clickAction != .none, let item = dockItem(at: point), let app = Self.runningApp(item.bundle), app.isActive else { return event }
        let windows = AXWindow.windows(pid: app.processIdentifier)
        guard !windows.isEmpty else { return event }
        swallowNextUp = true
        switch clickAction {
        case .minimize:
            let anyVisible = windows.contains { !Self.isMinimized($0) }
            windows.forEach { AXUIElementSetAttributeValue($0, kAXMinimizedAttribute as CFString, anyVisible ? kCFBooleanTrue : kCFBooleanFalse) }
        case .hide:
            app.hide()
        case .cycle:
            // Raising the backmost window rotates through all of them on repeated clicks.
            if let back = windows.last(where: { !Self.isMinimized($0) }) {
                AXUIElementPerformAction(back, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(back, kAXMainAttribute as CFString, kCFBooleanTrue)
            }
        case .none:
            break
        }
        return nil
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value)
        return (value as? Bool) == true
    }

    private func greenButtonWindow(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
              let element, AXWindow.string(element, kAXSubroleAttribute) == "AXFullScreenButton"
        else { return nil }
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &window) == .success, let window,
              CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        return (window as! AXUIElement)
    }

    /// Fills the visible screen; a second click restores the earlier size.
    private func toggleMaximize(_ window: AXUIElement) {
        guard let current = AXWindow.frame(of: window) else { return }
        let target = AXWindow.axRect(AXWindow.screen(containing: current).visibleFrame)
        let key = CFHash(window)
        if abs(current.width - target.width) < 4, abs(current.height - target.height) < 4, let previous = previousFrames.removeValue(forKey: key) {
            AXWindow.setFrame(window, previous)
        } else {
            previousFrames[key] = current
            AXWindow.setFrame(window, target)
        }
    }

    // MARK: Spaces order

    /// macOS's "Automatically rearrange Spaces based on most recent use", remembered and restored.
    private func applySpacesOrder() {
        let domain = "com.apple.dock" as CFString
        let key = "mru-spaces" as CFString
        if fixedSpaces {
            let current = (CFPreferencesCopyAppValue(key, domain) as? Bool) ?? true
            store.set(current, forKey: Key.spacesBefore)
            CFPreferencesSetAppValue(key, false as CFBoolean, domain)
        } else {
            let before = store.object(forKey: Key.spacesBefore) as? Bool ?? true
            CFPreferencesSetAppValue(key, before as CFBoolean, domain)
        }
        CFPreferencesAppSynchronize(domain)
        // The Dock reads the setting at launch; it restarts in a moment, windows stay put.
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.terminate()
    }

    // MARK: Quit on close

    private func configureQuitWatcher() {
        quitTimer?.invalidate()
        quitTimer = nil
        hadWindows = [:]
        guard !quitOnClose.isEmpty else { return }
        let timer = Timer(timeInterval: Self.quitCheckInterval, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.checkClosedApps() } }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        quitTimer = timer
    }

    private func checkClosedApps() {
        guard AXIsProcessTrusted() else { return }
        let watched = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier.map(quitOnClose.contains) == true }
        let alive = Set(watched.map(\.processIdentifier))
        hadWindows = hadWindows.filter { alive.contains($0.key) }
        for app in watched {
            let hasWindows = !AXWindow.windows(pid: app.processIdentifier).isEmpty
            if hadWindows[app.processIdentifier] == true, !hasWindows {
                app.terminate()
            }
            hadWindows[app.processIdentifier] = hasWindows
        }
    }
}

// MARK: - Preview panel

@MainActor
final class DockPreviewController {
    private static let thumbnailWidth = 220.0

    private let state = DockPreviewState()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    var isVisible: Bool { panel?.isVisible == true }

    func contains(_ point: CGPoint) -> Bool {
        guard let panel, panel.isVisible else { return false }
        return AXWindow.axRect(panel.frame).insetBy(dx: -6, dy: -6).contains(point)
    }

    func show(app: NSRunningApplication, near item: CGRect, dockFrame: CGRect) {
        hideWork?.cancel()
        let windows = AXWindow.windows(pid: app.processIdentifier).compactMap { window -> DockPreviewState.Window? in
            guard let title = AXWindow.string(window, kAXTitleAttribute), let frame = AXWindow.frame(of: window),
                  frame.width > 120, frame.height > 80
            else { return nil }
            return DockPreviewState.Window(id: "\(CFHash(window))", title: title, element: window)
        }
        guard !windows.isEmpty else { return hide() }
        state.app = app
        state.windows = windows
        state.thumbnails = [:]
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = DockPreviewView.size(for: windows.count)
        let anchor = AXWindow.screenRect(item)
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let dock = AXWindow.screenRect(dockFrame)
        var origin: CGPoint
        if dock.width >= dock.height {
            origin = CGPoint(x: anchor.midX - size.width / 2, y: dock.maxY + 6)
        } else if dock.minX <= screen.frame.minX + 4 {
            origin = CGPoint(x: dock.maxX + 6, y: anchor.midY - size.height / 2)
        } else {
            origin = CGPoint(x: dock.minX - size.width - 6, y: anchor.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        loadThumbnails(pid: app.processIdentifier)
    }

    func hideSoon() {
        guard isVisible, hideWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.hideWork = nil
            guard let self, !self.contains(CGPoint(x: NSEvent.mouseLocation.x, y: (NSScreen.screens.first?.frame.height ?? 0) - NSEvent.mouseLocation.y))
            else { return }
            self.hide()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: DockPreviewView(state: state) { [weak self] in self?.hide() })
        return panel
    }

    private func loadThumbnails(pid: pid_t) {
        guard CGPreflightScreenCaptureAccess() else { return }
        let titles = Set(state.windows.map(\.title))
        Task {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return }
            let candidates = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 && titles.contains($0.title ?? "") }
            for window in candidates {
                let configuration = SCStreamConfiguration()
                let scale = Self.thumbnailWidth / max(window.frame.width, 1)
                configuration.width = Int(Self.thumbnailWidth * 2)
                configuration.height = max(Int(window.frame.height * scale * 2), 1)
                configuration.showsCursor = false
                guard let image = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                                              configuration: configuration),
                      let title = window.title
                else { continue }
                state.thumbnails[title] = NSImage(cgImage: image, size: .zero)
            }
        }
    }
}

@MainActor
final class DockPreviewState: ObservableObject {
    struct Window: Identifiable {
        let id: String
        let title: String
        let element: AXUIElement
    }

    @Published var app: NSRunningApplication?
    @Published var windows: [Window] = []
    @Published var thumbnails: [String: NSImage] = [:]
}

private struct DockPreviewView: View {
    static let tile = CGSize(width: 220, height: 160)

    @ObservedObject var state: DockPreviewState
    let dismiss: () -> Void

    static func size(for count: Int) -> CGSize {
        let columns = min(count, 4)
        let rows = Int((Double(count) / 4).rounded(.up))
        return CGSize(width: CGFloat(columns) * (tile.width + 10) + 14, height: CGFloat(min(rows, 2)) * (tile.height + 10) + 14)
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.tile.width), spacing: 10), count: min(max(state.windows.count, 1), 4)), spacing: 10) {
            ForEach(state.windows) { window in
                DockPreviewTile(window: window, thumbnail: state.thumbnails[window.title], app: state.app, dismiss: dismiss)
            }
        }
        .padding(7)
        .navyGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct DockPreviewTile: View {
    let window: DockPreviewState.Window
    let thumbnail: NSImage?
    let app: NSRunningApplication?
    let dismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(nsImage: app?.icon ?? NSImage()).resizable().frame(width: 54, height: 54)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                if hovering {
                    HStack(spacing: 4) {
                        action("rectangle.lefthalf.filled") { snap(.leftHalf) }
                        action("rectangle.righthalf.filled") { snap(.rightHalf) }
                        action("arrow.up.left.and.arrow.down.right") { snap(.maximize) }
                        action("xmark") { press(kAXCloseButtonAttribute) }
                    }
                    .padding(5)
                    .transition(.opacity)
                }
            }
            .frame(height: 124)
            Text(window.title.isEmpty ? (app?.localizedName ?? "") : window.title)
                .font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .padding(6)
        .frame(width: DockPreviewView.tile.width, height: DockPreviewView.tile.height)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(hovering ? 0.12 : 0.04)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onTapGesture {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
            app?.activate()
            dismiss()
        }
    }

    private func action(_ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.regularMaterial))
        }
        .buttonStyle(.plain)
    }

    private func snap(_ action: WindowAction) {
        guard let current = AXWindow.frame(of: window.element) else { return }
        let screen = AXWindow.screen(containing: current)
        AXWindow.setFrame(window.element, WindowLayout.frame(for: action, in: AXWindow.axRect(screen.visibleFrame), current: current))
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        app?.activate()
        dismiss()
    }

    private func press(_ button: String) {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window.element, button as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return }
        AXUIElementPerformAction(value as! AXUIElement, kAXPressAction as CFString)
        dismiss()
    }
}
