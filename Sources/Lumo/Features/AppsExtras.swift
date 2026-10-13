import AppKit
import LumoCore

/// Updates announced by apps' own Sparkle feeds (the address each app lists as SUFeedURL).
@MainActor
final class FeedUpdates: ObservableObject {
    struct Update: Identifiable, Equatable {
        let app: URL
        let name: String
        let installed: String
        let latest: String
        let download: URL?
        var id: String { app.path }
    }

    @Published private(set) var updates: [Update] = []
    @Published private(set) var checkedApps = 0
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheck: Date?

    func check() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            let candidates = await Task.detached(priority: .utility) { Self.appsWithFeeds() }.value
            checkedApps = candidates.count
            var found: [Update] = []
            await withTaskGroup(of: Update?.self) { group in
                for candidate in candidates {
                    group.addTask { await Self.check(candidate) }
                }
                for await update in group { if let update { found.append(update) } }
            }
            updates = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            lastCheck = Date()
            isChecking = false
        }
    }

    /// Opens the app so its own updater can install the new version.
    func openUpdater(_ update: Update) {
        NSWorkspace.shared.openApplication(at: update.app, configuration: NSWorkspace.OpenConfiguration())
    }

    private struct Candidate: Sendable {
        let app: URL
        let name: String
        let short: String
        let build: String
        let feed: URL
    }

    nonisolated private static func appsWithFeeds() -> [Candidate] {
        let roots = ["/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        return roots.flatMap { root -> [Candidate] in
            ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).filter { $0.hasSuffix(".app") }.compactMap { name in
                let app = URL(fileURLWithPath: root).appendingPathComponent(name)
                guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
                      let feedString = info["SUFeedURL"] as? String, let feed = URL(string: feedString), feed.scheme == "https"
                else { return nil }
                return Candidate(app: app, name: name.replacingOccurrences(of: ".app", with: ""),
                                 short: info["CFBundleShortVersionString"] as? String ?? "", build: info["CFBundleVersion"] as? String ?? "", feed: feed)
            }
        }
    }

    nonisolated private static func check(_ candidate: Candidate) async -> Update? {
        var request = URLRequest(url: candidate.feed, timeoutInterval: 12)
        request.setValue("Lumo (https://github.com/Leidone/lumo)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = AppcastParser.latest(data), latest.isNewer(thanShort: candidate.short, build: candidate.build)
        else { return nil }
        return Update(app: candidate.app, name: candidate.name, installed: candidate.short,
                      latest: latest.shortVersion.isEmpty ? latest.build : latest.shortVersion, download: latest.downloadURL)
    }
}

/// Files that messengers save on their own, with a retention rule.
@MainActor
final class MessagingDownloads: ObservableObject {
    struct Source: Identifiable, Equatable {
        let id: String
        let name: String
        let folder: URL
        var bytes: UInt64 = 0
        var files = 0
        var oldBytes: UInt64 = 0
        var oldFiles = 0
    }

    private enum Key {
        static let days = "messaging.retentionDays"
        static let auto = "messaging.autoClean"
        static let lastAuto = "messaging.lastAutoClean"
    }

    @Published private(set) var sources: [Source] = []
    @Published private(set) var isScanning = false
    @Published var retentionDays: Int { didSet { store.set(retentionDays, forKey: Key.days); scan() } }
    @Published var autoClean: Bool { didSet { store.set(autoClean, forKey: Key.auto) } }

    var t = Localizer(language: .english)
    private let store: UserDefaults

    init(store: UserDefaults) {
        self.store = store
        store.register(defaults: [Key.days: 30])
        retentionDays = store.integer(forKey: Key.days)
        autoClean = store.bool(forKey: Key.auto)
    }

    nonisolated private static var known: [(id: String, name: String, path: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ("telegram", "Telegram", home.appendingPathComponent("Downloads/Telegram Desktop").path),
            ("whatsapp", "WhatsApp", home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media").path),
            ("viber", "Viber", home.appendingPathComponent("Documents/ViberDownloads").path),
            ("wechat", "WeChat", home.appendingPathComponent("Library/Containers/com.tencent.xinWeChat/Data/Library/Application Support/com.tencent.xinWeChat").path),
        ]
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        Task {
            sources = await Task.detached(priority: .utility) {
                Self.known.filter { FileManager.default.fileExists(atPath: $0.path) }.map { item in
                    var source = Source(id: item.id, name: item.name, folder: URL(fileURLWithPath: item.path))
                    for (url, size, date) in Self.files(in: source.folder) {
                        _ = url
                        source.bytes += size
                        source.files += 1
                        if date < cutoff {
                            source.oldBytes += size
                            source.oldFiles += 1
                        }
                    }
                    return source
                }
            }.value
            isScanning = false
        }
    }

    /// Weekly, if the rule is on.
    func autoCleanIfDue(now: Date) {
        guard autoClean else { return }
        let last = store.object(forKey: Key.lastAuto) as? Date ?? .distantPast
        guard now.timeIntervalSince(last) > 7 * 86_400 else { return }
        // The first pass only measures; the cleanup happens on the next check, once sizes are known.
        guard !sources.isEmpty else { return scan() }
        store.set(now, forKey: Key.lastAuto)
        for source in sources { trashOld(source, announce: false) }
    }

    /// Moves files older than the retention period to the Trash (recoverable).
    func trashOld(_ source: Source, announce: Bool = true) {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        let old = Self.files(in: source.folder).filter { $0.date < cutoff }.map(\.url)
        guard !old.isEmpty else { return }
        Task {
            _ = try? await NSWorkspace.shared.recycle(old)
            if announce {
                Toast.show("trash.fill", t("В Корзину: \(old.count)", "Moved to Trash: \(old.count)"), subtitle: source.name, tint: Palette.orange.color)
            }
            scan()
        }
    }

    /// Sorts the files into ~/Downloads/Messaging/<App>/<Kind>.
    func organize(_ source: Source) {
        let target = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/Messaging/\(source.name)")
        let files = Self.files(in: source.folder).map(\.url)
        var moved = 0
        for file in files {
            let folder = target.appendingPathComponent(Self.kind(of: file))
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var destination = folder.appendingPathComponent(file.lastPathComponent)
            var index = 2
            while FileManager.default.fileExists(atPath: destination.path) {
                destination = folder.appendingPathComponent("\(file.deletingPathExtension().lastPathComponent) \(index).\(file.pathExtension)")
                index += 1
            }
            if (try? FileManager.default.moveItem(at: file, to: destination)) != nil { moved += 1 }
        }
        Toast.show("folder.fill", t("Разложено файлов: \(moved)", "Organized \(moved) files"), subtitle: target.path, tint: Palette.green.color)
        NSWorkspace.shared.activateFileViewerSelecting([target])
        scan()
    }

    nonisolated private static func kind(of url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return "Images"
        case "mp4", "mov", "m4v", "webm": return "Videos"
        case "mp3", "m4a", "ogg", "opus", "wav": return "Audio"
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "pages", "numbers", "key": return "Documents"
        case "zip", "rar", "7z", "dmg", "pkg": return "Archives"
        default: return "Other"
        }
    }

    nonisolated private static func files(in folder: URL) -> [(url: URL, size: UInt64, date: Date)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        return (enumerator?.allObjects as? [URL] ?? []).compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            return (url, UInt64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
        }
    }
}
