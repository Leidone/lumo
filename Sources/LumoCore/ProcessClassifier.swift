import Foundation

/// A regular (Dock-visible) application that is currently running.
public struct RunningAppInfo: Equatable, Sendable {
    public let pid: Int32
    public let bundlePath: String
    public let bundleID: String?
    public let name: String
    public let isFrontmost: Bool

    public init(pid: Int32, bundlePath: String, bundleID: String?, name: String, isFrontmost: Bool) {
        self.pid = pid
        self.bundlePath = bundlePath
        self.bundleID = bundleID
        self.name = name
        self.isFrontmost = isFrontmost
    }

    public var exceptionKey: String { bundleID ?? name }

    func owns(path: String) -> Bool {
        path.hasPrefix(bundlePath.hasSuffix("/") ? bundlePath : bundlePath + "/")
    }
}

public struct ClassificationContext: Sendable {
    public let currentUID: UInt32
    public let ownPID: Int32
    public let apps: [RunningAppInfo]
    public let exceptions: Set<String>

    public init(currentUID: UInt32, ownPID: Int32, apps: [RunningAppInfo], exceptions: Set<String>) {
        self.currentUID = currentUID
        self.ownPID = ownPID
        self.apps = apps
        self.exceptions = exceptions
    }
}

public enum ExclusionReason: Equatable, Sendable {
    case otherUser, ownProcess, systemPath, systemName, relativePath, terminalSession
}

public enum ProcessKind: Equatable, Sendable {
    case excluded(ExclusionReason)
    case app(RunningAppInfo)
    case helper(owner: RunningAppInfo)
    case background
}

/// Decides which processes Lumo is allowed to touch. Anything not provably
/// third-party and user-owned is excluded.
public enum ProcessClassifier {
    static let systemPathPrefixes = [
        "/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/", "/private/", "/Library/Developer/",
    ]

    static let systemNames: Set<String> = [
        "launchd", "kernel_task", "WindowServer", "loginwindow", "Dock", "Finder", "SystemUIServer",
        "ControlCenter", "NotificationCenter", "Spotlight", "coreaudiod", "Lumo",
    ]

    public static func classify(_ record: ProcessRecord, in context: ClassificationContext) -> ProcessKind {
        if record.uid != context.currentUID { return .excluded(.otherUser) }
        if record.pid == context.ownPID { return .excluded(.ownProcess) }
        if !record.path.hasPrefix("/") { return .excluded(.relativePath) }
        if systemNames.contains(record.name) { return .excluded(.systemName) }
        if systemPathPrefixes.contains(where: record.path.hasPrefix) { return .excluded(.systemPath) }
        if record.tty != nil { return .excluded(.terminalSession) }

        if let app = context.apps.first(where: { $0.pid == record.pid }) { return .app(app) }
        if let owner = context.apps.first(where: { $0.owns(path: record.path) }) { return .helper(owner: owner) }
        return .background
    }
}
