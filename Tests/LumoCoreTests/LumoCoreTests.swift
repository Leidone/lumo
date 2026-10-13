import Foundation
import Testing
@testable import LumoCore

private let me: UInt32 = 501

private func record(_ pid: Int32, _ path: String, cpu: Double = 0, mb: UInt64 = 10,
                    uid: UInt32 = me, tty: String? = nil) -> ProcessRecord {
    ProcessRecord(pid: pid, uid: uid, cpuPercent: cpu, residentBytes: mb * 1_048_576, tty: tty, path: path)
}

private let chrome = RunningAppInfo(pid: 100, bundlePath: "/Applications/Google Chrome.app",
                                    bundleID: "com.google.Chrome", name: "Google Chrome", isFrontmost: false)
private let editor = RunningAppInfo(pid: 200, bundlePath: "/Applications/Editor.app",
                                    bundleID: "com.example.editor", name: "Editor", isFrontmost: true)

private func context(exceptions: Set<String> = []) -> ClassificationContext {
    ClassificationContext(currentUID: me, ownPID: 999, apps: [chrome, editor], exceptions: exceptions)
}

@Suite("PSParser")
struct PSParserTests {
    @Test("parses fields and keeps spaces in paths")
    func parsesPathWithSpaces() {
        let output = """
          61884   501  18.9  90800 ??       /Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper
            1     0   0.0  20064 ??       /sbin/launchd
        """
        let records = PSParser.parse(output)
        #expect(records.count == 2)
        #expect(records[0] == ProcessRecord(
            pid: 61884, uid: 501, cpuPercent: 18.9, residentBytes: 90800 * 1024, tty: nil,
            path: "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper"))
        #expect(records[0].name == "Claude Helper")
    }

    @Test("reads tty and comma decimal separator")
    func parsesTTYAndComma() {
        let records = PSParser.parse("  42  501  3,5  100 ttys001  -zsh")
        #expect(records.first?.tty == "ttys001")
        #expect(records.first?.cpuPercent == 3.5)
    }

    @Test("skips malformed lines")
    func skipsGarbage() {
        #expect(PSParser.parse("garbage\n\n  1 2 x 4 ?? /a").isEmpty)
    }
}

@Suite("ProcessClassifier")
struct ClassifierTests {
    @Test("protects other users, itself, system and terminal processes")
    func exclusions() {
        let ctx = context()
        #expect(ProcessClassifier.classify(record(1, "/Applications/X.app/X", uid: 0), in: ctx) == .excluded(.otherUser))
        #expect(ProcessClassifier.classify(record(999, "/Applications/Lumo.app/Lumo"), in: ctx) == .excluded(.ownProcess))
        #expect(ProcessClassifier.classify(record(3, "/usr/libexec/logd"), in: ctx) == .excluded(.systemPath))
        #expect(ProcessClassifier.classify(record(4, "-zsh"), in: ctx) == .excluded(.relativePath))
        #expect(ProcessClassifier.classify(record(5, "/opt/homebrew/bin/node", tty: "ttys001"), in: ctx)
            == .excluded(.terminalSession))
        #expect(ProcessClassifier.classify(record(6, "/Applications/Old/Finder"), in: ctx) == .excluded(.systemName))
    }

    @Test("recognises apps, helpers and background processes")
    func kinds() {
        let ctx = context()
        #expect(ProcessClassifier.classify(record(100, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"), in: ctx)
            == .app(chrome))
        #expect(ProcessClassifier.classify(record(101, "/Applications/Google Chrome.app/Contents/Frameworks/Helper"), in: ctx)
            == .helper(owner: chrome))
        #expect(ProcessClassifier.classify(record(300, "/Applications/Google Chrome.app.backup/x"), in: ctx) == .background)
    }
}

@Suite("OptimizationPolicy")
struct PolicyTests {
    @Test("interpolates limits and clamps intensity")
    func limits() {
        let gentle = OptimizationPolicy(intensity: -1)
        let maximum = OptimizationPolicy(intensity: 5)
        #expect(gentle.cpuLimitPercent == 60)
        #expect(maximum.cpuLimitPercent == 10)
        #expect(gentle.appMemoryLimitBytes == 4096 * 1_048_576)
        #expect(maximum.backgroundMemoryLimitBytes == 256 * 1_048_576)
        #expect(gentle.level == .gentle)
        #expect(OptimizationPolicy(intensity: 0.5).level == .balanced)
        #expect(maximum.level == .maximum && maximum.forceKillStubborn)
    }
}

