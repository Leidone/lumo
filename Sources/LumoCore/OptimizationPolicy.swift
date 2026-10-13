import Foundation

/// Maps the user's "intensity" slider (0…1) to concrete limits.
public struct OptimizationPolicy: Equatable, Sendable {
    public enum Level: String, Sendable { case gentle, balanced, maximum }

    public let intensity: Double

    public init(intensity: Double) {
        self.intensity = min(max(intensity, 0), 1)
    }

    /// CPU % above which a process/app is considered a hog: 60% → 10%.
    public var cpuLimitPercent: Double { 60 - 50 * intensity }

    /// App memory limit (all helpers combined): 4 GB → 1 GB.
    public var appMemoryLimitBytes: UInt64 { Self.megabytes(4096 - 3072 * intensity) }

    /// Background process memory limit: 2 GB → 256 MB.
    public var backgroundMemoryLimitBytes: UInt64 { Self.megabytes(2048 - 1792 * intensity) }

    /// At high intensity processes that ignore SIGTERM get SIGKILL.
    public var forceKillStubborn: Bool { intensity >= 0.8 }

    public var level: Level {
        switch intensity {
        case ..<0.34: return .gentle
        case ..<0.67: return .balanced
        default: return .maximum
        }
    }

    public func memoryLimit(forApp isApp: Bool) -> UInt64 {
        isApp ? appMemoryLimitBytes : backgroundMemoryLimitBytes
    }

    public func exceeds(_ group: UsageGroup) -> Bool {
        group.cpuPercent > cpuLimitPercent || group.residentBytes > memoryLimit(forApp: group.isApp)
    }

    private static func megabytes(_ value: Double) -> UInt64 {
        UInt64(value.rounded()) * 1_048_576
    }
}
