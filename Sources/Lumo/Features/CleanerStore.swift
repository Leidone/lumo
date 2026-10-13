import AppKit
import LumoCore

/// Finds reclaimable space and removes it. Regenerable data (caches, logs, Xcode builds)
/// is deleted; anything that could be personal (app leftovers, old downloads) goes to the Trash.
@MainActor
final class CleanerStore: ObservableObject {
    enum Kind: String, CaseIterable, Identifiable {
        case caches, logs, derivedData, leftovers, downloads

        var id: Self { self }
        var movesToTrash: Bool { self == .leftovers || self == .downloads }
    }

    struct Item: Identifiable, Equatable {
        let url: URL
        let bytes: UInt64
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    struct Finding: Equatable {
        let items: [Item]
        var bytes: UInt64 { items.reduce(0) { $0 + $1.bytes } }
    }

    private enum Key {
        static let autoClean = "autoCleanWeekly"
        static let lastAutoClean = "lastAutoClean"
    }

    private static let autoInterval: TimeInterval = 7 * 86_400

    @Published private(set) var findings: [Kind: Finding] = [:]
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published private(set) var lastFreedBytes: UInt64?
    @Published var selection: Set<Kind> = [.caches, .logs, .derivedData]
    @Published var includeDownloads = false
    @Published var autoCleanWeekly: Bool { didSet { store.set(autoCleanWeekly, forKey: Key.autoClean) } }

    private let store: UserDefaults

    init(store: UserDefaults) {
        self.store = store
        autoCleanWeekly = store.bool(forKey: Key.autoClean)
    }

    var selectedBytes: UInt64 { selection.compactMap { findings[$0]?.bytes }.reduce(0, +) }
    var lastAutoClean: Date? { store.object(forKey: Key.lastAutoClean) as? Date }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let downloads = includeDownloads
        Task {
            findings = await Task.detached(priority: .utility) {
                CleanerScanner.scan(running: running, includeDownloads: downloads)
            }.value
            isScanning = false
        }
    }

    func clean() {
        guard !isCleaning, !isScanning else { return }
        let targets = findings.filter { selection.contains($0.key) }
        guard !targets.isEmpty else { return }
        isCleaning = true
        Task {
            let deletable = targets.filter { !$0.key.movesToTrash }.flatMap(\.value.items)
            let trashable = targets.filter { $0.key.movesToTrash }.flatMap(\.value.items)
            let deleted = await Task.detached(priority: .userInitiated) { CleanerScanner.delete(deletable) }.value
            let trashed = await Self.recycle(trashable)
            lastFreedBytes = deleted + trashed
            isCleaning = false
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            scan()
        }
    }

    /// Weekly background run: only caches and logs, which apps rebuild on their own.
    func autoCleanIfDue(now: Date) {
        guard autoCleanWeekly, !isCleaning else { return }
        if let last = lastAutoClean, now.timeIntervalSince(last) < Self.autoInterval { return }
        store.set(now, forKey: Key.lastAutoClean)
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        Task.detached(priority: .background) {
            let findings = CleanerScanner.scan(running: running, includeDownloads: false)
            let items = [Kind.caches, .logs].compactMap { findings[$0] }.flatMap(\.items)
            _ = CleanerScanner.delete(items)
        }
    }

    private static func recycle(_ items: [Item]) async -> UInt64 {
        guard !items.isEmpty else { return 0 }
        let trashed = (try? await NSWorkspace.shared.recycle(items.map(\.url))) ?? [:]
        return items.filter { trashed[$0.url] != nil }.reduce(0) { $0 + $1.bytes }
    }
}

/// File-system work; runs off the main thread.
enum CleanerScanner {
    private static let downloadsAge: TimeInterval = 30 * 86_400
    private static let leftoverAge: TimeInterval = 30 * 86_400
    private static let leftoverFolders = [
        "Application Support", "Preferences", "Saved Application State", "HTTPStorages", "WebKit",
    ]

    static func scan(running: Set<String>, includeDownloads: Bool) -> [CleanerStore.Kind: CleanerStore.Finding] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        var result: [CleanerStore.Kind: CleanerStore.Finding] = [:]

        let cacheFolders = children(of: library.appendingPathComponent("Caches")).filter {
            CachePolicy.isEligible(folderName: $0.lastPathComponent, runningBundleIDs: running)
        }
        result[.caches] = finding(cacheFolders.flatMap(children(of:)))
        result[.logs] = finding(children(of: library.appendingPathComponent("Logs")))
        result[.derivedData] = finding(children(of: library.appendingPathComponent("Developer/Xcode/DerivedData")))

        let now = Date()
        let leftovers = leftoverFolders.flatMap { children(of: library.appendingPathComponent($0)) }.filter { url in
            LeftoverDetector.isLeftover(itemName: url.lastPathComponent, isInstalled: isInstalled, running: running)
                && age(of: url, now: now) > leftoverAge
        }
        result[.leftovers] = finding(leftovers)

        if includeDownloads {
            let old = children(of: home.appendingPathComponent("Downloads")).filter { age(of: $0, now: now) > downloadsAge }
            result[.downloads] = finding(old)
        }
        return result
    }

    /// Returns the bytes actually freed.
    static func delete(_ items: [CleanerStore.Item]) -> UInt64 {
        items.reduce(0) { total, item in
            (try? FileManager.default.removeItem(at: item.url)) != nil ? total + item.bytes : total
        }
    }

    static func size(of url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey]
        let own = UInt64((try? url.resourceValues(forKeys: keys).totalFileAllocatedSize) ?? 0)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                                              options: [], errorHandler: { _, _ in true })
        else { return own }
        var total = own
        for case let file as URL in enumerator {
            total += UInt64((try? file.resourceValues(forKeys: keys).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    private static func finding(_ urls: [URL]) -> CleanerStore.Finding {
        let items = urls.map { CleanerStore.Item(url: $0, bytes: size(of: $0)) }
        return CleanerStore.Finding(items: items.sorted { $0.bytes > $1.bytes })
    }

    private static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles])) ?? []
    }

    private static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    private static func age(of url: URL, now: Date) -> TimeInterval {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .addedToDirectoryDateKey])
        let date = [values?.addedToDirectoryDate, values?.contentModificationDate].compactMap { $0 }.max() ?? now
        return now.timeIntervalSince(date)
    }
}
