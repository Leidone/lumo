import AppKit
import ApplicationServices
import LumoCore
import ScreenCaptureKit
import SwiftUI

/// A ⌘Tab replacement with live window previews (or icons without Screen Recording access).
@MainActor
final class AppSwitcher {
    private static let tabKey: Int64 = 48
    private static let escapeKey: Int64 = 53
    private static let leftKey: Int64 = 123
    private static let rightKey: Int64 = 124
    private static let quitKey: Int64 = 12
    private static let deleteKey: Int64 = 51
    private static let thumbnailWidth = 360.0

    var showsPreviews = true
    /// Only apps with a window on the display under the pointer.
    var currentDisplayOnly = false
    /// One tile per window instead of per app.
    var perWindow = false

    private let state = SwitcherState()
    private var panel: NSPanel?
    private var recent: [String] = []
    private var activationObserver: NSObjectProtocol?

    init() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
            MainActor.assumeIsolated { self?.recent = RecentApps.activating(String(pid), in: self?.recent ?? []) }
        }
    }

    var keyHandler: (mask: CGEventMask, handle: InputTap.Handler) {
        (InputTap.mask(.keyDown, .flagsChanged), { [weak self] type, event in self?.handle(type, event) ?? event })
    }

    /// The system ⌘Tab is handled before event taps, so it is switched off while ours is on.
    func setSystemSwitcherEnabled(_ enabled: Bool) {
        SymbolicHotKeys.setCommandTab(enabled: enabled)
    }

    // MARK: Keys

    private func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        let flags = event.flags
        if type == .flagsChanged {
            if state.isShown && !flags.contains(.maskCommand) { commit() }
            return event
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if code == Self.tabKey, flags.contains(.maskCommand), !flags.contains(.maskControl), !flags.contains(.maskAlternate) {
            if state.isShown {
                move(flags.contains(.maskShift) ? -1 : 1)
            } else {
                open(backwards: flags.contains(.maskShift))
            }
            return nil
        }
        guard state.isShown else { return event }
        switch code {
        case Self.escapeKey: close()
        case Self.leftKey: move(-1)
        case Self.rightKey: move(1)
        case Self.quitKey where state.query.isEmpty: quitSelected()
        case Self.deleteKey: updateQuery(String(state.query.dropLast()))
        default:
            // Typing while ⌘ is held filters the list by name.
            if let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased(),
               characters.count == 1, characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == " " }) {
                updateQuery(state.query + characters)
            }
        }
        return nil
    }

    // MARK: Flow

    private func open(backwards: Bool) {
        var apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
        let windows = Self.onScreenWindows()
        if currentDisplayOnly {
            let screen = AXWindow.axRect(NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.frame ?? .zero)
            let here = Set(windows.filter { $0.bounds.intersects(screen) }.map(\.pid))
            apps = apps.filter { here.contains($0.processIdentifier) }
        }
        let order = RecentApps.ordered(running: apps.map { String($0.processIdentifier) }, recent: recent)
        let byPID = Dictionary(uniqueKeysWithValues: apps.map { (String($0.processIdentifier), $0) })
        let ordered = order.compactMap { byPID[$0] }
        let items: [SwitcherState.Item]
        if perWindow {
            items = ordered.flatMap { app in
                windows.filter { $0.pid == app.processIdentifier }.map {
                    SwitcherState.Item(pid: app.processIdentifier, name: $0.title.isEmpty ? (app.localizedName ?? "") : $0.title,
                                       icon: app.icon ?? NSImage(), windowID: $0.id, windowTitle: $0.title)
                }
            }
        } else {
            items = ordered.map { SwitcherState.Item(pid: $0.processIdentifier, name: $0.localizedName ?? "", icon: $0.icon ?? NSImage()) }
        }
        guard items.count > 1 else { return }
        state.allItems = items
        state.query = ""
        state.items = items
        state.selection = backwards ? items.count - 1 : 1
        state.isShown = true
        showPanel()
        if showsPreviews && CGPreflightScreenCaptureAccess() { loadThumbnails(for: items) }
    }

    private func updateQuery(_ query: String) {
        state.query = query
        state.items = query.isEmpty ? state.allItems : state.allItems.filter { $0.name.lowercased().contains(query) }
        state.selection = 0
        resizePanel()
    }

    struct WindowInfo {
        let id: CGWindowID
        let pid: pid_t
        let title: String
        let bounds: CGRect
    }

    /// Normal app windows currently on screen (top-left coordinates), front to back.
    static func onScreenWindows() -> [WindowInfo] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict), bounds.width > 80, bounds.height > 60
            else { return nil }
            return WindowInfo(id: number, pid: pid, title: info[kCGWindowName as String] as? String ?? "", bounds: bounds)
        }
    }

    private func move(_ step: Int) {
        guard !state.items.isEmpty else { return }
        state.selection = (state.selection + step + state.items.count) % state.items.count
    }

    fileprivate func select(_ index: Int) { state.selection = index }

    fileprivate func commit() {
        guard state.isShown, state.items.indices.contains(state.selection) else { return close() }
        let item = state.items[state.selection]
        let pid = item.pid
        close()
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if app.isHidden { app.unhide() }
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let title = item.windowTitle {
            AXWindow.raise(pid: pid, title: title)
            app.activate()
        } else {
            app.activate(options: [.activateAllWindows])
        }
    }

    private func quitSelected() {
        guard state.items.indices.contains(state.selection) else { return }
        let item = state.items[state.selection]
        NSRunningApplication(processIdentifier: item.pid)?.terminate()
        state.items.removeAll { $0.pid == item.pid }
        state.allItems.removeAll { $0.pid == item.pid }
        if state.items.count < 2 { return close() }
        state.selection = min(state.selection, state.items.count - 1)
        resizePanel()
    }

    private func close() {
        state.isShown = false
        panel?.orderOut(nil)
    }

    // MARK: Panel

    private func showPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        resizePanel()
        panel.orderFrontRegardless()
    }

    private func resizePanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let size = SwitcherView.size(for: max(state.items.count, 1), maxWidth: screen.visibleFrame.width * 0.9)
        panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: SwitcherView(state: state, switcher: self))
        return panel
    }

    // MARK: Previews

    private func loadThumbnails(for items: [SwitcherState.Item]) {
        Task {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return }
            for item in items.prefix(16) {
                let window = item.windowID.flatMap { id in content.windows.first { $0.windowID == id } } ?? content.windows
                    .filter { $0.owningApplication?.processID == item.pid && $0.windowLayer == 0 && $0.frame.width > 120 }
                    .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
                guard let window else { continue }
                let configuration = SCStreamConfiguration()
                let scale = Self.thumbnailWidth / window.frame.width
                configuration.width = Int(Self.thumbnailWidth)
                configuration.height = max(Int(window.frame.height * scale), 1)
                configuration.showsCursor = false
                let filter = SCContentFilter(desktopIndependentWindow: window)
                if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) {
                    state.thumbnails[item.id] = NSImage(cgImage: image, size: .zero)
                }
            }
        }
    }
}

