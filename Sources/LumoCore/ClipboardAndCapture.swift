import Foundation

// MARK: - Clipboard history

public struct ClipEntry: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case text, image, files }

    public let id: UUID
    public let kind: Kind
    public let text: String?
    public let files: [String]?
    public let imageFile: String?
    public let pinned: Bool
    public let date: Date
    public let sourceApp: String?

    public init(id: UUID = UUID(), kind: Kind, text: String? = nil, files: [String]? = nil, imageFile: String? = nil,
                pinned: Bool = false, date: Date = Date(), sourceApp: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.files = files
        self.imageFile = imageFile
        self.pinned = pinned
        self.date = date
        self.sourceApp = sourceApp
    }

    /// What makes two copies "the same" for de-duplication.
    public var fingerprint: String {
        switch kind {
        case .text: return "t:" + (text ?? "")
        case .files: return "f:" + (files ?? []).joined(separator: "\n")
        case .image: return "i:" + (imageFile ?? id.uuidString)
        }
    }

    public func withPinned(_ pinned: Bool) -> ClipEntry {
        ClipEntry(id: id, kind: kind, text: text, files: files, imageFile: imageFile, pinned: pinned, date: date, sourceApp: sourceApp)
    }

    public func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let haystack = (text ?? "") + " " + (files ?? []).joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(query)
    }
}

public enum ClipboardHistory {
    /// New copy goes on top; an identical older copy is replaced (keeping its pin);
    /// unpinned entries beyond `limit` fall off the end. Pinned entries are never dropped.
    public static func adding(_ entry: ClipEntry, to history: [ClipEntry], limit: Int) -> (history: [ClipEntry], dropped: [ClipEntry]) {
        let existing = history.first { $0.fingerprint == entry.fingerprint }
        let fresh = existing?.pinned == true ? entry.withPinned(true) : entry
        let rest = history.filter { $0.fingerprint != entry.fingerprint }
        var unpinnedSeen = fresh.pinned ? 0 : 1
        var kept: [ClipEntry] = [fresh]
        var dropped: [ClipEntry] = []
        for item in rest {
            if item.pinned {
                kept.append(item)
            } else if unpinnedSeen < limit {
                kept.append(item)
                unpinnedSeen += 1
            } else {
                dropped.append(item)
            }
        }
        return (kept, dropped)
    }

    /// Pinned first, then newest first.
    public static func sorted(_ history: [ClipEntry]) -> [ClipEntry] {
        history.sorted { lhs, rhs in
            lhs.pinned != rhs.pinned ? lhs.pinned : lhs.date > rhs.date
        }
    }
}

// MARK: - Snippets

public struct Snippet: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let trigger: String
    public let expansion: String

    public init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }
}

/// Watches typed characters and reports when a trigger has just been completed.
public struct SnippetMatcher: Equatable, Sendable {
    public private(set) var buffer = ""
    private let capacity: Int

    public init(capacity: Int = 64) {
        self.capacity = capacity
    }

    public mutating func type(_ characters: String) {
        buffer = String((buffer + characters).suffix(capacity))
    }

    public mutating func backspace() {
        if !buffer.isEmpty { buffer.removeLast() }
    }

    /// Navigation, clicks and app switches break the "word being typed".
    public mutating func reset() {
        buffer = ""
    }

    /// The snippet whose trigger the buffer now ends with (longest trigger wins).
    public mutating func match(in snippets: [Snippet]) -> Snippet? {
        let hit = snippets
            .filter { !$0.trigger.isEmpty && buffer.hasSuffix($0.trigger) }
            .max { $0.trigger.count < $1.trigger.count }
        if hit != nil { buffer = "" }
        return hit
    }

    /// Fills `{date}`, `{time}` and `{clipboard}`.
    public static func expand(_ template: String, date: Date, clipboard: String?, locale: Locale) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        return template
            .replacingOccurrences(of: "{date}", with: dateFormatter.string(from: date))
            .replacingOccurrences(of: "{time}", with: timeFormatter.string(from: date))
            .replacingOccurrences(of: "{clipboard}", with: clipboard ?? "")
    }
}

// MARK: - Colors

/// A sampled screen color in sRGB components (0…1).
public struct PickedColor: Equatable, Codable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    private var bytes: (Int, Int, Int) {
        (Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    public var hex: String {
        let (r, g, b) = bytes
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    public var rgb: String {
        let (r, g, b) = bytes
        return "rgb(\(r), \(g), \(b))"
    }

    public var hsl: String {
        let maxValue = max(red, green, blue), minValue = min(red, green, blue)
        let lightness = (maxValue + minValue) / 2
        let delta = maxValue - minValue
        guard delta > 0 else { return "hsl(0, 0%, \(Int((lightness * 100).rounded()))%)" }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch maxValue {
        case red: hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return "hsl(\(Int(hue.rounded())), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
    }

    public var swiftUI: String {
        String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", red, green, blue)
    }
}
