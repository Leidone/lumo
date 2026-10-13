import Foundation

/// One row of `ps` output.
public struct ProcessRecord: Equatable, Sendable {
    public let pid: Int32
    public let uid: UInt32
    public let cpuPercent: Double
    public let residentBytes: UInt64
    /// Controlling terminal, `nil` when the process has none (`??`).
    public let tty: String?
    public let path: String

    public init(pid: Int32, uid: UInt32, cpuPercent: Double, residentBytes: UInt64, tty: String?, path: String) {
        self.pid = pid
        self.uid = uid
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
        self.tty = tty
        self.path = path
    }

    public var name: String { (path as NSString).lastPathComponent }
}

/// Parses output of `ps -axww -o pid=,uid=,pcpu=,rss=,tty=,comm=`.
public enum PSParser {
    public static let arguments = ["-axww", "-o", "pid=,uid=,pcpu=,rss=,tty=,comm="]

    public static func parse(_ output: String) -> [ProcessRecord] {
        output.split(whereSeparator: \.isNewline).compactMap(parseLine)
    }

    static func parseLine(_ line: Substring) -> ProcessRecord? {
        let fields = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
        guard fields.count == 6,
              let pid = Int32(fields[0]),
              let uid = UInt32(fields[1]),
              let cpu = Double(fields[2].replacingOccurrences(of: ",", with: ".")),
              let rssKB = UInt64(fields[3])
        else { return nil }

        let path = fields[5].trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        let tty = fields[4] == "??" ? nil : String(fields[4])
        return ProcessRecord(pid: pid, uid: uid, cpuPercent: cpu, residentBytes: rssKB * 1024, tty: tty, path: path)
    }
}
