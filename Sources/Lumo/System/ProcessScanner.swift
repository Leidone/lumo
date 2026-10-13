import AppKit
import LumoCore

enum ProcessScanner {
    struct ScanError: LocalizedError {
        let status: Int32
        var errorDescription: String? { "ps exited with status \(status)" }
    }

    /// Runs `ps` once. Call off the main thread.
    static func snapshot() throws -> [ProcessRecord] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = PSParser.arguments
        process.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ScanError(status: process.terminationStatus) }
        return PSParser.parse(String(decoding: data, as: UTF8.self))
    }

    @MainActor
    static func runningApps(frontmostPID: pid_t?) -> [RunningAppInfo] {
        let ownPID = getpid()
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, app.processIdentifier != ownPID, let url = app.bundleURL else {
                return nil
            }
            return RunningAppInfo(
                pid: app.processIdentifier, bundlePath: url.path, bundleID: app.bundleIdentifier,
                name: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                isFrontmost: app.processIdentifier == frontmostPID)
        }
    }
}
