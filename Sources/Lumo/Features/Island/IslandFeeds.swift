import AppKit
import EventKit
import LumoCore
import SwiftUI

// MARK: - Calendar

/// Upcoming events from the user's calendars (read-only, asks for access once).
@MainActor
final class CalendarFeed: ObservableObject {
    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let color: Color
        let meetingURL: URL?
    }

    private static let lookahead: TimeInterval = 36 * 3600
    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "telemost.yandex.ru", "whereby.com", "webex.com"]

    @Published private(set) var events: [Event] = []
    @Published private(set) var access: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    var isAuthorized: Bool { access == .fullAccess }

    func start() {
        guard timer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.reload() } }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        reload()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            Task { @MainActor in
                self?.access = EKEventStore.authorizationStatus(for: .event)
                self?.reload()
            }
        }
    }

    /// The next timed event starting within `minutes`, used for the "starting soon" banner.
    func startingSoon(within minutes: Double, now: Date = .now) -> Event? {
        events.first { !$0.isAllDay && $0.start > now && $0.start.timeIntervalSince(now) <= minutes * 60 }
    }

    private func reload() {
        access = EKEventStore.authorizationStatus(for: .event)
        guard isAuthorized else {
            events = []
            return
        }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: now.addingTimeInterval(Self.lookahead), calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
            .map { event in
                Event(id: event.eventIdentifier ?? UUID().uuidString, title: event.title ?? "—", start: event.startDate, end: event.endDate,
                      isAllDay: event.isAllDay, color: Color(nsColor: event.calendar?.color ?? .systemBlue),
                      meetingURL: Self.meetingURL(in: event))
            }
    }

    private static func meetingURL(in event: EKEvent) -> URL? {
        if let url = event.url, isMeeting(url) { return url }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: " ")
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url).first(where: isMeeting)
    }

    private static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

// MARK: - Downloads

/// Watches ~/Downloads for browsers' temporary files to show progress and a "done" banner.
@MainActor
final class DownloadWatcher: ObservableObject {
    struct Download: Identifiable, Equatable {
        let id: String
        let name: String
        let bytes: Int64
        let total: Int64?
        let speed: Double

        var progress: Double? { total.map { $0 > 0 ? min(Double(bytes) / Double($0), 1) : 0 } }
    }

    @Published private(set) var active: [Download] = []
    var onFinished: ((URL) -> Void)?

    private let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var pollTimer: Timer?
    private var previous: [String: (bytes: Int64, at: Date)] = [:]

    func start() {
        guard source == nil else { return }
        descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scan() } }
        let fd = descriptor
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        scan()
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
        pollTimer?.invalidate()
        pollTimer = nil
        active = []
        previous = [:]
    }

    private func scan() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let now = Date()
        var next: [Download] = []
        for name in names {
            guard let finalName = DownloadNames.finalName(of: name) else { continue }
            let url = folder.appendingPathComponent(name)
            let (bytes, total) = Self.measure(url)
            let last = previous[name]
            let elapsed = last.map { now.timeIntervalSince($0.at) } ?? 0
            let speed = last.map { elapsed > 0 ? Double(bytes - $0.bytes) / elapsed : 0 } ?? 0
            previous[name] = (bytes, now)
            next.append(Download(id: name, name: finalName, bytes: bytes, total: total, speed: max(speed, 0)))
        }
        // A temporary file that vanished while its final name now exists has finished.
        let finished = active.filter { old in !next.contains { $0.id == old.id } }
        for download in finished {
            previous[download.id] = nil
            let url = folder.appendingPathComponent(download.name)
            if FileManager.default.fileExists(atPath: url.path) { onFinished?(url) }
        }
        if next != active { active = next }
        updatePolling()
    }

    /// Growing files don't always post directory events, so poll once a second while anything downloads.
    private func updatePolling() {
        if active.isEmpty {
            pollTimer?.invalidate()
            pollTimer = nil
        } else if pollTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.scan() } }
            timer.tolerance = 0.3
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
    }

    private static func measure(_ url: URL) -> (Int64, Int64?) {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard isDirectory.boolValue else {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
            return (size?.int64Value ?? 0, nil)
        }
        // Safari keeps a bundle with its progress in Info.plist.
        let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist"))
        let bytes = (info?["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
        let total = (info?["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
        return (bytes, total.flatMap { $0 > 0 ? $0 : nil })
    }
}

// MARK: - Lyrics

/// Synced lyrics from lrclib.net (free, no account). Only used when the user turns it on.
@MainActor
final class LyricsService: ObservableObject {
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var trackID: String?

    private var cache: [String: [LyricLine]] = [:]
    private var task: Task<Void, Never>?

    func load(for track: NowPlayingService.Track?) {
        guard let track, !track.state.title.isEmpty else {
            task?.cancel()
            lines = []
            trackID = nil
            return
        }
        guard track.id != trackID else { return }
        trackID = track.id
        task?.cancel()
        if let cached = cache[track.id] {
            lines = cached
            return
        }
        lines = []
        let state = track.state
        let id = track.id
        task = Task { [weak self] in
            let fetched = await Self.fetch(state)
            guard !Task.isCancelled else { return }
            self?.cache[id] = fetched
            if self?.trackID == id { self?.lines = fetched }
        }
    }

    func line(at time: Double) -> String? {
        LyricsParser.index(at: time, in: lines).map { lines[$0].text }.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func fetch(_ state: NowPlayingState) async -> [LyricLine] {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: state.title),
            URLQueryItem(name: "artist_name", value: state.artist),
            URLQueryItem(name: "album_name", value: state.album),
            URLQueryItem(name: "duration", value: String(Int(state.duration.rounded()))),
        ].filter { !($0.value ?? "").isEmpty }
        guard !state.artist.isEmpty, let url = components?.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Lumo (https://github.com/Leidone/lumo)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let synced = object["syncedLyrics"] as? String
        else { return [] }
        return LyricsParser.parse(synced)
    }
}
