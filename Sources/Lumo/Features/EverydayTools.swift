import AppKit
import SwiftUI
import UserNotifications

/// One-tap actions shared by the Quick panel, the radial menu and the Command Bar.
enum LumoTool: String, CaseIterable, Identifiable, Codable {
    case screenshotArea, screenshotWindow, screenshotScreen, textFromScreen, colorPicker, recordScreen
    case clipboard, shelf, scratchpad, commandBar, cameraMirror
    case optimize, keepAwake, darkMode, lockScreen, sleepDisplay, emptyTrash, desktopIcons, hiddenFiles, ejectDisks
    case muteMics, nextOutput, cleaningMode, cleanLink

    var id: Self { self }

    var symbol: String {
        switch self {
        case .screenshotArea: return "camera.viewfinder"
        case .screenshotWindow: return "macwindow"
        case .screenshotScreen: return "display"
        case .textFromScreen: return "text.viewfinder"
        case .colorPicker: return "eyedropper.halffull"
        case .recordScreen: return "record.circle.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .shelf: return "tray.full.fill"
        case .scratchpad: return "note.text"
        case .commandBar: return "command.square.fill"
        case .cameraMirror: return "web.camera.fill"
        case .optimize: return "sparkles"
        case .keepAwake: return "cup.and.saucer.fill"
        case .darkMode: return "moon.fill"
        case .lockScreen: return "lock.fill"
        case .sleepDisplay: return "display.trianglebadge.exclamationmark"
        case .emptyTrash: return "trash.fill"
        case .desktopIcons: return "menubar.dock.rectangle"
        case .hiddenFiles: return "eye.slash.fill"
        case .ejectDisks: return "eject.fill"
        case .muteMics: return "mic.slash.fill"
        case .nextOutput: return "hifispeaker.fill"
        case .cleaningMode: return "keyboard.badge.eye"
        case .cleanLink: return "link.badge.plus"
        }
    }

    var colors: [Color] {
        switch self {
        case .screenshotArea, .screenshotWindow, .screenshotScreen: return FeatureID.screenshot.colors
        case .textFromScreen: return [Palette.green.color, Palette.mint.color]
        case .colorPicker: return [Palette.orange.color, Palette.pink.color]
        case .recordScreen: return FeatureID.recorder.colors
        case .clipboard: return FeatureID.clipboard.colors
        case .shelf: return FeatureID.shelf.colors
        case .scratchpad: return FeatureID.notes.colors
        case .commandBar: return FeatureID.commandBar.colors
        case .cameraMirror: return [Palette.blue.color, Palette.purple.color]
        case .optimize: return FeatureID.optimizer.colors
        case .keepAwake: return [Palette.orange.color, Palette.yellow.color]
        case .darkMode: return [Palette.indigo.color, Palette.purple.color]
        case .lockScreen, .sleepDisplay: return [Palette.purple.color, Palette.pink.color]
        case .emptyTrash: return [Palette.red.color, Palette.orange.color]
        case .desktopIcons, .hiddenFiles: return [Palette.cyan.color, Palette.blue.color]
        case .ejectDisks: return [Palette.mint.color, Palette.cyan.color]
        case .muteMics: return [Palette.red.color, Palette.pink.color]
        case .nextOutput: return FeatureID.audio.colors
        case .cleaningMode: return [Palette.yellow.color, Palette.green.color]
        case .cleanLink: return FeatureID.fileTools.colors
        }
    }

    func title(_ t: Localizer) -> String {
        switch self {
        case .screenshotArea: return t("Скриншот области", "Screenshot area")
        case .screenshotWindow: return t("Скриншот окна", "Screenshot window")
        case .screenshotScreen: return t("Весь экран", "Whole screen")
        case .textFromScreen: return t("Текст с экрана", "Text from screen")
        case .colorPicker: return t("Пипетка", "Color picker")
        case .recordScreen: return t("Запись экрана", "Record screen")
        case .clipboard: return t("История буфера", "Clipboard")
        case .shelf: return t("Полка", "Shelf")
        case .scratchpad: return t("Черновик", "Scratchpad")
        case .commandBar: return "Command Bar"
        case .cameraMirror: return t("Зеркало", "Camera mirror")
        case .optimize: return t("Оптимизировать", "Optimize")
        case .keepAwake: return t("Не спать", "Stay awake")
        case .darkMode: return t("Тёмная тема", "Dark Mode")
        case .lockScreen: return t("Заблокировать", "Lock screen")
        case .sleepDisplay: return t("Погасить экран", "Sleep display")
        case .emptyTrash: return t("Очистить корзину", "Empty Trash")
        case .desktopIcons: return t("Иконки на столе", "Desktop icons")
        case .hiddenFiles: return t("Скрытые файлы", "Hidden files")
        case .ejectDisks: return t("Извлечь диски", "Eject disks")
        case .muteMics: return t("Микрофоны", "Microphones")
        case .nextOutput: return t("Выход звука", "Sound output")
        case .cleaningMode: return t("Режим чистки", "Cleaning mode")
        case .cleanLink: return t("Очистить ссылку", "Clean link")
        }
    }

