import AppKit
import SwiftUI

/// "Install only what you use": removed features vanish from the Tools tab and stop running;
/// their on/off switches are remembered and come back when the feature is added again.
@MainActor
final class FeatureHub: ObservableObject {
    enum Preset: String, CaseIterable, Identifiable {
        case essentials, power, everything

        var id: Self { self }

        var features: Set<FeatureID> {
            switch self {
            case .essentials: return [.optimizer, .cleaner, .sensors, .updates, .readouts, .clipboard, .screenshot, .commandBar, .island, .notes, .keepAwake]
            case .power: return Set(FeatureID.allCases).subtracting([.radial, .messaging, .displays])
            case .everything: return Set(FeatureID.allCases)
            }
        }

        func title(_ t: Localizer) -> String {
            switch self {
            case .essentials: return t("Основное", "Essentials")
            case .power: return t("Продвинутый", "Power user")
            case .everything: return t("Всё", "Everything")
            }
        }
    }

    /// A switch that keeps a feature running in the background.
    private struct Switch {
        let name: String
        let get: () -> Bool
        let set: (Bool) -> Void
    }

    private enum Key {
        static let removed = "hub.removed"
        static let snapshots = "hub.snapshots"
        static let order = "hub.categoryOrder"
        static let hidden = "hub.hiddenCategories"
        static let compact = "hub.compact"
    }

    @Published private(set) var removed: Set<FeatureID>
    @Published var order: [FeatureCategory] { didSet { store.set(order.map(\.rawValue), forKey: Key.order) } }
    @Published var hiddenCategories: Set<FeatureCategory> { didSet { store.set(hiddenCategories.map(\.rawValue), forKey: Key.hidden) } }
    @Published var compact: Bool { didSet { store.set(compact, forKey: Key.compact) } }

    weak var model: AppModel?
    private let store: UserDefaults

    init(store: UserDefaults) {
        self.store = store
        removed = Set((store.stringArray(forKey: Key.removed) ?? []).compactMap(FeatureID.init(rawValue:)))
        let saved = (store.stringArray(forKey: Key.order) ?? []).compactMap(FeatureCategory.init(rawValue:))
        order = saved + FeatureCategory.allCases.filter { !saved.contains($0) }
        hiddenCategories = Set((store.stringArray(forKey: Key.hidden) ?? []).compactMap(FeatureCategory.init(rawValue:)))
        compact = store.bool(forKey: Key.compact)
    }

    var visibleCategories: [FeatureCategory] { order.filter { !hiddenCategories.contains($0) } }

    func features(in category: FeatureCategory) -> [FeatureID] {
        FeatureID.allCases.filter { $0.category == category && !removed.contains($0) }
    }

    func isInstalled(_ feature: FeatureID) -> Bool { !removed.contains(feature) }

    func setInstalled(_ feature: FeatureID, _ installed: Bool) {
        guard installed != isInstalled(feature) else { return }
        var snapshots = store.dictionary(forKey: Key.snapshots) as? [String: [String: Bool]] ?? [:]
        let switches = self.switches(for: feature)
        if installed {
            let saved = snapshots.removeValue(forKey: feature.rawValue) ?? [:]
            for item in switches { if let value = saved[item.name] { item.set(value) } }
            removed.remove(feature)
        } else {
            snapshots[feature.rawValue] = Dictionary(uniqueKeysWithValues: switches.map { ($0.name, $0.get()) })
            switches.forEach { $0.set(false) }
            removed.insert(feature)
        }
        store.set(snapshots, forKey: Key.snapshots)
        store.set(removed.map(\.rawValue), forKey: Key.removed)
    }

    func apply(_ preset: Preset) {
        for feature in FeatureID.allCases { setInstalled(feature, preset.features.contains(feature)) }
    }

    func move(_ category: FeatureCategory, by offset: Int) {
        guard let index = order.firstIndex(of: category) else { return }
        let target = min(max(index + offset, 0), order.count - 1)
        var next = order
        next.swapAt(index, target)
        order = next
    }

    // MARK: Background switches per feature

