import Foundation

/// Fixed-length rolling window of samples, oldest first. Appending returns a new value.
public struct MetricHistory: Equatable, Sendable {
    public let capacity: Int
    public let values: [Double]

    public init(capacity: Int, values: [Double] = []) {
        let limit = max(capacity, 1)
        self.capacity = limit
        self.values = Array(values.suffix(limit))
    }

    public func appending(_ value: Double) -> MetricHistory {
        MetricHistory(capacity: capacity, values: values + [value])
    }

    public var latest: Double? { values.last }
    public var peak: Double { values.max() ?? 0 }
}

/// Cumulative byte counters of the physical network interfaces at one moment.
public struct NetworkCounters: Equatable, Sendable {
    public let received: UInt64
    public let sent: UInt64
    public let timestamp: TimeInterval

    public init(received: UInt64, sent: UInt64, timestamp: TimeInterval) {
        self.received = received
        self.sent = sent
        self.timestamp = timestamp
    }
}

public struct NetworkDelta: Equatable, Sendable {
    public let receivedBytes: UInt64
    public let sentBytes: UInt64
    public let downBytesPerSecond: Double
    public let upBytesPerSecond: Double

    public static let zero = NetworkDelta(receivedBytes: 0, sentBytes: 0, downBytesPerSecond: 0, upBytesPerSecond: 0)

    /// Counters can go backwards when an interface resets; that interval counts as zero.
    public static func between(_ previous: NetworkCounters, _ current: NetworkCounters) -> NetworkDelta {
        let elapsed = current.timestamp - previous.timestamp
        guard elapsed > 0 else { return .zero }
        let received = current.received >= previous.received ? current.received - previous.received : 0
        let sent = current.sent >= previous.sent ? current.sent - previous.sent : 0
        return NetworkDelta(receivedBytes: received, sentBytes: sent,
                            downBytesPerSecond: Double(received) / elapsed, upBytesPerSecond: Double(sent) / elapsed)
    }
}

/// Internal battery state from IOKit.
public struct BatteryReading: Equatable, Sendable {
    public let charge: Double
    public let isCharging: Bool
    public let isPluggedIn: Bool
    /// Minutes to empty (on battery) or to full (charging); nil while macOS is still estimating.
    public let minutesRemaining: Int?
    public let cycleCount: Int?
    public let maxCapacity: Int?
    public let designCapacity: Int?
    public let watts: Double?

    public init(charge: Double, isCharging: Bool, isPluggedIn: Bool, minutesRemaining: Int?, cycleCount: Int?,
                maxCapacity: Int?, designCapacity: Int?, watts: Double?) {
        self.charge = min(max(charge, 0), 1)
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.minutesRemaining = minutesRemaining.flatMap { $0 > 0 ? $0 : nil }
        self.cycleCount = cycleCount
        self.maxCapacity = maxCapacity
        self.designCapacity = designCapacity
        self.watts = watts
    }

    /// Full-charge capacity relative to design. Only trusted when both values are in mAh
    /// (Apple Silicon reports "MaxCapacity" as a 0–100 percentage).
    public var health: Double? {
        guard let maxCapacity, let designCapacity, maxCapacity > 100, designCapacity > 100 else { return nil }
        return min(Double(maxCapacity) / Double(designCapacity), 1)
    }
}

/// A TCP port some process is listening on.
public struct ListeningPort: Identifiable, Equatable, Sendable {
    public let pid: Int32
    public let command: String
    public let port: Int
    public let address: String

    public var id: String { "\(pid):\(port)" }
    public var isLocalOnly: Bool { address.hasPrefix("127.") || address == "[::1]" || address == "localhost" }

    public init(pid: Int32, command: String, port: Int, address: String) {
        self.pid = pid
        self.command = command
        self.port = port
        self.address = address
    }
}

/// Parses `lsof -nP -iTCP -sTCP:LISTEN -F pcn` field output.
public enum LsofParser {
    public static let arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]

    public static func parse(_ output: String) -> [ListeningPort] {
        var result: [ListeningPort] = []
        var seen = Set<String>()
        var pid: Int32?
        var command = ""

        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value)
                command = ""
            case "c":
                command = value
            case "n":
                guard let pid, let entry = endpoint(value) else { continue }
                let port = ListeningPort(pid: pid, command: command, port: entry.port, address: entry.address)
                if seen.insert(port.id).inserted { result.append(port) }
            default:
                continue
            }
        }
        return result.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    private static func endpoint(_ value: String) -> (address: String, port: Int)? {
        guard let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) else { return nil }
        return (String(value[..<colon]), port)
    }
}