@Suite("OptimizationPlanner")
struct PlannerTests {
    private let records = [
        record(100, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", cpu: 10, mb: 500),
        record(101, "/Applications/Google Chrome.app/Contents/Frameworks/Renderer", cpu: 30, mb: 700),
        record(200, "/Applications/Editor.app/Contents/MacOS/Editor", cpu: 90, mb: 3000),
        record(300, "/Users/me/Library/Updater/Updater", cpu: 45, mb: 50),
        record(301, "/Applications/Quiet.app/quietd", cpu: 1, mb: 20),
        record(1, "/usr/libexec/logd", cpu: 99, mb: 9000),
    ]

    @Test("folds helpers into the owning app and drops system processes")
    func grouping() {
        let groups = OptimizationPlanner.groups(from: records, context: context())
        let chromeGroup = groups.first { $0.id == "app:/Applications/Google Chrome.app" }
        #expect(chromeGroup?.cpuPercent == 40)
        #expect(chromeGroup?.residentBytes == 1200 * 1_048_576)
        #expect(Set(chromeGroup?.pids ?? []) == [100, 101])
        #expect(!groups.contains { $0.pids.contains(1) })
        #expect(groups.first?.displayName == "Editor")
    }

    @Test("plans only over-limit, non-frontmost, non-excepted groups")
    func planning() {
        let policy = OptimizationPolicy(intensity: 0.5)  // 35% CPU
        let groups = OptimizationPlanner.groups(from: records, context: context())

        let withApps = OptimizationPlanner.plan(groups, policy: policy, closeApps: true)
        #expect(withApps.map(\.id).sorted() == ["app:/Applications/Google Chrome.app", "pid:300"])
        #expect(withApps.first { $0.id == "pid:300" }?.action == .terminate)

        let backgroundOnly = OptimizationPlanner.plan(groups, policy: policy, closeApps: false)
        #expect(backgroundOnly.map(\.id) == ["pid:300"])

        let excepted = OptimizationPlanner.groups(from: records, context: context(exceptions: ["Updater"]))
        #expect(OptimizationPlanner.plan(excepted, policy: policy, closeApps: false).isEmpty)
    }
}

@Suite("Monitoring")
struct MonitoringTests {
    @Test("history keeps only the newest samples and never mutates the original")
    func history() {
        let empty = MetricHistory(capacity: 3)
        let full = [0.1, 0.2, 0.3, 0.4].reduce(empty) { $0.appending($1) }
        #expect(empty.values.isEmpty)
        #expect(full.values == [0.2, 0.3, 0.4])
        #expect(full.latest == 0.4)
        #expect(full.peak == 0.4)
        #expect(MetricHistory(capacity: 0).capacity == 1)
    }

    @Test("network delta computes per-second rates and ignores counter resets")
    func networkDelta() {
        let a = NetworkCounters(received: 1_000, sent: 500, timestamp: 10)
        let b = NetworkCounters(received: 5_000, sent: 1_500, timestamp: 12)
        let delta = NetworkDelta.between(a, b)
        #expect(delta.receivedBytes == 4_000)
        #expect(delta.downBytesPerSecond == 2_000)
        #expect(delta.upBytesPerSecond == 500)

        let reset = NetworkCounters(received: 10, sent: 10, timestamp: 14)
        #expect(NetworkDelta.between(b, reset).receivedBytes == 0)
        #expect(NetworkDelta.between(b, b) == .zero)
    }

    @Test("battery health only trusts mAh capacities")
    func batteryHealth() {
        let intel = BatteryReading(charge: 0.5, isCharging: false, isPluggedIn: false, minutesRemaining: -1,
                                   cycleCount: 300, maxCapacity: 4_500, designCapacity: 5_000, watts: 8)
        #expect(intel.health == 0.9)
        #expect(intel.minutesRemaining == nil)

        let percentOnly = BatteryReading(charge: 1.4, isCharging: true, isPluggedIn: true, minutesRemaining: 30,
                                         cycleCount: nil, maxCapacity: 100, designCapacity: 5_000, watts: nil)
        #expect(percentOnly.health == nil)
        #expect(percentOnly.charge == 1)
    }