    @MainActor
    func run(_ model: AppModel) {
        switch self {
        case .screenshotArea: model.capture.screenshot(.area)
        case .screenshotWindow: model.capture.screenshot(.window)
        case .screenshotScreen: model.capture.screenshot(.screen)
        case .textFromScreen: model.capture.recognizeText()
        case .colorPicker: model.capture.pickColor()
        case .recordScreen: model.recorder.toggle()
        case .clipboard: model.clipboard.showPanel()
        case .shelf: model.shelfPanel.toggle()
        case .scratchpad: model.scratchpad.toggle()
        case .commandBar: model.commandBar.toggle()
        case .cameraMirror: model.cameraMirror.toggle()
        case .optimize: model.optimize()
        case .keepAwake: model.keepAwake.isOn ? model.stopKeepAwake() : model.startKeepAwake(minutes: 60)
        case .darkMode: model.toggleDarkMode()
        case .lockScreen: model.lockScreen()
        case .sleepDisplay: model.sleepDisplay()
        case .emptyTrash: model.emptyTrash()
        case .desktopIcons: model.toggleDesktopIcons()
        case .hiddenFiles: model.toggleHiddenFiles()
        case .ejectDisks: model.ejectAllDisks()
        case .muteMics: model.audio.toggleMicsMuted()
        case .nextOutput: model.audio.cycleOutput()
        case .cleaningMode: model.cleaning.start()
        case .cleanLink: model.clipExtras.cleanClipboardLink()
        }
    }
}

// MARK: - Extra quick actions

extension AppModel {
    func sleepDisplay() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }

    var hiddenFilesShown: Bool {
        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        return (CFPreferencesCopyAppValue("AppleShowAllFiles" as CFString, "com.apple.finder" as CFString) as? Bool) == true
    }

    /// Shows or hides dot-files in Finder (relaunches Finder, like ⇧⌘. does for open windows).
    func toggleHiddenFiles() {
        let show = !hiddenFilesShown
        CFPreferencesSetAppValue("AppleShowAllFiles" as CFString, show as CFBoolean, "com.apple.finder" as CFString)
        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        }
        Toast.show(show ? "eye.fill" : "eye.slash.fill", show ? t("Скрытые файлы видны", "Hidden files shown") : t("Скрытые файлы спрятаны", "Hidden files hidden"))
    }

    /// Ejects every removable or network volume; reports what couldn't be ejected.
    func ejectAllDisks() {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        let ejectable = volumes.filter { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return values?.volumeIsEjectable == true || values?.volumeIsRemovable == true || values?.volumeIsInternal == false
        }.filter { $0.path != "/" }
        guard !ejectable.isEmpty else {
            Toast.show("eject", t("Нечего извлекать", "Nothing to eject"))
            return
        }
        var failed: [String] = []
        for volume in ejectable {
            do { try NSWorkspace.shared.unmountAndEjectDevice(at: volume) } catch { failed.append(volume.lastPathComponent) }
        }
        Toast.show(failed.isEmpty ? "eject.fill" : "exclamationmark.triangle.fill",
                   failed.isEmpty ? t("Диски извлечены: \(ejectable.count)", "Ejected \(ejectable.count)") : t("Занято: ", "In use: ") + failed.joined(separator: ", "),
                   tint: failed.isEmpty ? Palette.green.color : Palette.orange.color)
    }

    func announceFinished(_ agent: AgentUsageStore.Agent, project: String) {
        let title = t("\(agent.title) закончил задачу", "\(agent.title) finished")
        island.showPeek(DynamicIsland.Peek(symbol: "checkmark.seal.fill", title: title, subtitle: project, tint: Palette.green.color))
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = project
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "lumo.agent.\(UUID())", content: content, trigger: nil))
        agents.refresh()
    }
}

