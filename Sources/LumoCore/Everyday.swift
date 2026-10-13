import Foundation

// MARK: - Calculator

/// A small, crash-proof arithmetic parser for the Command Bar: + − × ÷ ^, parentheses, unary minus
/// and postfix % ("200*15%" = 30). Anything else returns nil instead of raising like NSExpression.
public enum Calculator {
    public static func evaluate(_ input: String) -> Double? {
        let normalized = input
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .filter { !$0.isWhitespace }
        guard !normalized.isEmpty else { return nil }
        var parser = Parser(characters: Array(normalized))
        guard let value = parser.expression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    /// True only for real arithmetic (digits plus at least one operator), so plain numbers aren't "calculated".
    public static func looksLikeMath(_ input: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "0123456789.,+-*/^%()×÷− ")
        return input.rangeOfCharacter(from: .decimalDigits) != nil
            && input.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^%×÷−")) != nil
            && input.unicodeScalars.allSatisfy(allowed.contains)
    }

    private struct Parser {
        let characters: [Character]
        var index = 0
        var isAtEnd: Bool { index >= characters.count }

        private var current: Character? { isAtEnd ? nil : characters[index] }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while let op = current, op == "+" || op == "-" {
                index += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func term() -> Double? {
            guard var value = power() else { return nil }
            while let op = current, op == "*" || op == "/" {
                index += 1
                guard let rhs = power() else { return nil }
                if op == "/" && rhs == 0 { return nil }
                value = op == "*" ? value * rhs : value / rhs
            }
            return value
        }

        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            guard current == "^" else { return base }
            index += 1
            guard let exponent = power() else { return nil }
            return pow(base, exponent)
        }

        mutating func unary() -> Double? {
            if current == "-" {
                index += 1
                return unary().map { -$0 }
            }
            if current == "+" {
                index += 1
                return unary()
            }
            return primary()
        }

        mutating func primary() -> Double? {
            var value: Double
            if current == "(" {
                index += 1
                guard let inner = expression(), current == ")" else { return nil }
                index += 1
                value = inner
            } else {
                let start = index
                while let character = current, character.isNumber || character == "." { index += 1 }
                guard index > start, let number = Double(String(characters[start..<index])) else { return nil }
                value = number
            }
            if current == "%" {
                index += 1
                value /= 100
            }
            return value
        }
    }
}

// MARK: - Units

public enum UnitConverter {
    private static let units: [String: Dimension] = [
        "km": UnitLength.kilometers, "км": UnitLength.kilometers, "m": UnitLength.meters, "м": UnitLength.meters,
        "cm": UnitLength.centimeters, "см": UnitLength.centimeters, "mm": UnitLength.millimeters, "мм": UnitLength.millimeters,
        "mi": UnitLength.miles, "ft": UnitLength.feet, "in": UnitLength.inches, "yd": UnitLength.yards,
        "kg": UnitMass.kilograms, "кг": UnitMass.kilograms, "g": UnitMass.grams, "г": UnitMass.grams,
        "lb": UnitMass.pounds, "lbs": UnitMass.pounds, "oz": UnitMass.ounces,
        "c": UnitTemperature.celsius, "°c": UnitTemperature.celsius, "f": UnitTemperature.fahrenheit,
        "°f": UnitTemperature.fahrenheit, "k": UnitTemperature.kelvin,
        "l": UnitVolume.liters, "л": UnitVolume.liters, "ml": UnitVolume.milliliters, "мл": UnitVolume.milliliters,
        "gal": UnitVolume.gallons, "kb": UnitInformationStorage.kilobytes, "mb": UnitInformationStorage.megabytes,
        "gb": UnitInformationStorage.gigabytes, "tb": UnitInformationStorage.terabytes,
        "кб": UnitInformationStorage.kilobytes, "мб": UnitInformationStorage.megabytes, "гб": UnitInformationStorage.gigabytes,
        "km/h": UnitSpeed.kilometersPerHour, "км/ч": UnitSpeed.kilometersPerHour, "mph": UnitSpeed.milesPerHour,
        "m/s": UnitSpeed.metersPerSecond,
    ]

    /// "10 km to mi", "32 f in c", "5 гб в мб". Returns nil for anything that isn't a same-kind conversion.
    public static func convert(_ query: String) -> (value: Double, unit: String)? {
        let pattern = #"^\s*(-?[\d.,]+)\s*([^\s\d]+)\s+(?:to|in|в|->|→)\s+([^\s\d]+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let valueRange = Range(match.range(at: 1), in: query),
              let fromRange = Range(match.range(at: 2), in: query),
              let toRange = Range(match.range(at: 3), in: query),
              let value = Double(query[valueRange].replacingOccurrences(of: ",", with: ".")),
              let from = units[query[fromRange].lowercased()],
              let to = units[query[toRange].lowercased()],
              type(of: from) == type(of: to)
        else { return nil }
        let converted = Measurement(value: value, unit: from).converted(to: to).value
        return (converted, String(query[toRange]))
    }
}