    @Test("lsof parser reads ports, dedupes IPv4/IPv6 twins and sorts by port")
    func lsof() {
        let output = """
        p812
        cnode
        f23
        n*:3000
        f24
        n[::1]:3000
        p77
        cpostgres
        f5
        n127.0.0.1:5432
        p90
        cbroken
        nnot-a-port
        """
        let ports = LsofParser.parse(output)
        #expect(ports.map(\.port) == [3000, 5432])
        #expect(ports[0] == ListeningPort(pid: 812, command: "node", port: 3000, address: "*"))
        #expect(ports[1].isLocalOnly)
        #expect(!ports[0].isLocalOnly)
    }
}

@Suite("Maintenance")
struct MaintenanceTests {
    @Test("leftovers are reverse-DNS items of apps that are gone, never Apple's or running ones")
    func leftovers() {
        let installed: Set<String> = ["com.tinyspeck.slackmacgap"]
        let check = { (name: String) in
            LeftoverDetector.isLeftover(itemName: name, isInstalled: { installed.contains($0) }, running: ["com.running.app"])
        }
        #expect(LeftoverDetector.bundleID(fromItemName: "com.old.Tool.plist") == "com.old.Tool")
        #expect(LeftoverDetector.bundleID(fromItemName: "Google") == nil)
        #expect(check("com.old.Tool.plist"))
        #expect(check("org.gone.app.savedState"))
        #expect(!check("com.tinyspeck.slackmacgap"))
        #expect(!check("com.apple.Safari.plist"))
        #expect(!check("com.running.app"))
        #expect(!check("Homebrew"))
    }

    @Test("related files match the bundle id, its suffixes, group containers and the exact app name")
    func related() {
        func match(_ name: String) -> Bool {
            RelatedFiles.matches(itemName: name, bundleID: "com.spotify.client", appName: "Spotify")
        }
        #expect(match("com.spotify.client"))
        #expect(match("com.spotify.client.plist"))
        #expect(match("com.spotify.client.savedState"))
        #expect(match("2FNC3A47ZF.com.spotify.client"))
        #expect(match("Spotify"))
        #expect(!match("com.spotify.clientele"))
        #expect(!match("SpotifyHelperNotes"))
        #expect(!RelatedFiles.matches(itemName: "anything", bundleID: nil, appName: "X"))
    }

    @Test("brew outdated json handles formulae and casks with array or string versions")
    func brewOutdated() {
        let json = """
        {"formulae":[{"name":"git","installed_versions":["2.43","2.44"],"current_version":"2.45"}],
         "casks":[{"name":"firefox","installed_versions":"120.0","current_version":"121.0"}]}
        """
        let packages = BrewParser.outdated(json: Data(json.utf8))
        #expect(packages.map(\.id) == ["cask:firefox", "formula:git"])
        #expect(packages[1].installedVersion == "2.44")
        #expect(packages[0].latestVersion == "121.0")
        #expect(BrewParser.outdated(json: Data("nope".utf8)).isEmpty)
        #expect(BrewParser.names("==> Formulae\nwget\n\ngit\nNo formulae found") == ["wget", "git"])
    }

    @Test("mas outdated lines become store updates with versions")
    func masOutdated() {
        let updates = MasParser.outdated("497799835  Xcode  (15.0 -> 15.1)\n1295203466 Microsoft Remote Desktop (10.9.4 -> 10.9.5)\nWarning: x")
        #expect(updates == [
            StoreUpdate(appID: "497799835", name: "Xcode", installedVersion: "15.0", latestVersion: "15.1"),
            StoreUpdate(appID: "1295203466", name: "Microsoft Remote Desktop", installedVersion: "10.9.4", latestVersion: "10.9.5"),
        ])
    }
}

@Suite("Input")
struct InputTests {
    private let screen = CGRect(x: 0, y: 25, width: 1000, height: 600)

    @Test("layout actions tile the visible frame exactly")
    func layout() {
        let current = CGRect(x: 100, y: 100, width: 400, height: 300)
        #expect(WindowLayout.frame(for: .leftHalf, in: screen, current: current) == CGRect(x: 0, y: 25, width: 500, height: 600))
        #expect(WindowLayout.frame(for: .rightHalf, in: screen, current: current) == CGRect(x: 500, y: 25, width: 500, height: 600))
        #expect(WindowLayout.frame(for: .bottomRight, in: screen, current: current) == CGRect(x: 500, y: 325, width: 500, height: 300))
        #expect(WindowLayout.frame(for: .rightThird, in: screen, current: current) == CGRect(x: 667, y: 25, width: 333, height: 600))
        #expect(WindowLayout.frame(for: .maximize, in: screen, current: current) == screen)
        #expect(WindowLayout.frame(for: .center, in: screen, current: current) == CGRect(x: 300, y: 175, width: 400, height: 300))
    }

