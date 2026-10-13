import Foundation

// MARK: - Now playing

/// A snapshot from the system Now Playing service. Elapsed time is reported at `timestamp`
/// and advances with `rate` between updates.
public struct NowPlayingState: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double
    public let elapsed: Double
    public let timestamp: Date
    public let rate: Double

    public init(title: String, artist: String, album: String, duration: Double, elapsed: Double, timestamp: Date, rate: Double) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.rate = rate
    }

    public var isPlaying: Bool { rate > 0 }

    public func elapsed(at date: Date) -> Double {
        let value = elapsed + max(date.timeIntervalSince(timestamp), 0) * rate
        return duration > 0 ? min(max(value, 0), duration) : max(value, 0)
    }

    public func progress(at date: Date) -> Double {
        duration > 0 ? elapsed(at: date) / duration : 0
    }
}

// MARK: - Lyrics

public struct LyricLine: Equatable, Sendable {
    public let time: Double
    public let text: String

    public init(time: Double, text: String) {
        self.time = time
        self.text = text
    }
}

/// Parses LRC synced lyrics ("[mm:ss.xx] text"), including several stamps per line and `[offset:ms]`.
public enum LyricsParser {
    private static let stamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#)
    private static let offsetTag = try! NSRegularExpression(pattern: #"^\[offset:\s*([+-]?\d+)\]"#, options: [.caseInsensitive])

    public static func parse(_ text: String) -> [LyricLine] {
        var offset = 0.0
        var lines: [LyricLine] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let range = NSRange(line.startIndex..., in: line)
            if let match = offsetTag.firstMatch(in: line, range: range), let value = Double(substring(line, match.range(at: 1))) {
                offset = value / 1000
                continue
            }
            let matches = stamp.matches(in: line, range: range)
            guard let last = matches.last, let lastRange = Range(last.range, in: line) else { continue }
            let lyric = String(line[lastRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutes = Double(substring(line, match.range(at: 1))),
                      let seconds = Double(substring(line, match.range(at: 2)).replacingOccurrences(of: ":", with: "."))
                else { continue }
                lines.append(LyricLine(time: max(minutes * 60 + seconds - offset, 0), text: lyric))
            }
        }
        return lines.enumerated()
            .sorted { $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time }
            .map(\.element)
    }

    /// Index of the line being sung at `time`, or nil before the first one.
    public static func index(at time: Double, in lines: [LyricLine]) -> Int? {
        var low = 0
        var high = lines.count - 1
        var found: Int?
        while low <= high {
            let middle = (low + high) / 2
            if lines[middle].time <= time {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return found
    }

    private static func substring(_ text: String, _ range: NSRange) -> String {
        Range(range, in: text).map { String(text[$0]) } ?? ""
    }
}

// MARK: - Activities

/// What the collapsed island can show beside the notch, most urgent first.
public enum IslandActivity: Int, CaseIterable, Comparable, Sendable {
    case recording, timer, notification, download, event, media, agent, awake

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public static func primary(of activities: Set<IslandActivity>) -> IslandActivity? { activities.min() }
}

// MARK: - Downloads

/// Browsers write to a temporary name and rename on completion.
public enum DownloadNames {
    public static let partialExtensions = ["crdownload", "download", "part", "partial", "opdownload"]

    public static func finalName(of fileName: String) -> String? {
        let url = URL(fileURLWithPath: fileName)
        guard partialExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty || base == "." ? nil : base
    }
}

// MARK: - Notifications

/// The visible text of one Notification Center record (its "req" dictionary).
public struct NotificationPayload: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let body: String

    public init(title: String, subtitle: String, body: String) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
    }

    public init?(plist: [String: Any]) {
        guard let request = plist["req"] as? [String: Any] else { return nil }
        let title = request["titl"] as? String ?? ""
        let subtitle = request["subt"] as? String ?? ""
        let body = request["body"] as? String ?? ""
        guard !(title.isEmpty && subtitle.isEmpty && body.isEmpty) else { return nil }
        self.init(title: title, subtitle: subtitle, body: body)
    }
}
