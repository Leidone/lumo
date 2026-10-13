import Foundation

// MARK: - Debounce

/// Drops a press that follows its own release faster than a human can (worn keys and buttons),
/// and the release that belongs to it.
public struct PressDebouncer: Sendable {
    public var threshold: Double
    private var lastUp: [Int64: Double] = [:]
    private var dropped: Set<Int64> = []

    public init(threshold: Double) {
        self.threshold = threshold
    }

    public mutating func dropDown(key: Int64, at time: Double) -> Bool {
        guard let up = lastUp[key], time - up < threshold else { return false }
        dropped.insert(key)
        return true
    }

    public mutating func dropUp(key: Int64, at time: Double) -> Bool {
        if dropped.remove(key) != nil { return true }
        lastUp[key] = time
        return false
    }
}

// MARK: - Mouse gestures

public enum MouseGesture: String, CaseIterable, Sendable {
    case left, right, up, down

    /// The dominant direction of a button drag, once it travelled far enough.
    public static func direction(dx: Double, dy: Double, threshold: Double) -> MouseGesture? {
        guard max(abs(dx), abs(dy)) >= threshold else { return nil }
        if abs(dx) >= abs(dy) { return dx > 0 ? .right : .left }
        return dy > 0 ? .down : .up
    }
}

// MARK: - hidutil key remapping

/// One `hidutil` UserKeyMapping entry (HID usage page 7 codes).
public struct HIDKeyMapping: Equatable, Sendable {
    public let source: UInt64
    public let destination: UInt64

    public init(source: UInt64, destination: UInt64) {
        self.source = source
        self.destination = destination
    }

    /// Caps Lock becomes F18, which Lumo then treats as the Super key.
    public static let capsLockToF18 = HIDKeyMapping(source: 0x7_0000_0039, destination: 0x7_0000_006D)

    public static func adding(_ mapping: HIDKeyMapping, to list: [HIDKeyMapping]) -> [HIDKeyMapping] {
        list.filter { $0.source != mapping.source } + [mapping]
    }

    public static func removing(_ mapping: HIDKeyMapping, from list: [HIDKeyMapping]) -> [HIDKeyMapping] {
        list.filter { $0 != mapping }
    }

    /// Argument for `hidutil property --set`.
    public static func json(_ list: [HIDKeyMapping]) -> String {
        let entries = list.map { "{\"HIDKeyboardModifierMappingSrc\":\($0.source),\"HIDKeyboardModifierMappingDst\":\($0.destination)}" }
        return "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}"
    }

    /// Reads `hidutil property --get UserKeyMapping` (an old-style property list, or "(null)").
    public static func parse(_ output: String) -> [HIDKeyMapping] {
        guard let data = output.data(using: .utf8),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]]
        else { return [] }
        return list.compactMap { entry in
            guard let source = number(entry["HIDKeyboardModifierMappingSrc"]),
                  let destination = number(entry["HIDKeyboardModifierMappingDst"])
            else { return nil }
            return HIDKeyMapping(source: source, destination: destination)
        }
    }

    private static func number(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let text = value as? String { return UInt64(text) }
        return nil
    }
}

// MARK: - Shortcuts

/// A key with modifiers, stored by virtual key code so it survives keyboard layout changes.
public struct ShortcutBinding: Codable, Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)
    }

    public let keyCode: UInt32
    public let modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Carbon's modifier flags (cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096).
    public var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= 256 }
        if modifiers.contains(.shift) { flags |= 512 }
        if modifiers.contains(.option) { flags |= 2048 }
        if modifiers.contains(.control) { flags |= 4096 }
        return flags
    }

    public var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    private static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "Esc", 64: "F17", 79: "F18", 80: "F19",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
        111: "F12", 113: "F15", 118: "F4", 120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    public static func keyName(_ code: UInt32) -> String { names[code] ?? "#\(code)" }
}
