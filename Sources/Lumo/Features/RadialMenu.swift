import AppKit
import LumoCore
import SwiftUI

/// One slice of the radial menu.
struct RadialItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case tool, app, file, keys, submenu
    }

    var id = UUID()
    var kind: Kind
    var value: String
    var title: String
    var children: [RadialItem] = []
    var binding: ShortcutBinding?
}

/// A named set of slices; it is used while one of its apps is in front (or as the default).
struct RadialProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var apps: [String] = []
    var items: [RadialItem]
}

/// A wheel of apps, files, key combos and Lumo tools around the pointer.
@MainActor
final class RadialMenu: NSObject, ObservableObject, NSWindowDelegate {
    private enum Key {
        static let profiles = "radial.profiles"
        static let enabled = "radial.enabled"
    }

    static let size: CGFloat = 340
    static let maxSlices = 8

    @Published var isEnabled: Bool { didSet { store.set(isEnabled, forKey: Key.enabled); registerHotKey() } }
    @Published var profiles: [RadialProfile] { didSet { save() } }
    /// What the open wheel shows: the profile's items, or a submenu's.
    @Published private(set) var stack: [[RadialItem]] = []
    @Published var highlighted: Int?

    weak var model: AppModel?
    var t = Localizer(language: .english)
    private let store: UserDefaults
    private let hotKeys = HotKeyCenter()
    private var panel: KeyPanel?
    private var targetApp: NSRunningApplication?

    init(store: UserDefaults) {
        self.store = store
        isEnabled = store.bool(forKey: Key.enabled)
        let saved = store.data(forKey: Key.profiles).flatMap { try? JSONDecoder().decode([RadialProfile].self, from: $0) } ?? []
        profiles = saved.isEmpty ? [Self.defaultProfile] : saved
        super.init()
        registerHotKey()
    }

    static var defaultProfile: RadialProfile {
        let tools: [LumoTool] = [.screenshotArea, .textFromScreen, .colorPicker, .clipboard, .shelf, .scratchpad, .keepAwake, .lockScreen]
        return RadialProfile(name: "Lumo", items: tools.map { RadialItem(kind: .tool, value: $0.rawValue, title: "") })
    }

    var current: [RadialItem] { stack.last ?? [] }

    // MARK: Showing

    func toggle() {
        if panel?.isVisible == true { return close() }
        targetApp = NSWorkspace.shared.frontmostApplication
        let bundle = targetApp?.bundleIdentifier ?? ""
        let profile = profiles.first { $0.apps.contains(bundle) } ?? profiles.first { $0.apps.isEmpty } ?? profiles.first
        stack = [Array((profile?.items ?? []).prefix(Self.maxSlices))]
        highlighted = nil
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let point = NSEvent.mouseLocation
        panel.setFrame(CGRect(x: point.x - Self.size / 2, y: point.y - Self.size / 2, width: Self.size, height: Self.size), display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        stack = []
    }

    func back() {
        if stack.count > 1 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { _ = stack.popLast() }
        } else {
            close()
        }
    }

    func choose(_ item: RadialItem) {
        if item.kind == .submenu {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { stack.append(Array(item.children.prefix(Self.maxSlices))) }
            highlighted = nil
            return
        }
        close()
        let target = targetApp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.run(item, target: target) }
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    private func run(_ item: RadialItem, target: NSRunningApplication?) {
        switch item.kind {
        case .tool:
            if let tool = LumoTool(rawValue: item.value), let model { tool.run(model) }
        case .app, .file:
            NSWorkspace.shared.open(URL(fileURLWithPath: item.value))
        case .keys:
            guard let binding = item.binding else { return }
            target?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { Self.press(binding) }
        case .submenu:
            break
        }
    }

    private static func press(_ binding: ShortcutBinding) {
        var flags: CGEventFlags = []
        if binding.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if binding.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if binding.modifiers.contains(.control) { flags.insert(.maskControl) }
        if binding.modifiers.contains(.shift) { flags.insert(.maskShift) }
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(binding.keyCode), keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: InputTap.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: Display helpers

    func title(of item: RadialItem) -> String {
        if !item.title.isEmpty { return item.title }
        switch item.kind {
        case .tool: return LumoTool(rawValue: item.value)?.title(t) ?? item.value
        case .app, .file: return FileManager.default.displayName(atPath: item.value).replacingOccurrences(of: ".app", with: "")
        case .keys: return item.binding?.display ?? "⌘"
        case .submenu: return t("Папка", "Folder")
        }
    }

    // MARK: Setup

    private func registerHotKey() {
        hotKeys.unregisterAll()
        if isEnabled { hotKeys.register(.radialMenu) { [weak self] in self?.toggle() } }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) { store.set(data, forKey: Key.profiles) }
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: RadialView(menu: self))
        return panel
    }
}