// MARK: - Quick panel

/// A floating palette of favorite tools on ⌃⌘V.
@MainActor
final class QuickPanel: NSObject, ObservableObject, NSWindowDelegate {
    private enum Key {
        static let favorites = "quickPanel.favorites"
        static let enabled = "quickPanel.enabled"
    }

    static let defaults: [LumoTool] = [.screenshotArea, .textFromScreen, .colorPicker, .recordScreen, .clipboard, .shelf,
                                       .scratchpad, .keepAwake, .darkMode, .muteMics, .ejectDisks, .lockScreen]

    @Published var isEnabled: Bool { didSet { store.set(isEnabled, forKey: Key.enabled); registerHotKey() } }
    @Published private(set) var favorites: [LumoTool]

    weak var model: AppModel?
    private let store: UserDefaults
    private let hotKeys = HotKeyCenter()
    private var panel: KeyPanel?

    init(store: UserDefaults) {
        self.store = store
        isEnabled = store.object(forKey: Key.enabled) as? Bool ?? false
        favorites = (store.stringArray(forKey: Key.favorites) ?? []).compactMap(LumoTool.init(rawValue:))
        super.init()
        if favorites.isEmpty { favorites = Self.defaults }
        registerHotKey()
    }

    func toggleFavorite(_ tool: LumoTool) {
        favorites = favorites.contains(tool) ? favorites.filter { $0 != tool } : favorites + [tool]
        store.set(favorites.map(\.rawValue), forKey: Key.favorites)
    }

    func toggle() {
        if panel?.isVisible == true { return close() }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let columns = min(max(favorites.count, 1), 4)
        let rows = Int((Double(max(favorites.count, 1)) / 4).rounded(.up))
        let size = CGSize(width: CGFloat(columns) * 96 + 28, height: CGFloat(rows) * 92 + 28)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                                  width: size.width, height: size.height), display: true)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() { panel?.orderOut(nil) }

    func run(_ tool: LumoTool) {
        close()
        guard let model else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { tool.run(model) }
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    private func registerHotKey() {
        hotKeys.unregisterAll()
        if isEnabled { hotKeys.register(.quickPanel) { [weak self] in self?.toggle() } }
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: QuickPanelView(panel: self))
        return panel
    }
}

private struct QuickPanelView: View {
    @ObservedObject var panel: QuickPanel

    var body: some View {
        let t = panel.model?.t ?? Localizer(language: .english)
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(88), spacing: 8), count: min(max(panel.favorites.count, 1), 4)), spacing: 8) {
            ForEach(panel.favorites) { tool in
                QuickToolButton(tool: tool, title: tool.title(t)) { panel.run(tool) }
            }
        }
        .padding(14)
        .navyGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onKeyPress(.escape) { panel.close(); return .handled }
    }
}

struct QuickToolButton: View {
    let tool: LumoTool
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                IconBadge(symbol: tool.symbol, colors: tool.colors, size: 40)
                Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(width: 88, height: 84)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(hovering ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Scratchpad window

/// The notes in a floating, always-on-top window.
@MainActor
final class ScratchpadWindow: NSObject, NSWindowDelegate {
    private let notes: NotesStore
    private let hotKeys = HotKeyCenter()
    private var window: NSPanel?
    var t = Localizer(language: .english)

    init(notes: NotesStore) {
        self.notes = notes
        super.init()
        hotKeys.register(.scratchpad) { [weak self] in self?.toggle() }
    }

    func toggle() {
        if let window, window.isVisible { return window.orderOut(nil) }
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSPanel {
        let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 380, height: 420),
                             styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView], backing: .buffered, defer: true)
        window.title = t("Черновик", "Scratchpad")
        window.titlebarAppearsTransparent = true
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: ScratchpadView(notes: notes, t: t))
        window.center()
        window.setFrameAutosaveName("LumoScratchpad")
        return window
    }
}