    @Test("dragging to edges and corners picks the matching snap")
    func snapping() {
        let full = CGRect(x: 0, y: 0, width: 1000, height: 650)
        #expect(WindowLayout.snapAction(for: CGPoint(x: 0, y: 300), in: full) == .leftHalf)
        #expect(WindowLayout.snapAction(for: CGPoint(x: 999, y: 300), in: full) == .rightHalf)
        #expect(WindowLayout.snapAction(for: CGPoint(x: 500, y: 0), in: full) == .maximize)
        #expect(WindowLayout.snapAction(for: CGPoint(x: 2, y: 20), in: full) == .topLeft)
        #expect(WindowLayout.snapAction(for: CGPoint(x: 998, y: 640), in: full) == .bottomRight)
        #expect(WindowLayout.snapAction(for: CGPoint(x: 500, y: 300), in: full) == nil)
    }

    @Test("hold mode lets the shortcut through only after the hold time")
    func holdGuard() {
        var guardian = QuitGuard(mode: .hold, holdDuration: 0.6)
        #expect(guardian.keyDown(isRepeat: false, at: 0) == .block(progress: 0))
        #expect(guardian.keyDown(isRepeat: true, at: 0.3) == .block(progress: 0.5))
        #expect(guardian.keyDown(isRepeat: true, at: 0.6) == .allow)
        #expect(guardian.keyDown(isRepeat: true, at: 0.7) == .block(progress: 1))
        guardian.keyUp()
        #expect(guardian.keyDown(isRepeat: true, at: 5) == .block(progress: 0))
    }

    @Test("double mode needs two presses close together")
    func doubleGuard() {
        var guardian = QuitGuard(mode: .double, doubleWindow: 0.5)
        #expect(guardian.keyDown(isRepeat: false, at: 0) == .block(progress: 0.5))
        #expect(guardian.keyDown(isRepeat: false, at: 0.4) == .allow)
        #expect(guardian.keyDown(isRepeat: false, at: 2) == .block(progress: 0.5))
        #expect(guardian.keyDown(isRepeat: false, at: 3) == .block(progress: 0.5))
    }

    @Test("scroll glide emits the whole distance and cancels on reversal")
    func glide() {
        var glide = ScrollGlide(response: 0.3)
        glide.add(100)
        var total = 0.0
        while !glide.isIdle { total += glide.step() }
        #expect(total == 100)
        glide.add(50)
        _ = glide.step()
        glide.add(-20)
        #expect(glide.remaining == -20)
    }

    @Test("recent apps keep MRU order and drop apps that quit")
    func recent() {
        let list = RecentApps.activating("b", in: ["a", "b", "c"])
        #expect(list == ["b", "a", "c"])
        #expect(RecentApps.ordered(running: ["c", "d", "b"], recent: list) == ["b", "c", "d"])
    }
}

@Suite("Clipboard and capture")
struct ClipboardAndCaptureTests {
    @Test("history de-duplicates, keeps pins and drops the oldest unpinned entries")
    func history() {
        let old = Date(timeIntervalSince1970: 0)
        let pinned = ClipEntry(kind: .text, text: "keep", pinned: true, date: old)
        let a = ClipEntry(kind: .text, text: "a", date: old.addingTimeInterval(1))
        let b = ClipEntry(kind: .text, text: "b", date: old.addingTimeInterval(2))
        let start = [b, a, pinned]

        let (afterNew, dropped) = ClipboardHistory.adding(ClipEntry(kind: .text, text: "c"), to: start, limit: 2)
        #expect(afterNew.map { $0.text } == ["c", "b", "keep"])
        #expect(dropped.map { $0.text } == ["a"])

        let (repeatPinned, _) = ClipboardHistory.adding(ClipEntry(kind: .text, text: "keep"), to: start, limit: 5)
        #expect(repeatPinned.first?.pinned == true)
        #expect(repeatPinned.filter { $0.text == "keep" }.count == 1)
        #expect(ClipboardHistory.sorted(afterNew).first?.text == "keep")
        #expect(a.matches("A") && !a.matches("zz"))
    }

