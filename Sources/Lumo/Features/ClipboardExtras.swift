import AppKit
import ApplicationServices
import Carbon
import LumoCore

/// Clipboard and Finder helpers: auto-clear, plain-text paste, link cleaning and Finder shortcuts.
@MainActor
final class ClipboardExtras: ObservableObject {
    private enum Key {
        static let clearAfter = "extras.clearAfterMinutes"
        static let clearOnSleep = "extras.clearOnSleep"
        static let clearOnLock = "extras.clearOnLock"
        static let pastePlain = "extras.pastePlain"
        static let autoCleanLinks = "extras.autoCleanLinks"
        static let finderCutPaste = "extras.finderCutPaste"
        static let finderRename = "extras.finderRename"
        static let finderPasteImage = "extras.finderPasteImage"
    }

    private static let finderID = "com.apple.finder"
    private static let restoreDelay = 0.6

    /// 0 means never.
    @Published var clearAfterMinutes: Int { didSet { store.set(clearAfterMinutes, forKey: Key.clearAfter); scheduleClear() } }
    @Published var clearOnSleep: Bool { didSet { store.set(clearOnSleep, forKey: Key.clearOnSleep) } }
    @Published var clearOnLock: Bool { didSet { store.set(clearOnLock, forKey: Key.clearOnLock) } }
    @Published var pastePlainEnabled: Bool { didSet { store.set(pastePlainEnabled, forKey: Key.pastePlain); registerHotKeys() } }
    @Published var autoCleanLinks: Bool { didSet { store.set(autoCleanLinks, forKey: Key.autoCleanLinks); updatePolling() } }
    @Published var finderCutPaste: Bool { didSet { save(finderCutPaste, Key.finderCutPaste) } }
    @Published var finderRename: Bool { didSet { save(finderRename, Key.finderRename) } }
    @Published var finderPasteImage: Bool { didSet { save(finderPasteImage, Key.finderPasteImage) } }
    @Published private(set) var cleanedLinks = 0

    var t = Localizer(language: .english)
    var onChange: (() -> Void)?

    private let store: UserDefaults
    private let hotKeys = HotKeyCenter()
    private var observers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var clearWork: DispatchWorkItem?
    private var lastChange = NSPasteboard.general.changeCount
    private var cutPending = false

    init(store: UserDefaults) {
        self.store = store
        clearAfterMinutes = store.integer(forKey: Key.clearAfter)
        clearOnSleep = store.bool(forKey: Key.clearOnSleep)
        clearOnLock = store.bool(forKey: Key.clearOnLock)
        pastePlainEnabled = store.bool(forKey: Key.pastePlain)
        autoCleanLinks = store.bool(forKey: Key.autoCleanLinks)
        finderCutPaste = store.bool(forKey: Key.finderCutPaste)
        finderRename = store.bool(forKey: Key.finderRename)
        finderPasteImage = store.bool(forKey: Key.finderPasteImage)
    }

    func start() {
        observe()
        registerHotKeys()
        updatePolling()
    }

    private func save(_ value: Any, _ key: String) {
        store.set(value, forKey: key)
        onChange?()
    }

    // MARK: Watching the clipboard

