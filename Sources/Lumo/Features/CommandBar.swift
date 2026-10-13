import AppKit
import Carbon
import LumoCore
import SwiftUI

/// ⌥Space launcher: apps, files, clipboard, snippets, calculator, units, emoji and Lumo commands.
@MainActor
final class CommandBar: NSObject, ObservableObject, NSWindowDelegate {
    struct Command: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: Icon
        let run: () -> Void
    }

    enum Icon {
        case image(NSImage)
        case symbol(String, [Color])
        case text(String)
    }

    struct Script: Codable, Identifiable, Equatable {
        var id = UUID()
        var name: String
        var command: String
    }

    private static let enabledKey = "commandBar.enabled"
    private static let scriptsKey = "commandBar.scripts"
    private static let menuItemLimit = 600

    @Published var isEnabled: Bool { didSet { store.set(isEnabled, forKey: Self.enabledKey); registerHotKey() } }
    @Published var query = "" { didSet { search() } }
    @Published private(set) var results: [Command] = []
    @Published var selection = 0
    @Published var scripts: [Script] {
        didSet { if let data = try? JSONEncoder().encode(scripts) { store.set(data, forKey: Self.scriptsKey) } }
    }

    /// Lumo's own actions, supplied by the app model.
    var actions: () -> [Command] = { [] }
    var clipboard: ClipboardStore?
    var snippets: SnippetStore?
    var t = Localizer(language: .english)

    private let store: UserDefaults
    private let hotKeys = HotKeyCenter()
    private var panel: KeyPanel?
    private var apps: [(name: String, url: URL)] = []
    private var appsIndexedAt = Date.distantPast
    private var fileQuery: NSMetadataQuery?
    private var fileResults: [Command] = []
    /// Menu commands of the app that was in front when the bar opened, read lazily.
    private var menuApp: NSRunningApplication?
    private var menuItems: [(path: String, element: AXUIElement)]?

    init(store: UserDefaults) {
        self.store = store
        isEnabled = store.bool(forKey: Self.enabledKey)
        scripts = store.data(forKey: Self.scriptsKey).flatMap { try? JSONDecoder().decode([Script].self, from: $0) } ?? []
        super.init()
        registerHotKey()
    }

    func toggle() {
        if let panel, panel.isVisible { return close() }
        indexAppsIfNeeded()
        menuApp = NSWorkspace.shared.frontmostApplication
        menuItems = nil
        query = ""
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let size = CGSize(width: 620, height: 420)
            panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - screen.frame.height * 0.14,
                                  width: size.width, height: size.height), display: true)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        fileQuery?.stop()
    }

    func runSelected() {
        guard results.indices.contains(selection) else { return }
        let command = results[selection]
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { command.run() }
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    // MARK: Search

    private func search() {
        selection = 0
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            results = Array(actions().prefix(8))
            return
        }
        var found: [Command] = []
        if Calculator.looksLikeMath(text), let value = Calculator.evaluate(text) {
            let formatted = Self.format(value)
            found.append(Command(id: "calc", title: "= \(formatted)", subtitle: t("Скопировать результат", "Copy the result"),
                                 icon: .symbol("equal.circle.fill", [Palette.orange.color, Palette.pink.color])) { Self.copy(formatted) })
        }
        if let converted = UnitConverter.convert(text) {
            let formatted = "\(Self.format(converted.value)) \(converted.unit)"
            found.append(Command(id: "unit", title: formatted, subtitle: t("Скопировать", "Copy"),
                                 icon: .symbol("ruler.fill", [Palette.blue.color, Palette.cyan.color])) { Self.copy(formatted) })
        }
        found += actions().filter { $0.title.localizedCaseInsensitiveContains(text) }.prefix(4)
        found += apps.filter { $0.name.localizedCaseInsensitiveContains(text) }
            .sorted { lhs, rhs in
                let l = lhs.name.lowercased().hasPrefix(text.lowercased()), r = rhs.name.lowercased().hasPrefix(text.lowercased())
                return l != r ? l : lhs.name < rhs.name
            }
            .prefix(6)
            .map { app in
                Command(id: "app:\(app.url.path)", title: app.name, subtitle: t("Приложение", "Application"),
                        icon: .image(IconCache.icon(for: app.url.path))) { NSWorkspace.shared.open(app.url) }
            }
        found += windowCommands(matching: text)
        found += scripts.filter { $0.name.localizedCaseInsensitiveContains(text) }.prefix(4).map { script in
            Command(id: "script:\(script.id)", title: script.name, subtitle: t("Скрипт · ", "Script · ") + script.command,
                    icon: .symbol("terminal.fill", [Palette.green.color, Palette.mint.color])) { [weak self] in self?.run(script) }
        }
        if text.count >= 2 { found += menuCommands(matching: text) }
        if let snippets {
            found += snippets.snippets.filter { $0.trigger.localizedCaseInsensitiveContains(text) || $0.expansion.localizedCaseInsensitiveContains(text) }
                .prefix(3)
                .map { snippet in
                    Command(id: "snippet:\(snippet.id)", title: snippet.expansion, subtitle: t("Сниппет ", "Snippet ") + snippet.trigger,
                            icon: .symbol("text.badge.plus", FeatureID.snippets.colors)) { Self.paste(snippet.expansion) }
                }
        }
        if let clipboard, clipboard.isEnabled {
            found += clipboard.sortedEntries.filter { $0.kind == .text && $0.matches(text) }.prefix(3).map { entry in
                Command(id: "clip:\(entry.id)", title: entry.text ?? "", subtitle: t("Из истории буфера", "From clipboard history"),
                        icon: .symbol("doc.on.clipboard.fill", FeatureID.clipboard.colors)) { [weak clipboard] in clipboard?.paste(entry) }
            }
        }
        found += EmojiIndex.search(text, limit: 6).map { item in
            Command(id: "emoji:\(item.emoji)", title: "\(item.emoji)  \(item.name)", subtitle: t("Эмодзи — вставить", "Emoji — paste"),
                    icon: .text(item.emoji)) { Self.paste(item.emoji) }
        }
        results = found + fileResults
        searchFiles(text)
    }

    private func searchFiles(_ text: String) {
        fileQuery?.stop()
        guard text.count >= 3 else {
            fileResults = []
            return
        }
        let metadata = NSMetadataQuery()
        metadata.predicate = NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", text)
        metadata.searchScopes = [NSMetadataQueryUserHomeScope]
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: metadata, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.collectFiles(metadata, for: text) }
        }
        fileQuery = metadata
        metadata.start()
    }

    private func collectFiles(_ metadata: NSMetadataQuery, for text: String) {
        metadata.stop()
        guard text == query.trimmingCharacters(in: .whitespaces) else { return }
        let items = (0..<min(metadata.resultCount, 6)).compactMap { metadata.result(at: $0) as? NSMetadataItem }
        fileResults = items.compactMap { item in
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            let url = URL(fileURLWithPath: path)
            return Command(id: "file:\(path)", title: url.lastPathComponent,
                           subtitle: (path as NSString).abbreviatingWithTildeInPath, icon: .image(IconCache.icon(for: path))) {
                NSWorkspace.shared.open(url)
            }
        }
        results = results.filter { !$0.id.hasPrefix("file:") } + fileResults
    }

    // MARK: Windows, menus, scripts

    private func windowCommands(matching text: String) -> [Command] {
        AppSwitcher.onScreenWindows()
            .filter { !$0.title.isEmpty && $0.pid != getpid() && $0.title.localizedCaseInsensitiveContains(text) }
            .prefix(5)
            .map { window in
                let app = NSRunningApplication(processIdentifier: window.pid)
                return Command(id: "window:\(window.id)", title: window.title, subtitle: t("Окно · ", "Window · ") + (app?.localizedName ?? ""),
                               icon: .image(app?.icon ?? NSImage())) {
                    AXWindow.raise(pid: window.pid, title: window.title)
                    app?.activate()
                }
            }
    }

    private func menuCommands(matching text: String) -> [Command] {
        guard let app = menuApp, AXIsProcessTrusted() else { return [] }
        if menuItems == nil { menuItems = Self.readMenu(of: app) }
        return (menuItems ?? []).filter { $0.path.localizedCaseInsensitiveContains(text) }.prefix(6).map { item in
            Command(id: "menu:\(item.path)", title: item.path.components(separatedBy: " › ").last ?? item.path,
                    subtitle: t("Меню · ", "Menu · ") + item.path, icon: .image(app.icon ?? NSImage())) {
                app.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { AXUIElementPerformAction(item.element, kAXPressAction as CFString) }
            }
        }
    }

    /// Walks the app's menu bar (three levels deep) and keeps enabled leaf items.
    private static func readMenu(of app: NSRunningApplication) -> [(path: String, element: AXUIElement)] {
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXMenuBarAttribute as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID()
        else { return [] }
        var result: [(path: String, element: AXUIElement)] = []
        func children(_ element: AXUIElement) -> [AXUIElement] {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
            return value as? [AXUIElement] ?? []
        }
        func walk(_ element: AXUIElement, path: [String], depth: Int) {
            guard result.count < menuItemLimit, depth < 5 else { return }
            for child in children(element) {
                let title = AXWindow.string(child, kAXTitleAttribute) ?? ""
                let kids = children(child)
                if kids.isEmpty {
                    var enabled: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, kAXEnabledAttribute as CFString, &enabled)
                    if !title.isEmpty, (enabled as? Bool) != false, path.count > 1 {
                        result.append(((path + [title]).dropFirst().joined(separator: " › "), child))
                    }
                } else {
                    walk(child, path: title.isEmpty ? path : path + [title], depth: depth + 1)
                }
            }
        }
        walk(bar as! AXUIElement, path: ["bar"], depth: 0)
        return result
    }

    func addScript(name: String, command: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces), trimmedCommand = command.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedCommand.isEmpty else { return }
        scripts.append(Script(name: trimmedName, command: trimmedCommand))
    }

    func removeScript(_ script: Script) { scripts.removeAll { $0.id == script.id } }

    /// Runs a saved script in the user's login shell and shows the first line of its output.
    func run(_ script: Script) {
        let t = self.t
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", script.command]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            guard (try? process.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? ""
            let ok = process.terminationStatus == 0
            await MainActor.run {
                Toast.show(ok ? "checkmark.circle.fill" : "xmark.octagon.fill", script.name + (ok ? t(" — готово", " — done") : t(" — ошибка", " — failed")),
                           subtitle: output, tint: ok ? Palette.green.color : Palette.red.color)
            }
        }
    }

    private func indexAppsIfNeeded() {
        guard Date().timeIntervalSince(appsIndexedAt) > 600 else { return }
        appsIndexedAt = Date()
        let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                     FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        apps = roots.flatMap { root in
            ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [])
                .filter { $0.hasSuffix(".app") }
                .map { (name: FileManager.default.displayName(atPath: "\(root)/\($0)").replacingOccurrences(of: ".app", with: ""),
                        url: URL(fileURLWithPath: "\(root)/\($0)")) }
        }
    }

    // MARK: Helpers

    private func registerHotKey() {
        hotKeys.unregisterAll()
        guard isEnabled else { return }
        hotKeys.register(.commandBar) { [weak self] in self?.toggle() }
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                             backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: CommandBarView(bar: self))
        return panel
    }

    private static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 6
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter.string(from: value as NSNumber) ?? "\(value)"
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func paste(_ text: String) {
        copy(text)
        Paster.pressPaste()
    }
}

