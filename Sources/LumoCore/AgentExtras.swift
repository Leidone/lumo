import Foundation

/// Token split of one model call.
public struct TokenBreakdown: Equatable, Sendable {
    public let input: Int
    public let output: Int
    public let cacheRead: Int
    public let cacheWrite: Int

    public init(input: Int, output: Int, cacheRead: Int, cacheWrite: Int) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    public var total: Int { input + output + cacheRead + cacheWrite }
}

/// What the same tokens would cost on Anthropic's API at base rates (an estimate — plans bill differently).
/// Rates per million tokens; cache writes are 1.25× input, cache reads 0.1× input unless a model has its own rate.
public enum ClaudePricing {
    private struct Rate {
        let input: Double
        let output: Double
        var cacheRead: Double?
    }

    /// Longest matching prefix wins, so "claude-opus-5-5" beats "claude-opus-5".
    private static let rates: [(String, Rate)] = [
        ("claude-fable-5-1", Rate(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-fable-5", Rate(input: 10, output: 50)),
        ("claude-mythos-5-1", Rate(input: 10, output: 50)),
        ("claude-opus-5-5", Rate(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", Rate(input: 5, output: 25)),
        ("claude-opus-4-8", Rate(input: 5, output: 25)),
        ("claude-opus-4-7", Rate(input: 5, output: 25)),
        ("claude-opus-4-6", Rate(input: 5, output: 25)),
        ("claude-opus-4-5", Rate(input: 5, output: 25)),
        ("claude-opus-4", Rate(input: 15, output: 75)),
        ("claude-sonnet-5", Rate(input: 2, output: 10)),
        ("claude-sonnet-4", Rate(input: 3, output: 15)),
        ("claude-haiku-4-5", Rate(input: 1, output: 5)),
        ("claude-3-5-haiku", Rate(input: 0.8, output: 4)),
    ]

    public static func cost(model: String, _ tokens: TokenBreakdown) -> Double? {
        let name = model.lowercased()
        guard let rate = rates.filter({ name.hasPrefix($0.0) }).max(by: { $0.0.count < $1.0.count })?.1 else { return nil }
        let perToken = 1.0 / 1_000_000
        let value = Double(tokens.input) * rate.input * perToken
            + Double(tokens.output) * rate.output * perToken
            + Double(tokens.cacheWrite) * rate.input * 1.25 * perToken
            + Double(tokens.cacheRead) * (rate.cacheRead ?? rate.input * 0.1) * perToken
        return (value * 1_000_000).rounded() / 1_000_000
    }
}

// MARK: - Plan limits

public struct LimitWindow: Equatable, Sendable {
    public let name: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(name: String, usedPercent: Double, resetsAt: Date?) {
        self.name = name
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct AgentLimits: Equatable, Sendable {
    public let windows: [LimitWindow]
    public let plan: String?
    public let creditBalance: String?

    public init(windows: [LimitWindow], plan: String?, creditBalance: String?) {
        self.windows = windows
        self.plan = plan
        self.creditBalance = creditBalance
    }
}

/// Codex writes its plan limits into every `token_count` event; the newest one wins.
public enum CodexLimitParser {
    public static func latest(lines: [Substring]) -> AgentLimits? {
        for line in lines.reversed() where line.contains("\"rate_limits\"") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let limits = payload["rate_limits"] as? [String: Any]
            else { continue }
            let windows = ["primary", "secondary"].compactMap { key -> LimitWindow? in
                guard let window = limits[key] as? [String: Any], let used = (window["used_percent"] as? NSNumber)?.doubleValue else { return nil }
                let minutes = (window["window_minutes"] as? NSNumber)?.intValue ?? 0
                let resets = (window["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                return LimitWindow(name: windowName(minutes: minutes), usedPercent: used, resetsAt: resets)
            }
            let credits = limits["credits"] as? [String: Any]
            return AgentLimits(windows: windows, plan: limits["plan_type"] as? String,
                               creditBalance: (credits?["has_credits"] as? Bool) == true ? credits?["balance"] as? String : nil)
        }
        return nil
    }

    static func windowName(minutes: Int) -> String {
        switch minutes {
        case 0: return "—"
        case ..<1440: return "\(minutes / 60)h"
        default: return "\(minutes / 1440)d"
        }
    }
}

/// Claude's plan-usage response (`five_hour`, `seven_day`, `seven_day_opus` with utilization and reset time).
public enum ClaudeUsageParser {
    public static func parse(_ data: Data) -> [LimitWindow] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let names = [("five_hour", "5h"), ("seven_day", "7d"), ("seven_day_opus", "7d Opus"), ("seven_day_sonnet", "7d Sonnet")]
        return names.compactMap { key, name in
            guard let window = object[key] as? [String: Any], let used = (window["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return LimitWindow(name: name, usedPercent: used, resetsAt: AgentLogParser.date(window["resets_at"]))
        }
    }
}

// MARK: - Other agents

extension AgentLogParser {
    /// OpenCode stores one JSON file per message; assistant messages carry tokens, model and cost.
    public static func openCode(message data: Data) -> AgentEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["role"] as? String == "assistant",
              let tokens = object["tokens"] as? [String: Any],
              let created = ((object["time"] as? [String: Any])?["created"] as? NSNumber)?.doubleValue
        else { return nil }
        let cache = tokens["cache"] as? [String: Any]
        let breakdown = TokenBreakdown(input: tokens["input"] as? Int ?? 0,
                                       output: (tokens["output"] as? Int ?? 0) + (tokens["reasoning"] as? Int ?? 0),
                                       cacheRead: cache?["read"] as? Int ?? 0, cacheWrite: cache?["write"] as? Int ?? 0)
        guard breakdown.total > 0 else { return nil }
        let cwd = (object["path"] as? [String: Any])?["cwd"] as? String
        return AgentEvent(source: .opencode, date: Date(timeIntervalSince1970: created / 1000),
                          model: object["modelID"] as? String ?? "opencode", tokens: breakdown.total, breakdown: breakdown,
                          project: cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
                          reportedCost: (object["cost"] as? NSNumber)?.doubleValue)
    }

    /// GitHub Copilot CLI session logs: any line with a usage object (input/output tokens) counts.
    public static func copilot(lines: [Substring]) -> [AgentEvent] {
        lines.compactMap { line in
            guard line.contains("tokens"),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let usage = (object["usage"] ?? (object["data"] as? [String: Any])?["usage"]) as? [String: Any]
            else { return nil }
            let input = usage["input_tokens"] as? Int ?? usage["prompt_tokens"] as? Int ?? usage["inputTokens"] as? Int ?? 0
            let output = usage["output_tokens"] as? Int ?? usage["completion_tokens"] as? Int ?? usage["outputTokens"] as? Int ?? 0
            guard input + output > 0 else { return nil }
            let when = date(object["timestamp"]) ?? Date()
            let model = object["model"] as? String ?? (object["data"] as? [String: Any])?["model"] as? String ?? "copilot"
            return AgentEvent(source: .copilot, date: when, model: model, tokens: input + output,
                              breakdown: TokenBreakdown(input: input, output: output, cacheRead: 0, cacheWrite: 0))
        }
    }
}
