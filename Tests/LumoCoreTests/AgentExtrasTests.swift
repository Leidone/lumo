import Foundation
import Testing
@testable import LumoCore

@Suite("Agent extras")
struct AgentExtrasTests {
    @Test("Claude lines keep the token breakdown and the project folder")
    func claudeBreakdown() throws {
        let line = #"{"timestamp":"2026-10-13T10:00:00.000Z","cwd":"/Users/me/Lumo","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1000,"output_tokens":200,"cache_read_input_tokens":5000,"cache_creation_input_tokens":300}}}"#
        let event = try #require(AgentLogParser.claude(lines: [Substring(line)]).first)
        #expect(event.tokens == 6500)
        #expect(event.breakdown == TokenBreakdown(input: 1000, output: 200, cacheRead: 5000, cacheWrite: 300))
        #expect(event.project == "Lumo")
    }

    @Test("API value uses base rates with cache multipliers and the per-model cache read rates")
    func pricing() throws {
        let breakdown = TokenBreakdown(input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000, cacheWrite: 1_000_000)
        // Sonnet 5: 2 + 10 + 0.2 (read) + 2.5 (write)
        #expect(try #require(ClaudePricing.cost(model: "claude-sonnet-5", breakdown)) == 14.7)
        // Opus 5.5 has an explicit $0.20 cache read: 4 + 20 + 0.2 + 5
        #expect(try #require(ClaudePricing.cost(model: "claude-opus-5-5", breakdown)) == 29.2)
        #expect(ClaudePricing.cost(model: "gpt-5-codex", breakdown) == nil)
    }

    @Test("the newest Codex rate-limit snapshot is read from token_count events")
    func codexLimits() throws {
        let lines = [
            #"{"timestamp":"2026-10-13T09:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":5.0,"window_minutes":300,"resets_at":1791900000}}}}"#,
            #"{"timestamp":"2026-10-13T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":15.0,"window_minutes":300,"resets_at":1791905670},"secondary":{"used_percent":2.0,"window_minutes":10080,"resets_at":1792492470},"credits":{"has_credits":false,"balance":"0"},"plan_type":"plus"}}}"#,
        ].map { Substring($0) }
        let limits = try #require(CodexLimitParser.latest(lines: lines))
        #expect(limits.windows == [LimitWindow(name: "5h", usedPercent: 15, resetsAt: Date(timeIntervalSince1970: 1_791_905_670)),
                                   LimitWindow(name: "7d", usedPercent: 2, resetsAt: Date(timeIntervalSince1970: 1_792_492_470))])
        #expect(limits.plan == "plus")
    }

    @Test("Claude plan usage response becomes limit windows")
    func claudeLimits() throws {
        let json = #"{"five_hour":{"utilization":42.5,"resets_at":"2026-10-13T15:00:00+00:00"},"seven_day":{"utilization":10,"resets_at":"2026-10-18T00:00:00+00:00"},"seven_day_opus":null}"#
        let windows = ClaudeUsageParser.parse(Data(json.utf8))
        #expect(windows.map(\.name) == ["5h", "7d"])
        #expect(windows.first?.usedPercent == 42.5)
    }

    @Test("OpenCode assistant messages become events with their own cost")
    func openCode() throws {
        let json = #"{"role":"assistant","modelID":"claude-sonnet-5","time":{"created":1791883824000},"tokens":{"input":100,"output":50,"reasoning":0,"cache":{"read":1000,"write":0}},"cost":0.0123,"path":{"cwd":"/Users/me/app"}}"#
        let event = try #require(AgentLogParser.openCode(message: Data(json.utf8)))
        #expect(event.source == .opencode)
        #expect(event.tokens == 1150)
        #expect(event.reportedCost == 0.0123)
        #expect(event.project == "app")
    }
}