    private func switches(for feature: FeatureID) -> [Switch] {
        guard let model else { return [] }
        let input = model.input
        func bool(_ name: String, _ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> Switch { Switch(name: name, get: get, set: set) }
        switch feature {
        case .cleaner: return [bool("auto", { model.cleaner.autoCleanWeekly }, { model.cleaner.autoCleanWeekly = $0 })]
        case .windowLayout:
            return [bool("shortcuts", { input.windowShortcuts }, { input.windowShortcuts = $0 }),
                    bool("snap", { input.snapByDragging }, { input.snapByDragging = $0 }),
                    bool("drag", { input.modifierDrag }, { input.modifierDrag = $0 })]
        case .appSwitcher: return [bool("switcher", { input.switcherEnabled }, { input.switcherEnabled = $0 })]
        case .dock:
            return [bool("preview", { input.dock.previewEnabled }, { input.dock.previewEnabled = $0 }),
                    bool("green", { input.dock.greenMaximize }, { input.dock.greenMaximize = $0 })]
        case .quitProtection:
            return [bool("quit", { input.guardQuit }, { input.guardQuit = $0 }), bool("close", { input.guardClose }, { input.guardClose = $0 })]
        case .mouse:
            return [bool("smooth", { input.smoothScroll }, { input.smoothScroll = $0 }), bool("reverse", { input.reverseMouse }, { input.reverseMouse = $0 }),
                    bool("side", { input.sideButtons }, { input.sideButtons = $0 }), bool("linear", { input.linearScroll }, { input.linearScroll = $0 }),
                    bool("gestures", { input.gestures }, { input.gestures = $0 }), bool("three", { input.threeFingerMiddleClick }, { input.threeFingerMiddleClick = $0 }),
                    bool("focus", { input.focusFollowsMouse }, { input.focusFollowsMouse = $0 }), bool("filter", { input.clickFilter }, { input.clickFilter = $0 })]
        case .keyboard:
            return [bool("debounce", { input.keyboard.debounce }, { input.keyboard.debounce = $0 }),
                    bool("super", { input.keyboard.superSource != .off },
                         { input.keyboard.superSource = $0 ? (input.keyboard.superSource == .off ? .capsLock : input.keyboard.superSource) : .off })]
        case .clipboard: return [bool("history", { model.clipboard.isEnabled }, { model.clipboard.isEnabled = $0 })]
        case .snippets: return [bool("snippets", { model.snippets.isEnabled }, { model.snippets.isEnabled = $0 })]
        case .shelf:
            return [bool("shake", { model.shelfPanel.shakeToOpen }, { model.shelfPanel.shakeToOpen = $0 }),
                    bool("hotkey", { model.shelfPanel.hotKeyEnabled }, { model.shelfPanel.hotKeyEnabled = $0 })]
        case .fileTools:
            return [bool("links", { model.clipExtras.autoCleanLinks }, { model.clipExtras.autoCleanLinks = $0 }),
                    bool("cut", { model.clipExtras.finderCutPaste }, { model.clipExtras.finderCutPaste = $0 }),
                    bool("rename", { model.clipExtras.finderRename }, { model.clipExtras.finderRename = $0 }),
                    bool("png", { model.clipExtras.finderPasteImage }, { model.clipExtras.finderPasteImage = $0 }),
                    bool("dmg", { model.dmgInstaller.isEnabled }, { model.dmgInstaller.isEnabled = $0 })]
        case .screenshot: return [bool("hotkeys", { model.capture.hotkeysEnabled }, { model.capture.hotkeysEnabled = $0 })]
        case .mixer: return [bool("mixer", { model.mixer.isEnabled }, { model.mixer.isEnabled = $0 })]
        case .audio:
            return [bool("output", { model.audio.outputHotKey }, { model.audio.outputHotKey = $0 }),
                    bool("mute", { model.audio.muteHotKey }, { model.audio.muteHotKey = $0 }),
                    bool("guard", { model.audio.headphoneGuard }, { model.audio.headphoneGuard = $0 }),
                    bool("music", { model.audio.musicBlocker }, { model.audio.musicBlocker = $0 })]
        case .commandBar: return [bool("bar", { model.commandBar.isEnabled }, { model.commandBar.isEnabled = $0 })]
        case .island: return [bool("island", { model.island.isEnabled }, { model.island.isEnabled = $0 })]
        case .quickPanel: return [bool("panel", { model.quickPanel.isEnabled }, { model.quickPanel.isEnabled = $0 })]
        case .radial: return [bool("radial", { model.radial.isEnabled }, { model.radial.isEnabled = $0 })]
        case .notes: return [bool("finish", { model.agents.finishNotices }, { model.agents.finishNotices = $0 })]
        case .messaging: return [bool("auto", { model.messaging.autoClean }, { model.messaging.autoClean = $0 })]
        case .keepAwake:
            return [bool("power", { model.power.awakeOnPower }, { model.power.awakeOnPower = $0 }),
                    bool("display", { model.power.awakeWithDisplay }, { model.power.awakeWithDisplay = $0 }),
                    bool("bluetooth", { model.power.bluetoothOnSleep }, { model.power.bluetoothOnSleep = $0 })]
        case .displays:
            return [bool("dim", { model.displayTools.extraDimming }, { model.displayTools.extraDimming = $0 }),
                    bool("xdr", { model.displayTools.xdrBoost }, { model.displayTools.xdrBoost = $0 })]
        case .readouts, .optimizer, .uninstaller, .sensors, .network, .updates, .recorder, .shortcuts:
            return []
        }
    }
}

// MARK: - Settings export

enum SettingsTransfer {
    /// Writes every Lumo preference to a property list the user picks.
    @MainActor
    static func export(t: Localizer) {
        guard let id = Bundle.main.bundleIdentifier, let domain = UserDefaults.standard.persistentDomain(forName: id) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Lumo Settings.plist"
        panel.allowedContentTypes = [.propertyList]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? PropertyListSerialization.data(fromPropertyList: domain, format: .xml, options: 0)
        else { return }
        try? data.write(to: url)
        Toast.show("square.and.arrow.up.fill", t("Настройки сохранены", "Settings exported"), subtitle: url.lastPathComponent, tint: Palette.green.color)
    }

    /// Replaces the preferences with an exported file, then relaunches Lumo so everything picks them up.
    @MainActor
    static func importSettings(t: Localizer) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url),
              let domain = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = Bundle.main.bundleIdentifier
        else { return }
        UserDefaults.standard.setPersistentDomain(domain, forName: id)
        UserDefaults.standard.synchronize()
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? relaunch.run()
        NSApp.terminate(nil)
    }
}