// MARK: - Emoji

public enum EmojiIndex {
    public struct Item: Equatable, Sendable {
        public let emoji: String
        public let name: String
    }

    public static let all: [Item] = {
        let ranges: [ClosedRange<UInt32>] = [0x1F300...0x1FAFF, 0x2600...0x27BF]
        return ranges.flatMap { $0 }.compactMap { value -> Item? in
            guard let scalar = Unicode.Scalar(value), scalar.properties.isEmojiPresentation,
                  let name = scalar.properties.name?.lowercased()
            else { return nil }
            return Item(emoji: String(scalar), name: name)
        }
    }()

    public static func search(_ query: String, limit: Int = 12) -> [Item] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return Array(all.filter { item in words.allSatisfy { item.name.contains($0) } }.prefix(limit))
    }
}

// MARK: - AI agent usage

public struct AgentEvent: Equatable, Sendable {
    public enum Source: String, Sendable { case claude, codex, opencode, copilot }

    public let source: Source
    public let date: Date
    public let model: String
    public let tokens: Int
    /// Input/output/cache split, when the log reports it (needed for an API-value estimate).
    public let breakdown: TokenBreakdown?
    /// Folder name of the project the agent worked in.
    public let project: String?
    /// Cost the tool itself logged (OpenCode), in dollars.
    public let reportedCost: Double?

    public init(source: Source, date: Date, model: String, tokens: Int, breakdown: TokenBreakdown? = nil,
                project: String? = nil, reportedCost: Double? = nil) {
        self.source = source
        self.date = date
        self.model = model
        self.tokens = tokens
        self.breakdown = breakdown
        self.project = project
        self.reportedCost = reportedCost
    }
}

/// Reads local agent logs. Only token counts, models and times are used — never message content.
public enum AgentLogParser {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return isoFormatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// Claude Code: assistant lines carry `message.model` and `message.usage`.
    public static func claude(lines: [Substring]) -> [AgentEvent] {
        var seen = Set<String>()
        return lines.compactMap { line in
            guard line.contains("\"usage\""),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let when = date(object["timestamp"])
            else { return nil }
            // Streaming writes the same API message several times; count it once.
            if let id = message["id"] as? String, !seen.insert(id).inserted { return nil }
            let breakdown = TokenBreakdown(input: usage["input_tokens"] as? Int ?? 0, output: usage["output_tokens"] as? Int ?? 0,
                                           cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                                           cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0)
            let project = (object["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
            return AgentEvent(source: .claude, date: when, model: message["model"] as? String ?? "claude", tokens: breakdown.total,
                              breakdown: breakdown, project: project)
        }
    }

    /// Codex: `turn_context` sets the model; each `token_count` reports `last_token_usage`.
    public static func codex(lines: [Substring]) -> [AgentEvent] {
        var model = "codex"
        var events: [AgentEvent] = []
        for line in lines where line.contains("turn_context") || line.contains("token_count") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let payload = object["payload"] as? [String: Any]
            else { continue }
            if object["type"] as? String == "turn_context", let name = payload["model"] as? String {
                model = name
            } else if payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let usage = info["last_token_usage"] as? [String: Any],
                      let tokens = usage["total_tokens"] as? Int, tokens > 0,
                      let when = date(object["timestamp"]) {
                events.append(AgentEvent(source: .codex, date: when, model: model, tokens: tokens))
            }
        }
        return events
    }
}

/// Plans meter usage in rolling 5-hour windows that start on the hour of the first request.
public struct UsageBlock: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let tokens: Int
    public let requests: Int
    public let byModel: [String: Int]
}

public enum UsageBlocks {
    public static let length: TimeInterval = 5 * 3600

    public static func blocks(_ events: [AgentEvent]) -> [UsageBlock] {
        var result: [UsageBlock] = []
        var current: [AgentEvent] = []
        var start: Date?
        for event in events.sorted(by: { $0.date < $1.date }) {
            if let blockStart = start, event.date < blockStart.addingTimeInterval(length) {
                current.append(event)
                continue
            }
            if let blockStart = start { result.append(block(blockStart, current)) }
            start = floorToHour(event.date)
            current = [event]
        }
        if let blockStart = start { result.append(block(blockStart, current)) }
        return result
    }

    public static func current(_ events: [AgentEvent], now: Date) -> UsageBlock? {
        blocks(events).last.flatMap { now < $0.end ? $0 : nil }
    }

    private static func block(_ start: Date, _ events: [AgentEvent]) -> UsageBlock {
        let byModel = Dictionary(grouping: events, by: \.model).mapValues { $0.reduce(0) { $0 + $1.tokens } }
        return UsageBlock(start: start, end: start.addingTimeInterval(length), tokens: events.reduce(0) { $0 + $1.tokens },
                          requests: events.count, byModel: byModel)
    }

    private static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }
}