private struct ScratchpadView: View {
    @ObservedObject var notes: NotesStore
    let t: Localizer
    @State private var preview = false

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(notes.notes) { note in
                        Button { notes.selectedID = note.id } label: {
                            Text(note.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(note.id == notes.selectedID ? Palette.yellow.color.opacity(0.3) : Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                    Button { notes.add() } label: { Image(systemName: "plus") }.buttonStyle(.borderless)
                }
            }
            .scrollIndicators(.never)
            if let note = notes.selected ?? notes.notes.first {
                if preview {
                    ScrollView {
                        Text((try? AttributedString(markdown: note.body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                             ?? AttributedString(note.body))
                            .frame(maxWidth: .infinity, alignment: .topLeading).textSelection(.enabled)
                    }
                } else {
                    TextEditor(text: Binding(get: { note.body }, set: { notes.update(note.id, body: $0) }))
                        .font(.system(size: 13)).scrollContentBackground(.hidden)
                }
                HStack {
                    Toggle(t("Просмотр", "Preview"), isOn: $preview).toggleStyle(.button).controlSize(.small)
                    Spacer()
                    Button { _ = notes.exportToDesktop(note) } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(.borderless)
                }
            } else {
                Button(t("Новая заметка", "New note")) { notes.add() }.frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 10).padding(.top, 30)
        .frame(minWidth: 280, minHeight: 240)
    }
}

// MARK: - Cleaning mode

/// Locks the keyboard (and media keys) so you can wipe it; the mouse stays free to finish.
@MainActor
final class CleaningMode: ObservableObject {
    enum Style: String, CaseIterable, Identifiable {
        case blackScreen, indicator

        var id: Self { self }
    }

    @Published var style: Style { didSet { UserDefaults.standard.set(style.rawValue, forKey: "cleaning.style") } }
    @Published private(set) var isActive = false
    var t = Localizer(language: .english)

    private let tap = InputTap()
    private var windows: [NSWindow] = []

    init() {
        style = Style(rawValue: UserDefaults.standard.string(forKey: "cleaning.style") ?? "") ?? .blackScreen
    }

    func start() {
        guard !isActive else { return }
        guard AXIsProcessTrusted() else {
            Toast.show("hand.raised.fill", t("Нужен «Универсальный доступ»", "Needs Accessibility access"), tint: Palette.orange.color)
            return
        }
        isActive = true
        let systemDefined = CGEventType(rawValue: 14)!
        tap.configure([(InputTap.mask(.keyDown, .keyUp, .flagsChanged, systemDefined), { _, _ in nil })])
        let screens = style == .blackScreen ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        windows = screens.map(makeWindow)
        windows.forEach { $0.orderFrontRegardless() }
    }

    func stop() {
        tap.stop()
        windows.forEach { $0.orderOut(nil) }
        windows = []
        isActive = false
    }

    private func makeWindow(on screen: NSScreen) -> NSWindow {
        let frame = style == .blackScreen ? screen.frame
            : CGRect(x: screen.frame.midX - 160, y: screen.visibleFrame.minY + 80, width: 320, height: 120)
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = style == .blackScreen
        window.backgroundColor = style == .blackScreen ? .black : .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = NSHostingView(rootView: CleaningView(style: style, t: t) { [weak self] in self?.stop() })
        return window
    }
}

private struct CleaningView: View {
    let style: CleaningMode.Style
    let t: Localizer
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "keyboard.badge.eye").font(.system(size: style == .blackScreen ? 46 : 26)).foregroundStyle(.white.opacity(0.85))
            Text(t("Клавиатура заблокирована — можно протирать", "Keyboard locked — wipe away"))
                .font(.system(size: style == .blackScreen ? 17 : 12.5, weight: .semibold)).foregroundStyle(.white)
            Button(t("Готово", "Done"), action: finish)
                .buttonStyle(.borderedProminent).controlSize(style == .blackScreen ? .large : .regular)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(style == .indicator ? AnyView(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.85))) : AnyView(Color.black))
    }
}

// MARK: - Camera mirror

/// A small round mirror to check yourself before a call. Drag to move, double-click to close.
@MainActor
final class CameraMirror {
    private var panel: NSPanel?

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            panel.contentView = nil
            return
        }
        let panel = self.panel ?? {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            return panel
        }()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: CameraPreview()
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 2))
            .onTapGesture(count: 2) { [weak self] in self?.toggle() })
        if let screen = NSScreen.main {
            panel.setFrame(CGRect(x: screen.visibleFrame.maxX - 236, y: screen.visibleFrame.maxY - 236, width: 220, height: 220), display: true)
        }
        panel.orderFrontRegardless()
    }
}