/// Private WindowServer switch for the built-in ⌘Tab (the approach other switchers use).
enum SymbolicHotKeys {
    private typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32
    private static let commandTab: Int32 = 1
    private static let commandShiftTab: Int32 = 2

    static func setCommandTab(enabled: Bool) {
        set(commandTab, enabled: enabled)
        set(commandShiftTab, enabled: enabled)
    }

    /// Switches one of macOS's built-in shortcuts on or off for this login session.
    static func set(_ id: Int32, enabled: Bool) {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let symbol = dlsym(handle, "CGSSetSymbolicHotKeyEnabled")
        else { return }
        _ = unsafeBitCast(symbol, to: SetEnabled.self)(id, enabled)
    }
}

// MARK: - View

@MainActor
final class SwitcherState: ObservableObject {
    struct Item: Identifiable, Equatable {
        let pid: pid_t
        let name: String
        let icon: NSImage
        var windowID: CGWindowID?
        var windowTitle: String?
        var id: String { windowID.map { "w\($0)" } ?? "p\(pid)" }
    }

    @Published var items: [Item] = []
    @Published var selection = 0
    @Published var query = ""
    @Published var thumbnails: [String: NSImage] = [:]
    var allItems: [Item] = []
    var isShown = false
}

private struct SwitcherView: View {
    static let tile = CGSize(width: 168, height: 132)
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 20

    @ObservedObject var state: SwitcherState
    let switcher: AppSwitcher
    @Namespace private var namespace

    static func size(for count: Int, maxWidth: CGFloat) -> CGSize {
        let perRow = max(1, min(count, Int((maxWidth - padding * 2 + spacing) / (tile.width + spacing))))
        let rows = Int((Double(count) / Double(perRow)).rounded(.up))
        return CGSize(width: CGFloat(perRow) * (tile.width + spacing) - spacing + padding * 2,
                      height: CGFloat(rows) * (tile.height + spacing) - spacing + padding * 2)
    }

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: Self.tile.width, maximum: Self.tile.width), spacing: Self.spacing)]
        LazyVGrid(columns: columns, spacing: Self.spacing) {
            ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                tile(item, selected: index == state.selection)
                    .onHover { if $0 { switcher.select(index) } }
                    .onTapGesture {
                        switcher.select(index)
                        switcher.commit()
                    }
            }
        }
        .padding(Self.padding)
        .overlay(alignment: .top) {
            if !state.query.isEmpty {
                Label(state.query, systemImage: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.12)))
                    .offset(y: -14)
            }
        }
        .navyGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: state.selection)
    }

    private func tile(_ item: SwitcherState.Item, selected: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                if let thumbnail = state.thumbnails[item.id] {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Image(nsImage: item.icon).resizable().frame(width: 34, height: 34).offset(x: 6, y: 6)
                } else {
                    Image(nsImage: item.icon).resizable().frame(width: 72, height: 72)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 92)
            Text(item.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }
        .padding(10)
        .frame(width: Self.tile.width, height: Self.tile.height)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Palette.periwinkle.color, Palette.azure.color, Palette.indigo.color],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5))
                    .matchedGeometryEffect(id: "selection", in: namespace)
            }
        }
        .scaleEffect(selected ? 1.04 : 1)
    }
}
