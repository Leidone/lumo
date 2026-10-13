import Foundation

/// Resource usage of one thing the user can act on: an app (with all its helpers)
/// or a single background process.
public struct UsageGroup: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case app(RunningAppInfo)
        case background(ProcessRecord)
    }

    public let id: String
    public let kind: Kind
    public let displayName: String
    public let iconPath: String
    public let exceptionKey: String
    public let cpuPercent: Double
    public let residentBytes: UInt64
    public let pids: [Int32]
    public let isException: Bool
    public let isFrontmost: Bool

    public var isApp: Bool {
        if case .app = kind { return true }
        return false
    }
}

public enum PlannedAction: Equatable, Sendable {
    /// Ask a GUI app to quit normally (it may prompt to save documents).
    case quitApp
    /// Send SIGTERM to a background process.
    case terminate
}

public struct PlanItem: Identifiable, Equatable, Sendable {
    public let group: UsageGroup
    public let action: PlannedAction
    public var id: String { group.id }

    public init(group: UsageGroup, action: PlannedAction) {
        self.group = group
        self.action = action
    }
}

public enum OptimizationPlanner {
    /// Groups user-actionable processes; helpers are folded into their owning app.
    public static func groups(from records: [ProcessRecord], context: ClassificationContext) -> [UsageGroup] {
        var appTotals: [Int32: (app: RunningAppInfo, cpu: Double, bytes: UInt64, pids: [Int32])] = [:]
        var background: [UsageGroup] = []

        for record in records {
            switch ProcessClassifier.classify(record, in: context) {
            case .excluded:
                continue
            case .app(let app), .helper(let app):
                let current = appTotals[app.pid] ?? (app, 0, 0, [])
                appTotals[app.pid] = (app, current.cpu + record.cpuPercent,
                                      current.bytes + record.residentBytes, current.pids + [record.pid])
            case .background:
                background.append(UsageGroup(
                    id: "pid:\(record.pid)", kind: .background(record), displayName: record.name,
                    iconPath: record.path, exceptionKey: record.name, cpuPercent: record.cpuPercent,
                    residentBytes: record.residentBytes, pids: [record.pid],
                    isException: context.exceptions.contains(record.name), isFrontmost: false))
            }
        }

        let apps = appTotals.values.map { entry in
            UsageGroup(
                id: "app:\(entry.app.bundlePath)", kind: .app(entry.app), displayName: entry.app.name,
                iconPath: entry.app.bundlePath, exceptionKey: entry.app.exceptionKey, cpuPercent: entry.cpu,
                residentBytes: entry.bytes, pids: entry.pids,
                isException: context.exceptions.contains(entry.app.exceptionKey),
                isFrontmost: entry.app.isFrontmost)
        }
        return (apps + background).sorted { impactScore($0) > impactScore($1) }
    }

    public static func plan(_ groups: [UsageGroup], policy: OptimizationPolicy, closeApps: Bool) -> [PlanItem] {
        groups.compactMap { group in
            guard !group.isException, !group.isFrontmost, policy.exceeds(group) else { return nil }
            if group.isApp { return closeApps ? PlanItem(group: group, action: .quitApp) : nil }
            return PlanItem(group: group, action: .terminate)
        }
    }

    /// 10% CPU weighs the same as 1 GB of RAM.
    static func impactScore(_ group: UsageGroup) -> Double {
        group.cpuPercent + Double(group.residentBytes) / 1_073_741_824 * 10
    }
}
