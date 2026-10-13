import AppKit
import Carbon
import LumoCore

/// Text expansion: type a trigger like `;date` anywhere and it turns into the snippet's text.
@MainActor
final class SnippetStore: ObservableObject {
    private static let enabledKey = "snippets.enabled"
    private static let resetKeys: Set<Int64> = [36, 48, 53, 76, 115, 116, 119, 121, 123, 124, 125, 126]

    @Published var isEnabled: Bool { didSet { store.set(isEnabled, forKey: Self.enabledKey); configure() } }
    @Published private(set) var snippets: [Snippet] = []

    private let store: UserDefaults
    private let file: URL
    private let tap = InputTap()
    private var matcher = SnippetMatcher()
    private var accessibility = AXIsProcessTrusted()

    init(store: UserDefaults) {
        self.store = store
        isEnabled = store.bool(forKey: Self.enabledKey)
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumo", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = folder.appendingPathComponent("snippets.json")
        load()
        configure()
    }

    func refreshPermission() {
        let granted = AXIsProcessTrusted()
        guard granted != accessibility else { return }
        accessibility = granted
        configure()
    }

    func add(trigger: String, expansion: String) {
        let trimmed = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !expansion.isEmpty else { return }
        snippets = snippets.filter { $0.trigger != trimmed } + [Snippet(trigger: trimmed, expansion: expansion)]
        save()
    }

    func delete(_ snippet: Snippet) {
        snippets = snippets.filter { $0.id != snippet.id }
        save()
    }

    // MARK: Typing

    private func configure() {
        guard isEnabled else { return tap.stop() }
        tap.configure([(InputTap.mask(.keyDown, .leftMouseDown), { [weak self] type, event in self?.handle(type, event) ?? event })])
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        guard type == .keyDown else {
            matcher.reset()
            return event
        }
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            matcher.reset()
            return event
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if code == Int64(kVK_Delete) {
            matcher.backspace()
            return event
        }
        if Self.resetKeys.contains(code) {
            matcher.reset()
            return event
        }
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &characters)
        guard length > 0 else { return event }
        matcher.type(String(utf16CodeUnits: characters, count: length))
        guard let snippet = matcher.match(in: snippets) else { return event }
        expand(snippet)
        return nil
    }

    /// The trigger's last character is swallowed, so only `count - 1` characters need erasing.
    private func expand(_ snippet: Snippet) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        let text = SnippetMatcher.expand(snippet.expansion, date: Date(), clipboard: previous, locale: .current)
        Paster.pressBackspace(times: max(snippet.trigger.count - 1, 0))
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.TransientType")], owner: nil)
        pasteboard.setString(text, forType: .string)
        Paster.pressPaste()
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            pasteboard.clearContents()
            if let previous {
                pasteboard.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.TransientType")], owner: nil)
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    // MARK: Persistence

    private func load() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Snippet].self, from: data) {
            snippets = saved
        } else {
            snippets = [Snippet(trigger: ";date", expansion: "{date}"), Snippet(trigger: ";time", expansion: "{time}")]
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
