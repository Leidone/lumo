import AppKit
import CoreImage
import LumoCore
import SwiftUI

/// System-wide Now Playing (Music, Spotify, browsers, podcasts…) for the Dynamic Island.
///
/// MediaRemote only answers Apple-signed processes since macOS 15.4, so the work happens in a tiny
/// library hosted by /usr/bin/perl (Helpers/NowPlaying.m). It streams JSON lines and takes commands
/// on stdin. If the bridge is missing, Music and Spotify are still read through AppleScript.
@MainActor
final class NowPlayingService: ObservableObject {
    struct Track: Equatable {
        let state: NowPlayingState
        let bundleID: String?
        let pid: pid_t

        var id: String { "\(bundleID ?? "")|\(state.title)|\(state.artist)" }
    }

    enum Command: String {
        case toggle, play, pause, next, previous
    }

    private static let helperName = "LumoNowPlaying"
    private static let maxRestarts = 5
    private static let scriptedPlayers = ["com.spotify.client", "com.apple.Music"]

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = Palette.pink.color
    /// Called when a different track starts playing (not on pause/resume).
    var onNewTrack: ((Track) -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var restarts = 0
    private var scriptTimer: Timer?
    private var isRunning = false
    /// A different player's track waits here until it has held for a moment.
    private var pending: (track: Track?, artwork: NSImage??, since: Date)?
    private var peeked: [String: Date] = [:]
    private static let switchDelay: TimeInterval = 1.5
    private static let peekCooldown: TimeInterval = 120

    func start() {
        guard !isRunning else { return }
        isRunning = true
        restarts = 0
        if !launchBridge() { startScriptedPolling() }
    }

    func stop() {
        isRunning = false
        scriptTimer?.invalidate()
        scriptTimer = nil
        try? input?.close()
        process?.terminate()
        process = nil
        input = nil
        track = nil
        artwork = nil
    }

    func send(_ command: Command) {
        if process != nil {
            write(command.rawValue)
        } else if let bundleID = track?.bundleID, Self.scriptedPlayers.contains(bundleID) {
            // Only the two known players are ever named inside AppleScript.
            let verbs: [Command: String] = [.toggle: "playpause", .play: "play", .pause: "pause", .next: "next track", .previous: "previous track"]
            var error: NSDictionary?
            NSAppleScript(source: "tell application id \"\(bundleID)\" to \(verbs[command] ?? "playpause")")?.executeAndReturnError(&error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.pollScripted() }
        }
    }

    func seek(to seconds: Double) {
        guard process != nil, seconds.isFinite else { return }
        write("seek \(max(seconds, 0))")
    }

    // MARK: Bridge

    private static func helperURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: helperName, withExtension: "dylib") { return bundled }
        // Development runs: walk up from the executable to the repository's build/helpers folder.
        var folder = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<6 {
            guard let current = folder else { break }
            let candidate = current.appendingPathComponent("build/helpers/\(helperName).dylib")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            folder = current.deletingLastPathComponent()
        }
        return nil
    }

    private func launchBridge() -> Bool {
        guard let helper = Self.helperURL(), FileManager.default.isExecutableFile(atPath: "/usr/bin/perl") else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", """
            use DynaLoader;
            my $h = DynaLoader::dl_load_file($ARGV[0], 0) or exit 4;
            my $s = DynaLoader::dl_find_symbol($h, "lumo_nowplaying_main") or exit 5;
            DynaLoader::dl_install_xsub("main::run", $s);
            run();
            """, helper.path]
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.consume(data) }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in self?.bridgeEnded(status: status) }
        }
        do {
            try process.run()
        } catch {
            return false
        }
        self.process = process
        self.input = input.fileHandleForWriting
        write("refresh")
        return true
    }

    private func bridgeEnded(status: Int32) {
        process = nil
        input = nil
        guard isRunning else { return }
        restarts += 1
        guard restarts <= Self.maxRestarts, status == 0 || status == 15 else { return startScriptedPolling() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.isRunning, self.process == nil else { return }
            if !self.launchBridge() { self.startScriptedPolling() }
        }
    }

    private func write(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        try? input?.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { apply(object) }
        }
    }

    private func apply(_ object: [String: Any]) {
        guard object["type"] as? String == "info", let title = object["title"] as? String else {
            receive(nil, artwork: .some(nil))
            return
        }
        let state = NowPlayingState(
            title: title,
            artist: object["artist"] as? String ?? "",
            album: object["album"] as? String ?? "",
            duration: object["duration"] as? Double ?? 0,
            elapsed: object["elapsed"] as? Double ?? 0,
            timestamp: Date(timeIntervalSince1970: object["timestamp"] as? Double ?? Date().timeIntervalSince1970),
            rate: object["rate"] as? Double ?? 0)
        let pid = pid_t(object["pid"] as? Int ?? 0)
        let bundleID = object["bundle"] as? String ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let artwork: NSImage?? = (object["artwork"] as? String).map { Data(base64Encoded: $0).flatMap(NSImage.init(data:)) }
        receive(Track(state: state, bundleID: bundleID, pid: pid), artwork: artwork)
    }

    /// Two players (a page and its embedded video, say) can take turns reporting; switching to a different
    /// track only happens once it has held for a moment, so the island doesn't flicker and re-animate.
    private func receive(_ next: Track?, artwork: NSImage??) {
        let switching = next?.id != track?.id
        guard switching, track != nil else {
            pending = nil
            apply(next, artwork: artwork)
            return
        }
        if let pending, pending.track?.id == next?.id {
            self.pending = (next, artwork ?? pending.artwork, pending.since)
            guard Date().timeIntervalSince(pending.since) >= Self.switchDelay else { return }
            self.pending = nil
            apply(next, artwork: artwork ?? pending.artwork)
            return
        }
        pending = (next, artwork, Date())
        let id = next?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.switchDelay + 0.05) { [weak self] in
            guard let self, let pending = self.pending, pending.track?.id == id else { return }
            self.pending = nil
            self.apply(pending.track, artwork: pending.artwork)
        }
    }

    private func apply(_ next: Track?, artwork: NSImage??) {
        if let artwork { setArtwork(artwork) }
        // Position-only updates that match what the clock already shows don't need a redraw.
        if let current = track, let next, current.id == next.id, current.state.isPlaying == next.state.isPlaying,
           current.state.duration == next.state.duration,
           abs(current.state.elapsed(at: Date()) - next.state.elapsed(at: Date())) < 1.5 {
            return
        }
        guard next != track else { return }
        let isNew = next != nil && next?.id != track?.id
        track = next
        guard isNew, let next, next.state.isPlaying else { return }
        // Announce a track once, not every time two players trade places.
        if let shown = peeked[next.id], Date().timeIntervalSince(shown) < Self.peekCooldown { return }
        peeked[next.id] = Date()
        onNewTrack?(next)
    }

    private func setArtwork(_ image: NSImage?) {
        artwork = image
        guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            accent = Palette.pink.color
            return
        }
        Task.detached(priority: .utility) {
            let color = Self.averageColor(of: cgImage)
            await MainActor.run { [weak self] in
                withAnimation(.easeInOut(duration: 0.6)) { self?.accent = color }
            }
        }
    }

    nonisolated private static func averageColor(of cgImage: CGImage) -> Color {
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)]),
              let output = filter.outputImage
        else { return Palette.pink.color }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()])
            .render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        // Lift dark covers so the glow stays visible on the black island.
        let color = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: hue, saturation: min(saturation * 1.2, 1), brightness: max(brightness, 0.75))
    }

    // MARK: AppleScript fallback (Music and Spotify only, polled while they run)

    private func startScriptedPolling() {
        guard isRunning, scriptTimer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.pollScripted() } }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        scriptTimer = timer
        pollScripted()
    }

    private func pollScripted() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for bundleID in Self.scriptedPlayers where running.contains(bundleID) {
            let script = """
            tell application id "\(bundleID)"
                if player state is stopped then return ""
                return (player state as string) & "\\n" & (name of current track) & "\\n" & (artist of current track) & "\\n" & (player position as string) & "\\n" & ((duration of current track) as string)
            end tell
            """
            var error: NSDictionary?
            guard let output = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue, !output.isEmpty else { continue }
            let parts = output.components(separatedBy: "\n")
            guard parts.count >= 5 else { continue }
            let rawDuration = Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0
            // Spotify reports milliseconds, Music seconds.
            let duration = rawDuration > 10_000 ? rawDuration / 1000 : rawDuration
            let state = NowPlayingState(title: parts[1], artist: parts[2], album: "", duration: duration,
                                        elapsed: Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0,
                                        timestamp: Date(), rate: parts[0] == "playing" ? 1 : 0)
            receive(Track(state: state, bundleID: bundleID, pid: 0), artwork: nil)
            return
        }
        receive(nil, artwork: nil)
    }
}
