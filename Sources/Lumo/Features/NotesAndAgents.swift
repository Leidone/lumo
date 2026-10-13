import Security
import AppKit
import LumoCore

/// Autosaved scratchpad notes with Markdown preview.
@MainActor
final class NotesStore: ObservableObject {
    struct Note: Identifiable, Codable, Equatable {
        let id: UUID
        let body: String
        let updated: Date

        var title: String {
            let first = body.split(separator: "\n").first.map(String.init)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces)) ?? ""
            return first.isEmpty ? "—" : String(first.prefix(40))
        }
    }

    @Published private(set) var notes: [Note] = []
    @Published var selectedID: UUID?

    private let file: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumo", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = folder.appendingPathComponent("notes.json")
        if let data = try? Data(contentsOf: file) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            notes = (try? decoder.decode([Note].self, from: data)) ?? []
        }
        if notes.isEmpty { notes = [Note(id: UUID(), body: "", updated: Date())] }
        selectedID = notes.first?.id
    }

    var selected: Note? { notes.first { $0.id == selectedID } }

    func add() {
        let note = Note(id: UUID(), body: "", updated: Date())
        notes = [note] + notes
        selectedID = note.id
        scheduleSave()
    }

    func update(_ id: UUID, body: String) {
        notes = notes.map { $0.id == id ? Note(id: id, body: body, updated: Date()) : $0 }
        scheduleSave()
    }

    func delete(_ id: UUID) {
        notes = notes.filter { $0.id != id }
        if notes.isEmpty { notes = [Note(id: UUID(), body: "", updated: Date())] }
        if selectedID == id { selectedID = notes.first?.id }
        scheduleSave()
    }

    func exportToDesktop(_ note: Note) -> URL? {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let safe = note.title.replacingOccurrences(of: "/", with: "-")
        let url = desktop.appendingPathComponent("\(safe).md")
        guard (try? note.body.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return url
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = notes
        let file = file
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) { try? data.write(to: file, options: .atomic) }
        }
    }
}

/// Local AI coding agents (Claude Code, Codex, OpenCode, Copilot): tokens, plan limits, API value,
/// projects and a heads-up when a long task finishes. Reads only numbers and times from their logs.
@MainActor
final class AgentUsageStore: ObservableObject {
    enum Agent: String, CaseIterable, Identifiable {
        case claude, codex, opencode, copilot

        var id: Self { self }
        var title: String {
            switch self {
            case .claude: return "Claude Code"
            case .codex: return "Codex"
            case .opencode: return "OpenCode"
            case .copilot: return "GitHub Copilot"
            }
        }
    }

    struct Summary: Equatable {
        var block: UsageBlock?
        var today = 0
        var isInstalled = false
        var limits: AgentLimits?
        /// Estimated API value of today's tokens, in dollars.
        var valueToday: Double?
        var projects: [(name: String, tokens: Int)] = []
        var isWorking = false

        static func == (lhs: Summary, rhs: Summary) -> Bool {
            lhs.block == rhs.block && lhs.today == rhs.today && lhs.isInstalled == rhs.isInstalled && lhs.limits == rhs.limits
                && lhs.valueToday == rhs.valueToday && lhs.isWorking == rhs.isWorking && lhs.projects.map(\.name) == rhs.projects.map(\.name)
        }
    }

    private enum Key {
        static let claudeLimits = "agents.claudeLimits"
        static let finishNotices = "agents.finishNotices"
    }

    nonisolated private static let workingWindow: TimeInterval = 30
    private static let longTask: TimeInterval = 120
    private static let quietAfter: TimeInterval = 45

    @Published private(set) var summaries: [Agent: Summary] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var updated: Date?
    @Published private(set) var claudeLimitError: String?
    @Published var claudeLimitsEnabled: Bool {
        didSet { UserDefaults.standard.set(claudeLimitsEnabled, forKey: Key.claudeLimits); refresh() }
    }
    @Published var finishNotices: Bool {
        didSet { UserDefaults.standard.set(finishNotices, forKey: Key.finishNotices); configureWatcher() }
    }

    var onTaskFinished: ((Agent, String) -> Void)?
    private var watchTimer: Timer?
    private var activity: [String: (since: Date, last: Date)] = [:]

    var claude: Summary { summaries[.claude] ?? Summary() }
    var codex: Summary { summaries[.codex] ?? Summary() }

    init() {
        claudeLimitsEnabled = UserDefaults.standard.bool(forKey: Key.claudeLimits)
        finishNotices = UserDefaults.standard.bool(forKey: Key.finishNotices)
        configureWatcher()
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        let wantsClaudeLimits = claudeLimitsEnabled
        Task {
            var next = await Task.detached(priority: .utility) { Self.readAll(now: Date()) }.value
            if wantsClaudeLimits {
                switch await ClaudePlanUsage.fetch() {
                case .success(let windows):
                    next[.claude]?.limits = AgentLimits(windows: windows, plan: nil, creditBalance: nil)
                    claudeLimitError = nil
                case .failure(let error):
                    claudeLimitError = error.message
                }
            }
            summaries = next
            updated = Date()
            isLoading = false
        }
    }

    // MARK: Reading logs

