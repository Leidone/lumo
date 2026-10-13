import AppKit
import Carbon
import LumoCore

/// Keyboard fixes: a filter for keys that double-type on a worn keyboard, and a Super key
/// (Caps Lock or a right-hand modifier acting as ⌃⌥⇧⌘, with its own action when tapped alone).
@MainActor
final class KeyboardTools: ObservableObject {
    enum SuperSource: String, CaseIterable, Identifiable {
        case off, capsLock, rightCommand, rightOption

        var id: Self { self }
    }

    enum TapAction: String, CaseIterable, Identifiable {
        case none, escape, commandBar, quickPanel

        var id: Self { self }
    }

    private enum Key {
        static let debounce = "keyboard.debounce"
        static let debounceThreshold = "keyboard.debounceThreshold"
        static let superSource = "keyboard.superSource"
        static let tapAction = "keyboard.tapAction"
        static let superExclusions = "keyboard.superExclusions"
    }

    private static let f18: Int64 = 79
    private static let rightCommand: Int64 = 54
    private static let rightOption: Int64 = 61
    private static let hyper: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    @Published var debounce: Bool { didSet { save(debounce, Key.debounce) } }
    @Published var debounceThreshold: Double { didSet { save(debounceThreshold, Key.debounceThreshold) } }
    @Published var superSource: SuperSource {
        didSet {
            applyCapsLockMapping()
            save(superSource.rawValue, Key.superSource)
        }
    }
    @Published var tapAction: TapAction { didSet { save(tapAction.rawValue, Key.tapAction) } }
    @Published var superExclusions: [String] { didSet { save(superExclusions, Key.superExclusions) } }

    var onChange: (() -> Void)?
    /// Runs the tap action (Command Bar, Quick panel) — wired by the app model.
    var perform: ((TapAction) -> Void)?

    private let store: UserDefaults
    private var keyDebouncer = PressDebouncer(threshold: 0.04)
    private var superHeld = false
    private var superUsed = false

    init(store: UserDefaults) {
        store.register(defaults: [Key.debounceThreshold: 0.04])
        self.store = store
        debounce = store.bool(forKey: Key.debounce)
        debounceThreshold = store.double(forKey: Key.debounceThreshold)
        superSource = SuperSource(rawValue: store.string(forKey: Key.superSource) ?? "") ?? .off
        tapAction = TapAction(rawValue: store.string(forKey: Key.tapAction) ?? "") ?? .escape
        superExclusions = store.stringArray(forKey: Key.superExclusions) ?? []
        keyDebouncer = PressDebouncer(threshold: debounceThreshold)
        // The hidutil remap is lost on restart, so it's re-applied whenever Lumo starts.
        applyCapsLockMapping()
    }

    var usesTap: Bool { debounce || superSource != .off }

    var handlers: [(mask: CGEventMask, handle: InputTap.Handler)] {
        var result: [(mask: CGEventMask, handle: InputTap.Handler)] = []
        if debounce {
            result.append((InputTap.mask(.keyDown, .keyUp), { [weak self] type, event in self?.filterKey(type, event) ?? event }))
        }
        if superSource != .off {
            result.append((InputTap.mask(.keyDown, .keyUp, .flagsChanged), { [weak self] type, event in self?.handleSuper(type, event) ?? event }))
        }
        return result
    }

    func toggleExclusion(_ bundleID: String) {
        superExclusions = superExclusions.contains(bundleID) ? superExclusions.filter { $0 != bundleID } : superExclusions + [bundleID]
    }

    /// Puts Caps Lock back the way it was when Lumo quits.
    func shutdown() {
        if superSource == .capsLock { Self.setMappings(HIDKeyMapping.removing(.capsLockToF18, from: Self.currentMappings())) }
    }

    private func save(_ value: Any, _ key: String) {
        store.set(value, forKey: key)
        keyDebouncer = PressDebouncer(threshold: debounceThreshold)
        onChange?()
    }

    // MARK: Debounce

    private func filterKey(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return event }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let now = ProcessInfo.processInfo.systemUptime
        let drop = type == .keyDown ? keyDebouncer.dropDown(key: code, at: now) : keyDebouncer.dropUp(key: code, at: now)
        return drop ? nil : event
    }

    // MARK: Super key

    private var isExcluded: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier.map(superExclusions.contains) == true
    }

    private func handleSuper(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        guard !isExcluded else { return event }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        switch (superSource, type) {
        case (.capsLock, .keyDown) where code == Self.f18:
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                superHeld = true
                superUsed = false
            }
            return nil
        case (.capsLock, .keyUp) where code == Self.f18:
            superHeld = false
            if !superUsed { runTap() }
            return nil
        case (.rightCommand, .flagsChanged) where code == Self.rightCommand,
             (.rightOption, .flagsChanged) where code == Self.rightOption:
            let flag: CGEventFlags = superSource == .rightCommand ? .maskCommand : .maskAlternate
            if event.flags.contains(flag) {
                superHeld = true
                superUsed = false
            } else if superHeld {
                superHeld = false
                if !superUsed { runTap() }
            }
            return event
        case (_, .keyDown), (_, .keyUp):
            guard superHeld else { return event }
            superUsed = true
            event.flags = event.flags.union(Self.hyper)
            return event
        default:
            return event
        }
    }

    private func runTap() {
        switch tapAction {
        case .none: break
        case .escape:
            for isDown in [true, false] {
                guard let key = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Escape), keyDown: isDown) else { continue }
                key.setIntegerValueField(.eventSourceUserData, value: InputTap.syntheticMarker)
                key.post(tap: .cghidEventTap)
            }
        case .commandBar, .quickPanel:
            let action = tapAction
            DispatchQueue.main.async { [weak self] in self?.perform?(action) }
        }
    }

    // MARK: hidutil

    private func applyCapsLockMapping() {
        let current = Self.currentMappings()
        let next = superSource == .capsLock
            ? HIDKeyMapping.adding(.capsLockToF18, to: current)
            : HIDKeyMapping.removing(.capsLockToF18, from: current)
        if next != current { Self.setMappings(next) }
    }

    private static func currentMappings() -> [HIDKeyMapping] {
        HIDKeyMapping.parse(run(["property", "--get", "UserKeyMapping"]))
    }

    private static func setMappings(_ list: [HIDKeyMapping]) {
        _ = run(["property", "--set", HIDKeyMapping.json(list)])
    }

    @discardableResult
    private static func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
