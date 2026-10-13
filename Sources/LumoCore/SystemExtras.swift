import Foundation

// MARK: - Energy impact

public struct EnergyEntry: Equatable, Sendable {
    public let pid: Int32
    public let name: String
    public let impact: Double

    public init(pid: Int32, name: String, impact: Double) {
        self.pid = pid
        self.name = name
        self.impact = impact
    }
}

/// Parses `top -l 2 -o power -stats pid,command,power`. The first sample has no deltas,
/// so only the last one counts; idle processes (0.0) are dropped.
public enum PowerTopParser {
    public static let arguments = ["-l", "2", "-s", "1", "-n", "12", "-o", "power", "-stats", "pid,command,power"]

    public static func parse(_ output: String) -> [EnergyEntry] {
        let lines = output.components(separatedBy: .newlines)
        guard let header = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("PID") }) else { return [] }
        return lines[(header + 1)...].compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = Int32(parts[0]),
                  let impact = Double(parts[parts.count - 1].replacingOccurrences(of: ",", with: ".")), impact > 0
            else { return nil }
            let name = parts[1..<(parts.count - 1)].joined(separator: " ")
            return EnergyEntry(pid: pid, name: name, impact: impact)
        }
    }
}

// MARK: - Speed test

/// The result of Apple's own `networkQuality -c` (JSON output).
public struct SpeedTestResult: Equatable, Sendable {
    public let downloadMbps: Double
    public let uploadMbps: Double
    /// Round trips per minute under load (higher is better), when reported.
    public let responsiveness: Double?
    public let latencyMilliseconds: Double?

    public init(downloadMbps: Double, uploadMbps: Double, responsiveness: Double?, latencyMilliseconds: Double?) {
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.responsiveness = responsiveness
        self.latencyMilliseconds = latencyMilliseconds
    }

    public static func parse(_ data: Data) -> SpeedTestResult? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let down = (object["dl_throughput"] as? NSNumber)?.doubleValue,
              let up = (object["ul_throughput"] as? NSNumber)?.doubleValue
        else { return nil }
        return SpeedTestResult(downloadMbps: down / 1_000_000, uploadMbps: up / 1_000_000,
                               responsiveness: (object["responsiveness"] as? NSNumber)?.doubleValue,
                               latencyMilliseconds: (object["base_rtt"] as? NSNumber)?.doubleValue)
    }
}

// MARK: - Fan curve

/// Temperature → fan speed, linear between points and flat outside them.
public struct FanCurve: Codable, Equatable, Sendable {
    public struct Point: Codable, Equatable, Sendable {
        public let celsius: Double
        /// 0 = the fan's minimum speed, 1 = its maximum.
        public let fraction: Double

        public init(celsius: Double, fraction: Double) {
            self.celsius = celsius
            self.fraction = min(max(fraction, 0), 1)
        }
    }

    public static let balanced = FanCurve(points: [Point(celsius: 55, fraction: 0), Point(celsius: 75, fraction: 0.45), Point(celsius: 92, fraction: 1)])

    public let points: [Point]

    public init(points: [Point]) {
        self.points = points.sorted { $0.celsius < $1.celsius }
    }

    public func fraction(at celsius: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if celsius <= first.celsius { return first.fraction }
        if celsius >= last.celsius { return last.fraction }
        for (lower, upper) in zip(points, points.dropFirst()) where celsius <= upper.celsius {
            let span = upper.celsius - lower.celsius
            return span > 0 ? lower.fraction + (upper.fraction - lower.fraction) * (celsius - lower.celsius) / span : upper.fraction
        }
        return last.fraction
    }

    public func rpm(at celsius: Double, min: Double, max: Double) -> Double {
        (min + (max - min) * fraction(at: celsius)).rounded()
    }
}