    nonisolated private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    nonisolated private static func roots(_ agent: Agent) -> URL {
        switch agent {
        case .claude: return home.appendingPathComponent(".claude/projects")
        case .codex: return home.appendingPathComponent(".codex/sessions")
        case .opencode: return home.appendingPathComponent(".local/share/opencode/storage/message")
        case .copilot: return home.appendingPathComponent(".copilot")
        }
    }

    nonisolated private static func readAll(now: Date) -> [Agent: Summary] {
        var result: [Agent: Summary] = [:]
        for agent in Agent.allCases {
            result[agent] = summary(agent, now: now)
        }
        return result
    }

    nonisolated private static func recentFiles(_ root: URL, extension ext: String, since: Date) -> [(url: URL, modified: Date)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        return (FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == ext }
            .compactMap { url in
                let modified = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                return modified > since ? (url, modified) : nil
            }
    }

    nonisolated private static func summary(_ agent: Agent, now: Date) -> Summary {
        let root = roots(agent)
        guard FileManager.default.fileExists(atPath: root.path) else { return Summary() }
        let since = now.addingTimeInterval(-24 * 3600)
        let files = recentFiles(root, extension: agent == .opencode ? "json" : "jsonl", since: since)
        var events: [AgentEvent] = []
        var limits: AgentLimits?
        let newest = files.max { $0.modified < $1.modified }
        for file in files {
            guard let data = try? Data(contentsOf: file.url) else { continue }
            switch agent {
            case .opencode:
                AgentLogParser.openCode(message: data).map { events.append($0) }
            default:
                let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
                switch agent {
                case .claude: events += AgentLogParser.claude(lines: lines)
                case .codex:
                    events += AgentLogParser.codex(lines: lines)
                    if file.url == newest?.url { limits = CodexLimitParser.latest(lines: lines) }
                default: events += AgentLogParser.copilot(lines: lines)
                }
            }
        }
        events = events.filter { $0.date > since }
        let dayStart = Calendar.current.startOfDay(for: now)
        let todayEvents = events.filter { $0.date >= dayStart }
        let values = todayEvents.compactMap { event -> Double? in
            event.reportedCost ?? event.breakdown.flatMap { ClaudePricing.cost(model: event.model, $0) }
        }
        let projects = Dictionary(grouping: todayEvents.filter { $0.project != nil }, by: { $0.project ?? "" })
            .map { (name: $0.key, tokens: $0.value.reduce(0) { $0 + $1.tokens }) }
            .sorted { $0.tokens > $1.tokens }
        return Summary(block: UsageBlocks.current(events, now: now), today: todayEvents.reduce(0) { $0 + $1.tokens }, isInstalled: true,
                       limits: limits, valueToday: values.isEmpty ? nil : values.reduce(0, +),
                       projects: Array(projects.prefix(4)),
                       isWorking: newest.map { now.timeIntervalSince($0.modified) < workingWindow } ?? false)
    }

    // MARK: Finished-task notices

    /// Every 20 s: a session log that was written for 2+ minutes and then went quiet means the task ended.
    private func configureWatcher() {
        watchTimer?.invalidate()
        watchTimer = nil
        activity = [:]
        guard finishNotices else { return }
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.checkActivity() } }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
    }

    private func checkActivity() {
        Task {
            let now = Date()
            let files = await Task.detached(priority: .utility) { () -> [(Agent, URL, Date)] in
                [Agent.claude, .codex].flatMap { agent in
                    Self.recentFiles(Self.roots(agent), extension: "jsonl", since: now.addingTimeInterval(-600)).map { (agent, $0.url, $0.modified) }
                }
            }.value
            for (agent, url, modified) in files {
                let key = url.path
                if now.timeIntervalSince(modified) < Self.workingWindow {
                    let since = activity[key]?.since ?? modified
                    activity[key] = (since, modified)
                } else if let state = activity[key], now.timeIntervalSince(state.last) > Self.quietAfter {
                    activity[key] = nil
                    if state.last.timeIntervalSince(state.since) >= Self.longTask {
                        onTaskFinished?(agent, Self.projectName(url, agent: agent))
                    }
                }
            }
        }
    }

    nonisolated private static func projectName(_ url: URL, agent: Agent) -> String {
        // Claude keeps one folder per project, named after its path with dashes.
        guard agent == .claude else { return url.deletingPathExtension().lastPathComponent }
        return url.deletingLastPathComponent().lastPathComponent.components(separatedBy: "-").last ?? ""
    }
}

/// Claude plan usage (the numbers Claude shows under Settings → Usage), opt-in. Uses the sign-in
/// Claude Code keeps in the Keychain; the token is read for one request and never stored by Lumo.
enum ClaudePlanUsage {
    struct Failure: Error {
        let message: String
    }

    static func fetch() async -> Result<[LimitWindow], Failure> {
        guard let token = accessToken() else {
            return .failure(Failure(message: "Claude Code sign-in not found in the Keychain"))
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .failure(Failure(message: "No connection"))
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            return .failure(Failure(message: "Claude answered \((response as? HTTPURLResponse)?.statusCode ?? 0)"))
        }
        let windows = ClaudeUsageParser.parse(data)
        return windows.isEmpty ? .failure(Failure(message: "Unexpected answer")) : .success(windows)
    }

    private static func accessToken() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Claude Code-credentials",
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any]
        else { return nil }
        return oauth["accessToken"] as? String
    }
}