private struct RadialView: View {
    @ObservedObject var menu: RadialMenu
    @State private var appeared = false

    private let outer: CGFloat = RadialMenu.size / 2 - 10
    private let inner: CGFloat = 52

    var body: some View {
        let items = menu.current
        ZStack {
            Color.clear.frame(width: outer * 2, height: outer * 2)
                .navyGlass(in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let angle = Self.angle(index, items.count)
                let selected = menu.highlighted == index
                let radius = (outer + inner) / 2
                VStack(spacing: 4) {
                    icon(item)
                    Text(menu.title(of: item)).font(.system(size: 9.5, weight: .semibold)).lineLimit(1).frame(width: 74)
                }
                .scaleEffect(selected ? 1.15 : 1)
                .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selected)
            }
            if let selected = menu.highlighted, items.indices.contains(selected) {
                SliceShape(index: selected, count: items.count, inner: inner, outer: outer)
                    .fill(LinearGradient(colors: [Palette.blue.color.opacity(0.35), Palette.purple.color.opacity(0.3)],
                                         startPoint: .top, endPoint: .bottom))
                    .allowsHitTesting(false)
            }
            Circle().fill(Color.primary.opacity(0.08)).frame(width: inner * 2 - 8, height: inner * 2 - 8)
                .overlay(Image(systemName: menu.stack.count > 1 ? "chevron.backward" : "xmark").font(.system(size: 15, weight: .bold)))
                .onTapGesture { menu.back() }
        }
        .frame(width: RadialMenu.size, height: RadialMenu.size)
        .scaleEffect(appeared ? 1 : 0.6)
        .opacity(appeared ? 1 : 0)
        .contentShape(Circle())
        .onContinuousHover { phase in
            guard case .active(let point) = phase else { return }
            menu.highlighted = Self.slice(at: point, count: items.count, inner: inner, outer: outer)
        }
        .onTapGesture {
            if let index = menu.highlighted, items.indices.contains(index) { menu.choose(items[index]) }
        }
        .onKeyPress(.escape) { menu.close(); return .handled }
        .onAppear { withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { appeared = true } }
        .onDisappear { appeared = false }
    }

    @ViewBuilder
    private func icon(_ item: RadialItem) -> some View {
        switch item.kind {
        case .tool:
            let tool = LumoTool(rawValue: item.value)
            IconBadge(symbol: tool?.symbol ?? "questionmark", colors: tool?.colors ?? [.gray, .gray], size: 34)
        case .app, .file:
            Image(nsImage: IconCache.icon(for: item.value)).resizable().frame(width: 34, height: 34)
        case .keys:
            IconBadge(symbol: "command", colors: [Palette.indigo.color, Palette.blue.color], size: 34)
        case .submenu:
            IconBadge(symbol: "folder.fill", colors: [Palette.cyan.color, Palette.blue.color], size: 34)
        }
    }

    /// Slice 0 points straight up; slices go clockwise.
    static func angle(_ index: Int, _ count: Int) -> Double {
        -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(max(count, 1))
    }

    static func slice(at point: CGPoint, count: Int, inner: CGFloat, outer: CGFloat) -> Int? {
        guard count > 0 else { return nil }
        let dx = point.x - RadialMenu.size / 2, dy = point.y - RadialMenu.size / 2
        let distance = hypot(dx, dy)
        guard distance > inner, distance < outer + 20 else { return nil }
        let step = 2 * Double.pi / Double(count)
        var angle = atan2(dy, dx) + Double.pi / 2 + step / 2
        if angle < 0 { angle += 2 * Double.pi }
        return Int(angle / step) % count
    }
}

private struct SliceShape: Shape {
    let index: Int
    let count: Int
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let step = 2 * Double.pi / Double(max(count, 1))
        let middle = -Double.pi / 2 + Double(index) * step
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: .radians(middle - step / 2), endAngle: .radians(middle + step / 2), clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: .radians(middle + step / 2), endAngle: .radians(middle - step / 2), clockwise: true)
        path.closeSubpath()
        return path
    }
}