    @Test("snippet matcher fires on the longest trigger and resets")
    func snippets() {
        let snippets = [Snippet(trigger: ";a", expansion: "short"), Snippet(trigger: ";addr", expansion: "long")]
        var matcher = SnippetMatcher(capacity: 10)
        matcher.type("hi ;add")
        #expect(matcher.match(in: snippets) == nil)
        matcher.type("r")
        #expect(matcher.match(in: snippets)?.expansion == "long")
        #expect(matcher.buffer.isEmpty)
        matcher.type(";ax")
        matcher.backspace()
        #expect(matcher.match(in: snippets)?.expansion == "short")
        matcher.type("0123456789abc")
        #expect(matcher.buffer == "3456789abc")
    }

    @Test("snippet variables expand")
    func expansion() {
        let text = SnippetMatcher.expand("[{clipboard}]", date: Date(), clipboard: "copied", locale: Locale(identifier: "en_US"))
        #expect(text == "[copied]")
        #expect(!SnippetMatcher.expand("{date}", date: Date(timeIntervalSince1970: 0), clipboard: nil,
                                       locale: Locale(identifier: "en_US")).contains("{"))
    }

    @Test("picked colors format as hex, rgb, hsl and SwiftUI")
    func colors() {
        let orange = PickedColor(red: 1, green: 0.5, blue: 0)
        #expect(orange.hex == "#FF8000")
        #expect(orange.rgb == "rgb(255, 128, 0)")
        #expect(orange.hsl == "hsl(30, 100%, 50%)")
        #expect(orange.swiftUI == "Color(red: 1.000, green: 0.500, blue: 0.000)")
        #expect(PickedColor(red: 0.5, green: 0.5, blue: 0.5).hsl == "hsl(0, 0%, 50%)")
    }
}

@Suite("Everyday")
struct EverydayTests {
    @Test("calculator handles precedence, power, percent and rejects junk")
    func calculator() {
        #expect(Calculator.evaluate("2 + 3 × 4") == 14)
        #expect(Calculator.evaluate("(2+3)*4") == 20)
        #expect(Calculator.evaluate("2^3^2") == 512)
        #expect(Calculator.evaluate("-3^2") == -9 || Calculator.evaluate("-3^2") == 9)
        #expect(Calculator.evaluate("200*15%") == 30)
        #expect(Calculator.evaluate("1,5 + 1") == 2.5)
        #expect(Calculator.evaluate("1/0") == nil)
        #expect(Calculator.evaluate("2+") == nil)
        #expect(Calculator.evaluate("(1+2") == nil)
        #expect(Calculator.evaluate("rm -rf") == nil)
        #expect(Calculator.looksLikeMath("12*3"))
        #expect(!Calculator.looksLikeMath("1234"))
        #expect(!Calculator.looksLikeMath("safari"))
    }

    @Test("unit converter handles same-kind conversions in both languages")
    func units() throws {
        let miles = try #require(UnitConverter.convert("10 km to mi"))
        #expect(abs(miles.value - 6.2137) < 0.001)
        #expect(UnitConverter.convert("212 f in c").map { ($0.value * 10).rounded() / 10 } == 100)
        #expect(UnitConverter.convert("2 гб в мб")?.value == 2000)
        #expect(UnitConverter.convert("10 km to kg") == nil)
        #expect(UnitConverter.convert("hello") == nil)
    }

    @Test("emoji search finds by unicode name")
    func emoji() {
        #expect(EmojiIndex.search("rocket").first?.emoji == "🚀")
        #expect(EmojiIndex.search("").isEmpty)
    }

    @Test("agent logs parse claude and codex usage and dedupe streamed messages")
    func agentLogs() {
        let claude = """
        {"type":"assistant","timestamp":"2026-10-13T10:15:00.000Z","message":{"id":"m1","model":"claude-opus","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":0}}}
        {"type":"assistant","timestamp":"2026-10-13T10:15:01.000Z","message":{"id":"m1","model":"claude-opus","usage":{"input_tokens":10,"output_tokens":5}}}
        {"type":"user","timestamp":"2026-10-13T10:16:00.000Z","message":{"content":"hi"}}
        """
        let events = AgentLogParser.claude(lines: claude.split(separator: "\n"))
        #expect(events.count == 1)
        #expect(events.first?.tokens == 115)

        let codex = """
        {"timestamp":"2026-10-13T11:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5"}}
        {"timestamp":"2026-10-13T11:00:05.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":42}}}}
        """
        let codexEvents = AgentLogParser.codex(lines: codex.split(separator: "\n"))
        #expect(codexEvents.map(\.model) == ["gpt-5"])
        #expect(codexEvents.first?.tokens == 42)
    }