private struct CommandBarView: View {
    @ObservedObject var bar: CommandBar
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass").font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.brand)
                TextField(bar.t("Поиск приложений, файлов, расчёты…", "Search apps, files, math…"), text: $bar.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .medium))
                    .focused($focused)
            }
            .padding(.horizontal, 16).padding(.top, 14)
            Divider().opacity(0.4)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(bar.results.enumerated()), id: \.element.id) { index, command in
                            row(command, selected: index == bar.selection)
                                .id(index)
                                .onTapGesture {
                                    bar.selection = index
                                    bar.runSelected()
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .scrollIndicators(.never)
                .onChange(of: bar.selection) { _, value in withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(value) } }
            }
        }
        .padding(.bottom, 8)
        .navyGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { bar.selection = min(bar.selection + 1, max(bar.results.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { bar.selection = max(bar.selection - 1, 0); return .handled }
        .onKeyPress(.return) { bar.runSelected(); return .handled }
        .onKeyPress(.escape) { bar.close(); return .handled }
    }

    private func row(_ command: CommandBar.Command, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                switch command.icon {
                case .image(let image): Image(nsImage: image).resizable().frame(width: 28, height: 28)
                case .symbol(let name, let colors): IconBadge(symbol: name, colors: colors, size: 28)
                case .text(let text): Text(text).font(.system(size: 22)).frame(width: 28, height: 28)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                Text(command.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if selected { Text("↩").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(selected ? AnyShapeStyle(LinearGradient(colors: [Palette.indigo.color.opacity(0.45), Palette.azure.color.opacity(0.3)],
                                                          startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.clear)))
        .contentShape(Rectangle())
    }
}
