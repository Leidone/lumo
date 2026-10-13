import AppKit
import Carbon
import LumoCore
import SwiftUI

/// Every global shortcut Lumo owns, with its default and a human title.
enum ShortcutID: String, CaseIterable, Identifiable {
    case windowLeft, windowRight, windowTop, windowBottom
    case windowTopLeft, windowTopRight, windowBottomLeft, windowBottomRight
    case windowLeftThird, windowCenterThird, windowRightThird, windowMaximize, windowCenter, windowRestore, windowNextDisplay
    case captureArea, captureWindow, captureText, captureColor, captureRecord
    case commandBar, clipboard, pastePlain, quickPanel, radialMenu, shelf, scratchpad
    case nextOutput, muteMics, island, cleaningMode

    var id: Self { self }

    enum Group: String, CaseIterable {
        case windows, capture, everyday, sound
    }

    var group: Group {
        switch self {
        case .captureArea, .captureWindow, .captureText, .captureColor, .captureRecord: return .capture
        case .nextOutput, .muteMics: return .sound
        case .commandBar, .clipboard, .pastePlain, .quickPanel, .radialMenu, .shelf, .scratchpad, .island, .cleaningMode: return .everyday
        default: return .windows
        }
    }

    var defaultBinding: ShortcutBinding? {
        let windows: ShortcutBinding.Modifiers = [.control, .option]
        let capture: ShortcutBinding.Modifiers = [.control, .shift]
        let hyper: ShortcutBinding.Modifiers = [.control, .option, .command]
        switch self {
        case .windowLeft: return ShortcutBinding(keyCode: UInt32(kVK_LeftArrow), modifiers: windows)
        case .windowRight: return ShortcutBinding(keyCode: UInt32(kVK_RightArrow), modifiers: windows)
        case .windowTop: return ShortcutBinding(keyCode: UInt32(kVK_UpArrow), modifiers: windows)
        case .windowBottom: return ShortcutBinding(keyCode: UInt32(kVK_DownArrow), modifiers: windows)
        case .windowTopLeft: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_U), modifiers: windows)
        case .windowTopRight: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_I), modifiers: windows)
        case .windowBottomLeft: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: windows)
        case .windowBottomRight: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: windows)
        case .windowLeftThird: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_D), modifiers: windows)
        case .windowCenterThird: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_F), modifiers: windows)
        case .windowRightThird: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_G), modifiers: windows)
        case .windowMaximize: return ShortcutBinding(keyCode: UInt32(kVK_Return), modifiers: windows)
        case .windowCenter: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_C), modifiers: windows)
        case .windowRestore: return ShortcutBinding(keyCode: UInt32(kVK_Delete), modifiers: windows)
        case .windowNextDisplay: return ShortcutBinding(keyCode: UInt32(kVK_RightArrow), modifiers: hyper)
        case .captureArea: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_1), modifiers: capture)
        case .captureWindow: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_2), modifiers: capture)
        case .captureText: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_3), modifiers: capture)
        case .captureColor: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_4), modifiers: capture)
        case .captureRecord: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_5), modifiers: capture)
        case .commandBar: return ShortcutBinding(keyCode: UInt32(kVK_Space), modifiers: [.option])
        case .clipboard: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_V), modifiers: [.shift, .command])
        case .pastePlain: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_V), modifiers: [.option, .shift, .command])
        case .quickPanel: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_V), modifiers: [.control, .command])
        case .radialMenu: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_R), modifiers: hyper)
        case .shelf: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_S), modifiers: hyper)
        case .scratchpad: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_Semicolon), modifiers: hyper)
        case .nextOutput: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_O), modifiers: hyper)
        case .muteMics: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_M), modifiers: hyper)
        case .island: return ShortcutBinding(keyCode: UInt32(kVK_ANSI_N), modifiers: hyper)
        case .cleaningMode: return nil
        }
    }

    func title(_ t: Localizer) -> String {
        switch self {
        case .windowLeft: return t("Окно: левая половина", "Window: left half")
        case .windowRight: return t("Окно: правая половина", "Window: right half")
        case .windowTop: return t("Окно: верхняя половина", "Window: top half")
        case .windowBottom: return t("Окно: нижняя половина", "Window: bottom half")
        case .windowTopLeft: return t("Окно: верхняя левая четверть", "Window: top left quarter")
        case .windowTopRight: return t("Окно: верхняя правая четверть", "Window: top right quarter")
        case .windowBottomLeft: return t("Окно: нижняя левая четверть", "Window: bottom left quarter")
        case .windowBottomRight: return t("Окно: нижняя правая четверть", "Window: bottom right quarter")
        case .windowLeftThird: return t("Окно: левая треть", "Window: left third")
        case .windowCenterThird: return t("Окно: средняя треть", "Window: center third")
        case .windowRightThird: return t("Окно: правая треть", "Window: right third")
        case .windowMaximize: return t("Окно: на весь экран", "Window: maximize")
        case .windowCenter: return t("Окно: по центру", "Window: center")
        case .windowRestore: return t("Окно: прежний размер", "Window: restore")
        case .windowNextDisplay: return t("Окно: на следующий дисплей", "Window: next display")
        case .captureArea: return t("Скриншот области", "Screenshot an area")
        case .captureWindow: return t("Скриншот окна", "Screenshot a window")
        case .captureText: return t("Текст с экрана", "Text from screen")
        case .captureColor: return t("Пипетка", "Color picker")
        case .captureRecord: return t("Запись экрана", "Screen recording")
        case .commandBar: return "Command Bar"
        case .clipboard: return t("История буфера", "Clipboard history")
        case .pastePlain: return t("Вставить без форматирования", "Paste as plain text")
        case .quickPanel: return t("Быстрая панель", "Quick panel")
        case .radialMenu: return t("Радиальное меню", "Radial menu")
        case .shelf: return t("Полка", "Shelf")
        case .scratchpad: return t("Черновик", "Scratchpad")
        case .nextOutput: return t("Следующий выход звука", "Next sound output")
        case .muteMics: return t("Выключить все микрофоны", "Mute all microphones")
        case .island: return t("Открыть Dynamic Island", "Open the Dynamic Island")
        case .cleaningMode: return t("Режим чистки", "Cleaning mode")
        }
    }
}