    @Test("usage blocks start on the hour and last five hours")
    func blocks() {
        let base = Date(timeIntervalSince1970: 1_800_000_000) // on an hour boundary
        let events = [
            AgentEvent(source: .claude, date: base.addingTimeInterval(600), model: "a", tokens: 10),
            AgentEvent(source: .claude, date: base.addingTimeInterval(4 * 3600), model: "b", tokens: 5),
            AgentEvent(source: .claude, date: base.addingTimeInterval(6 * 3600), model: "a", tokens: 7),
        ]
        let blocks = UsageBlocks.blocks(events)
        #expect(blocks.count == 2)
        #expect(blocks[0].tokens == 15)
        #expect(blocks[0].start == base)
        #expect(blocks[0].byModel == ["a": 10, "b": 5])
        #expect(UsageBlocks.current(events, now: base.addingTimeInterval(6.5 * 3600))?.tokens == 7)
        #expect(UsageBlocks.current(events, now: base.addingTimeInterval(20 * 3600)) == nil)
    }
}

@Suite("SudoersRule")
struct SudoersRuleTests {
    @Test("grants only the three maintenance commands to a valid user")
    func ruleLine() {
        #expect(SudoersRule.line(for: "jane")
            == "jane ALL=(root) NOPASSWD: /usr/sbin/purge, /usr/bin/dscacheutil -flushcache, /usr/bin/killall -HUP mDNSResponder")
    }

    @Test("rejects user names that could inject commands", arguments: ["", "bob; rm -rf /", "a'b", "a b", "-x", "a\"b", "a\\b"])
    func rejectsUnsafeNames(name: String) {
        #expect(SudoersRule.line(for: name) == nil)
        #expect(SudoersRule.installScript(for: name) == nil)
    }

    @Test("install script is safe to embed in an AppleScript string and validates before activating")
    func installScript() throws {
        let script = try #require(SudoersRule.installScript(for: "jane"))
        #expect(!script.contains("\""))
        #expect(!script.contains("\\"))
        #expect(script.contains("visudo -cf /etc/sudoers.d/lumo.tmp"))
        #expect(script.hasSuffix("|| { /bin/rm -f /etc/sudoers.d/lumo.tmp; exit 1; }"))
    }
}

@Suite("System math")
struct SystemMathTests {
    @Test("computes CPU load including counter wrap-around")
    func cpuLoad() {
        let a = CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let b = CPUTicks(user: 200, system: 100, idle: 850, nice: 50)
        #expect(CPUTicks.load(from: a, to: b) == 0.75)

        let wrapped = CPUTicks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)
        let after = CPUTicks(user: 10, system: 0, idle: 20, nice: 0)
        #expect(CPUTicks.load(from: wrapped, to: after) == 0.5)
        #expect(CPUTicks.load(from: a, to: a) == 0)
    }

    @Test("auto trigger needs sustained load and respects cooldown")
    func autoTrigger() {
        var trigger = AutoTrigger(threshold: 0.8, requiredSamples: 2, cooldown: 60)
        let t0 = Date(timeIntervalSince1970: 0)
        let samples: [(Double, TimeInterval)] = [(0.9, 0), (0.5, 0), (0.9, 0), (0.9, 0), (0.9, 10), (0.9, 20), (0.9, 61)]
        let fired = samples.map { load, offset in trigger.feed(load: load, now: t0.addingTimeInterval(offset)) }
        #expect(fired == [false, false, false, true, false, false, true])
    }

    @Test("cache policy only allows third-party idle app caches")
    func cachePolicy() {
        let running: Set<String> = ["com.spotify.client"]
        #expect(CachePolicy.isEligible(folderName: "com.tinyspeck.slackmacgap", runningBundleIDs: running))
        #expect(!CachePolicy.isEligible(folderName: "com.apple.Safari", runningBundleIDs: running))
        #expect(!CachePolicy.isEligible(folderName: "com.Spotify.Client", runningBundleIDs: running))
        #expect(!CachePolicy.isEligible(folderName: "ms-playwright", runningBundleIDs: running))
        #expect(!CachePolicy.isEligible(folderName: ".DS_Store", runningBundleIDs: running))
    }
}