    /// One cheap changeCount check per second, only while a feature needs it.
    private func updatePolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        guard autoCleanLinks || clearAfterMinutes > 0 else { return }
        lastChange = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        if autoCleanLinks, let text = pasteboard.string(forType: .string), let cleaned = URLCleaner.clean(text) {
            pasteboard.clearContents()
            pasteboard.setString(cleaned, forType: .string)
            lastChange = pasteboard.changeCount
            cleanedLinks += 1
        }
        scheduleClear()
    }

    /// Cleans the link on the clipboard now; returns false when there was nothing to clean.
    @discardableResult
    func cleanClipboardLink() -> Bool {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string), let cleaned = URLCleaner.clean(text) else {
            Toast.show("link", t("В буфере нет ссылки с трекерами", "No tracking link on the clipboard"), tint: Palette.blue.color)
            return false
        }
        pasteboard.clearContents()
        pasteboard.setString(cleaned, forType: .string)
        lastChange = pasteboard.changeCount
        cleanedLinks += 1
        Toast.show("link.badge.plus", t("Ссылка очищена", "Link cleaned"), subtitle: cleaned, tint: Palette.green.color)
        return true
    }

    // MARK: Auto clear

    private func scheduleClear() {
        clearWork?.cancel()
        guard clearAfterMinutes > 0 else { return }
        let change = NSPasteboard.general.changeCount
        let work = DispatchWorkItem { [weak self] in
            // Only clears what was copied back then — a newer copy restarts the countdown.
            guard NSPasteboard.general.changeCount == change else { return }
            self?.clearClipboard()
        }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(clearAfterMinutes * 60), execute: work)
    }

    /// Clears the system clipboard; Lumo's history keeps what it saved.
    func clearClipboard() {
        NSPasteboard.general.clearContents()
        lastChange = NSPasteboard.general.changeCount
    }

    private func observe() {
        guard observers.isEmpty else { return }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { if self?.clearOnSleep == true { self?.clearClipboard() } }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { if self?.clearOnLock == true { self?.clearClipboard() } }
        })
    }

    // MARK: Paste as plain text

    private func registerHotKeys() {
        hotKeys.unregisterAll()
        if pastePlainEnabled { hotKeys.register(.pastePlain) { [weak self] in self?.pastePlain() } }
    }

    /// Pastes only the text, then puts the original (formatted) clipboard back.
    func pastePlain() {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string) else { return }
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in result[type] = item.data(forType: type) }
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Paster.pressPaste()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreDelay) {
            pasteboard.clearContents()
            let items = saved.map { contents -> NSPasteboardItem in
                let item = NSPasteboardItem()
                contents.forEach { item.setData($0.value, forType: $0.key) }
                return item
            }
            pasteboard.writeObjects(items)
        }
    }

    // MARK: Finder shortcuts

    var usesTap: Bool { finderCutPaste || finderRename || finderPasteImage }

    var handlers: [(mask: CGEventMask, handle: InputTap.Handler)] {
        guard usesTap else { return [] }
        return [(InputTap.mask(.keyDown), { [weak self] _, event in self?.handleFinderKey(event) ?? event })]
    }

    private func handleFinderKey(_ event: CGEvent) -> CGEvent? {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finderID, !Self.isEditingText() else { return event }
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        switch (code, flags) {
        case (kVK_ANSI_X, .maskCommand) where finderCutPaste:
            Self.press(kVK_ANSI_C, flags: .maskCommand)
            cutPending = true
            Toast.show("scissors", t("Вырезано — вставьте ⌘V, чтобы переместить", "Cut — press ⌘V to move"), tint: Palette.orange.color)
            return nil
        case (kVK_ANSI_V, .maskCommand):
            if finderCutPaste, cutPending {
                cutPending = false
                Self.press(kVK_ANSI_V, flags: [.maskCommand, .maskAlternate])
                return nil
            }
            if finderPasteImage, pasteImageAsFile() { return nil }
            return event
        case (kVK_ANSI_C, .maskCommand):
            cutPending = false
            return event
        case (kVK_F2, []) where finderRename:
            Self.press(kVK_Return, flags: [])
            return nil
        default:
            return event
        }
    }

    /// Saves a copied image (no files on the clipboard) as a PNG in the open Finder folder.
    private func pasteImageAsFile() -> Bool {
        let pasteboard = NSPasteboard.general
        guard !(pasteboard.types ?? []).contains(.fileURL), let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return false }
        let script = "tell application \"Finder\" to if (count of Finder windows) > 0 then get POSIX path of (target of front Finder window as alias) else get POSIX path of (desktop as alias)"
        var error: NSDictionary?
        guard let folder = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = URL(fileURLWithPath: folder).appendingPathComponent(t("Изображение ", "Image ") + formatter.string(from: Date()) + ".png")
        guard (try? png.write(to: url)) != nil else { return false }
        Toast.show("photo.badge.plus", t("Сохранено как PNG", "Saved as PNG"), subtitle: url.lastPathComponent, tint: Palette.green.color)
        return true
    }

    private static func isEditingText() -> Bool {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return false }
        let role = AXWindow.string(focused as! AXUIElement, kAXRoleAttribute)
        return role == kAXTextFieldRole || role == kAXTextAreaRole || role == "AXSearchField"
    }

    private static func press(_ key: Int, flags: CGEventFlags) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: isDown) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: InputTap.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}
