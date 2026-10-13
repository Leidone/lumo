import AppKit
import LumoCore

/// Lists third-party apps and removes them together with their ~/Library traces.
/// Everything goes to the Trash, so an uninstall can be undone from Finder.
@MainActor
final class UninstallerStore: ObservableObject {
    struct InstalledApp: Identifiable, Equatable {
        let url: URL
        let name: String
        let bundleID: String?
        let version: String?
        var id: URL { url }
    }

    struct Trace: Identifiable, Equatable {
        let url: URL
        let bytes: UInt64
        var id: URL { url }
        var folder: String { url.deletingLastPathComponent().lastPathComponent }
    }

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var selected: InstalledApp?
    @Published private(set) var appBytes: UInt64 = 0
    @Published private(set) var traces: [Trace] = []
    @Published var excluded: Set<URL> = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRemoving = false
    @Published private(set) var lastRemoved: String?

    var totalBytes: UInt64 { appBytes + traces.filter { !excluded.contains($0.url) }.reduce(0) { $0 + $1.bytes } }

    func loadApps() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            apps = await Task.detached(priority: .utility) { UninstallerScanner.installedApps() }.value
            isLoading = false
        }
    }

    func select(_ app: InstalledApp?) {
        selected = app
        traces = []
        excluded = []
        appBytes = 0
        guard let app else { return }
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                (CleanerScanner.size(of: app.url), UninstallerScanner.traces(for: app))
            }.value
            guard selected == app else { return }
            appBytes = found.0
            traces = found.1
        }
    }

    func uninstall(onError: @escaping (String) -> Void) {
        guard let app = selected, !isRemoving else { return }
        isRemoving = true
        Task {
            await Self.quit(app)
            let urls = [app.url] + traces.map(\.url).filter { !excluded.contains($0) }
            do {
                _ = try await NSWorkspace.shared.recycle(urls)
                lastRemoved = app.name
                apps = apps.filter { $0 != app }
                select(nil)
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            } catch {
                onError(error.localizedDescription)
            }
            isRemoving = false
        }
    }

    private static func quit(_ app: InstalledApp) async {
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleURL == app.url }
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }
        for _ in 0..<20 where running.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}

enum UninstallerScanner {
    private static let traceFolders = [
        "Application Support", "Caches", "Preferences", "Saved Application State", "Containers",
        "Group Containers", "HTTPStorages", "WebKit", "Logs", "LaunchAgents", "Cookies", "Application Scripts",
    ]

    static func installedApps() -> [UninstallerStore.InstalledApp] {
        let fileManager = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"),
                     fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        let ownID = Bundle.main.bundleIdentifier
        return roots
            .flatMap { root in
                (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            }
            .filter { $0.pathExtension == "app" }
            .compactMap { url -> UninstallerStore.InstalledApp? in
                let bundle = Bundle(url: url)
                let bundleID = bundle?.bundleIdentifier
                guard bundleID?.hasPrefix("com.apple.") != true, bundleID != ownID else { return nil }
                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                return UninstallerStore.InstalledApp(url: url, name: name, bundleID: bundleID, version: version)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func traces(for app: UninstallerStore.InstalledApp) -> [UninstallerStore.Trace] {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let appName = app.url.deletingPathExtension().lastPathComponent
        return traceFolders
            .flatMap { folder -> [URL] in
                let url = library.appendingPathComponent(folder)
                return (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            }
            .filter { RelatedFiles.matches(itemName: $0.lastPathComponent, bundleID: app.bundleID, appName: appName) }
            .map { UninstallerStore.Trace(url: $0, bytes: CleanerScanner.size(of: $0)) }
            .sorted { $0.bytes > $1.bytes }
    }
}
