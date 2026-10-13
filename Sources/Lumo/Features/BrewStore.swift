import AppKit
import LumoCore

/// Homebrew (formulae and casks) and Mac App Store updates via `mas`, driven through their CLIs.
@MainActor
final class BrewStore: ObservableObject {
    @Published private(set) var outdated: [BrewPackage] = []
    @Published private(set) var storeUpdates: [StoreUpdate] = []
    @Published private(set) var installedFormulae: [String] = []
    @Published private(set) var installedCasks: [String] = []
    @Published private(set) var searchResults: [BrewPackage] = []
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSearching = false
    @Published private(set) var lastChecked: Date?
    @Published var lastError: String?

    let brewPath = Shell.locate("brew")
    let masPath = Shell.locate("mas")

    var hasBrew: Bool { brewPath != nil }
    var updateCount: Int { outdated.count + storeUpdates.count }

    /// `updateIndex` runs `brew update` first (slower, but sees brand-new versions).
    func refresh(updateIndex: Bool = false) {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            if let brewPath {
                if updateIndex { _ = await Shell.run(brewPath, ["update", "--quiet"]) }
                async let outdatedRun = Shell.run(brewPath, ["outdated", "--json=v2"])
                async let formulaeRun = Shell.run(brewPath, ["list", "--formula", "-1"])
                async let casksRun = Shell.run(brewPath, ["list", "--cask", "-1"])
                let (outdatedResult, formulae, casks) = await (outdatedRun, formulaeRun, casksRun)
                outdated = BrewParser.outdated(json: Data(outdatedResult.output.utf8))
                installedFormulae = BrewParser.names(formulae.output)
                installedCasks = BrewParser.names(casks.output)
            }
            if let masPath {
                storeUpdates = MasParser.outdated(await Shell.run(masPath, ["outdated"]).output)
            }
            lastChecked = Date()
            isRefreshing = false
        }
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard let brewPath, trimmed.count >= 2 else {
            searchResults = []
            return
        }
        isSearching = true
        Task {
            async let formulae = Shell.run(brewPath, ["search", "--formula", trimmed])
            async let casks = Shell.run(brewPath, ["search", "--cask", trimmed])
            let (formulaResult, caskResult) = await (formulae, casks)
            let found = BrewParser.names(formulaResult.output).map { BrewPackage(name: $0, isCask: false, installedVersion: nil, latestVersion: nil) }
                + BrewParser.names(caskResult.output).map { BrewPackage(name: $0, isCask: true, installedVersion: nil, latestVersion: nil) }
            searchResults = Array(found.prefix(40))
            isSearching = false
        }
    }

    func isInstalled(_ package: BrewPackage) -> Bool {
        (package.isCask ? installedCasks : installedFormulae).contains(package.name)
    }

    func upgrade(_ package: BrewPackage) { runBrew(package.id, ["upgrade"] + kindFlag(package) + [package.name]) }
    func install(_ package: BrewPackage) { runBrew(package.id, ["install"] + kindFlag(package) + [package.name]) }
    func uninstall(_ package: BrewPackage) { runBrew(package.id, ["uninstall"] + kindFlag(package) + [package.name]) }

    func upgradeAll() {
        runBrew("all", ["upgrade"])
        if let masPath, !storeUpdates.isEmpty { runTool(masPath, id: "store-all", ["upgrade"]) }
    }

    func upgrade(_ update: StoreUpdate) {
        guard let masPath else { return }
        runTool(masPath, id: update.id, ["upgrade", update.appID])
    }

    func openAppStoreUpdates() {
        if let url = URL(string: "macappstore://showUpdatesPage") { NSWorkspace.shared.open(url) }
    }

    private func kindFlag(_ package: BrewPackage) -> [String] { package.isCask ? ["--cask"] : ["--formula"] }

    private func runBrew(_ id: String, _ arguments: [String]) {
        guard let brewPath else { return }
        runTool(brewPath, id: id, arguments)
    }

    private func runTool(_ path: String, id: String, _ arguments: [String]) {
        guard !busy.contains(id) else { return }
        busy = busy.union([id])
        Task {
            let result = await Shell.run(path, arguments)
            busy = busy.subtracting([id])
            if result.status != 0 {
                let detail = result.errorOutput.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
                lastError = detail.isEmpty ? "\(URL(fileURLWithPath: path).lastPathComponent) \(arguments.joined(separator: " ")) failed" : detail
            }
            refresh()
        }
    }
}

/// Runs command-line tools off the main thread with a predictable environment.
enum Shell {
    struct Result {
        let status: Int32
        let output: String
        let errorOutput: String
    }

    private static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    static func locate(_ tool: String) -> String? {
        searchPaths.map { "\($0)/\(tool)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func run(_ executable: String, _ arguments: [String]) async -> Result {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = searchPaths.joined(separator: ":")
            environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            environment["HOMEBREW_NO_ENV_HINTS"] = "1"
            environment["NONINTERACTIVE"] = "1"
            process.environment = environment
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            do {
                try process.run()
            } catch {
                return Result(status: -1, output: "", errorOutput: error.localizedDescription)
            }
            async let stdout = output.fileHandleForReading.readToEnd()
            async let stderr = errors.fileHandleForReading.readToEnd()
            let (outData, errData) = await ((try? stdout) ?? nil, (try? stderr) ?? nil)
            process.waitUntilExit()
            return Result(status: process.terminationStatus,
                          output: String(decoding: outData ?? Data(), as: UTF8.self),
                          errorOutput: String(decoding: errData ?? Data(), as: UTF8.self))
        }.value
    }
}
