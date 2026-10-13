import Foundation

/// Raw CPU tick counters from `host_statistics(HOST_CPU_LOAD_INFO)`.
public struct CPUTicks: Equatable, Sendable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    /// Busy fraction (0…1) between two samples. Counters may wrap around.
    public static func load(from previous: CPUTicks, to current: CPUTicks) -> Double {
        let busy = Double(current.user &- previous.user) + Double(current.system &- previous.system)
            + Double(current.nice &- previous.nice)
        let total = busy + Double(current.idle &- previous.idle)
        guard total > 0 else { return 0 }
        return min(max(busy / total, 0), 1)
    }
}

/// Fires an automatic optimization when load stays above a threshold for a
/// few samples in a row, but not more often than once per cooldown.
public struct AutoTrigger: Equatable, Sendable {
    public var threshold: Double
    public let requiredSamples: Int
    public let cooldown: TimeInterval
    public private(set) var consecutive = 0
    public private(set) var lastFired: Date?

    public init(threshold: Double, requiredSamples: Int = 3, cooldown: TimeInterval = 300) {
        self.threshold = threshold
        self.requiredSamples = requiredSamples
        self.cooldown = cooldown
    }

    public mutating func feed(load: Double, now: Date) -> Bool {
        guard load >= threshold else {
            consecutive = 0
            return false
        }
        consecutive += 1
        guard consecutive >= requiredSamples else { return false }
        if let lastFired, now.timeIntervalSince(lastFired) < cooldown { return false }
        lastFired = now
        consecutive = 0
        return true
    }
}

/// Which folders in ~/Library/Caches may be deleted.
public enum CachePolicy {
    /// Only bundle-id-named folders of third-party apps that are not running.
    public static func isEligible(folderName: String, runningBundleIDs: Set<String>) -> Bool {
        guard folderName.contains("."), !folderName.hasPrefix(".") else { return false }
        let lowered = folderName.lowercased()
        guard !lowered.hasPrefix("com.apple.") else { return false }
        return !runningBundleIDs.contains { $0.lowercased() == lowered }
    }
}