extension Notification.Name {
    static let lumoShortcutsChanged = Notification.Name("lumo.shortcutsChanged")
}

/// User overrides on top of the defaults. Changing one re-registers every affected hot key.
@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()
    private static let key = "shortcuts.overrides"
    private static let takeoverKey = "shortcuts.takeoverScreenshots"
    /// macOS symbolic hot keys for ⌘⇧3, ⌘⇧4 and ⌘⇧5.
    private static let screenshotSymbolicKeys: [Int32] = [28, 30, 184]

    @Published private(set) var overrides: [String: ShortcutBinding] = [:]
    @Published private(set) var disabled: Set<String> = []
    @Published var takeoverScreenshots: Bool {
        didSet {
            UserDefaults.standard.set(takeoverScreenshots, forKey: Self.takeoverKey)
            applyTakeover()
            NotificationCenter.default.post(name: .lumoShortcutsChanged, object: nil)
        }
    }

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        let saved = data.flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        overrides = saved?.overrides ?? [:]
        disabled = saved?.disabled ?? []
        takeoverScreenshots = UserDefaults.standard.bool(forKey: Self.takeoverKey)
        applyTakeover()
    }

    private struct Saved: Codable {
        let overrides: [String: ShortcutBinding]
        let disabled: Set<String>
    }

    func binding(_ id: ShortcutID) -> ShortcutBinding? {
        disabled.contains(id.rawValue) ? nil : overrides[id.rawValue] ?? id.defaultBinding
    }

    func set(_ binding: ShortcutBinding?, for id: ShortcutID) {
        if let binding {
            overrides[id.rawValue] = binding
            disabled.remove(id.rawValue)
        } else {
            overrides[id.rawValue] = nil
            disabled.insert(id.rawValue)
        }
        persist()
    }

    func reset(_ id: ShortcutID) {
        overrides[id.rawValue] = nil
        disabled.remove(id.rawValue)
        persist()
    }

    /// Another Lumo shortcut already using this combination, if any.
    func conflict(for binding: ShortcutBinding, excluding id: ShortcutID) -> ShortcutID? {
        ShortcutID.allCases.first { $0 != id && self.binding($0) == binding }
    }

    func restoreSystemShortcuts() {
        Self.screenshotSymbolicKeys.forEach { SymbolicHotKeys.set($0, enabled: true) }
    }

    private func applyTakeover() {
        Self.screenshotSymbolicKeys.forEach { SymbolicHotKeys.set($0, enabled: !takeoverScreenshots) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Saved(overrides: overrides, disabled: disabled)) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        NotificationCenter.default.post(name: .lumoShortcutsChanged, object: nil)
    }
}

/// Click, then press the new combination. Esc cancels, ⌫ clears.
struct ShortcutRecorder: View {
    let id: ShortcutID
    @ObservedObject var store = ShortcutStore.shared
    let t: Localizer
    @State private var recording = false
    @State private var monitor: Any?
    @State private var warning: String?

    var body: some View {
        HStack(spacing: 6) {
            if let warning {
                Text(warning).font(.system(size: 10)).foregroundStyle(Palette.orange.color).lineLimit(1)
            }
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? t("Нажмите сочетание…", "Press keys…") : (store.binding(id)?.display ?? t("Нет", "None")))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .frame(minWidth: 76)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(recording ? Palette.blue.color.opacity(0.25) : Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            if store.overrides[id.rawValue] != nil || store.disabled.contains(id.rawValue) {
                Button { store.reset(id) } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless).help(t("Вернуть по умолчанию", "Reset to default"))
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        warning = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case kVK_Escape: stop()
            case kVK_Delete where event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty:
                store.set(nil, for: id)
                stop()
            default:
                let modifiers = Self.modifiers(event.modifierFlags)
                guard !modifiers.isEmpty else {
                    warning = t("Нужен ⌘, ⌥ или ⌃", "Needs ⌘, ⌥ or ⌃")
                    return nil
                }
                let binding = ShortcutBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers)
                if let other = store.conflict(for: binding, excluding: id) {
                    warning = t("Уже занято: ", "Already used: ") + other.title(t)
                    return nil
                }
                store.set(binding, for: id)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> ShortcutBinding.Modifiers {
        var result: ShortcutBinding.Modifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }
}
