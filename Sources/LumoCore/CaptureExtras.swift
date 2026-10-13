import CoreGraphics
import Foundation

/// Joins the frames of a scrolling screenshot: each row of pixels is reduced to a signature, and the
/// new frame is attached where its top rows repeat the previous frame's bottom rows.
public enum ScrollStitcher {
    /// How many rows at the top of `next` are already at the bottom of `previous`, or nil when they don't line up.
    public static func overlap(previous: [UInt64], next: [UInt64], minimum: Int) -> Int? {
        guard let first = next.first, !previous.isEmpty else { return nil }
        let limit = min(previous.count, next.count)
        // Candidates: positions in `previous` holding `next`'s first row, largest overlap first.
        for start in previous.indices where previous[start] == first {
            let length = previous.count - start
            guard length >= minimum, length <= limit else { continue }
            if previous[start...].elementsEqual(next.prefix(length)) { return length }
        }
        return nil
    }
}

/// Which parts of a recording survive trimming and cuts, and where an edited moment came from.
public enum EditRanges {
    public struct Range: Equatable, Sendable {
        public let start: Double
        public let end: Double

        public init(start: Double, end: Double) {
            self.start = start
            self.end = end
        }

        public var length: Double { max(end - start, 0) }
    }

    public static func kept(duration: Double, trimStart: Double, trimEnd: Double, cuts: [Range]) -> [Range] {
        var ranges = [Range(start: max(trimStart, 0), end: min(trimEnd, duration))]
        for cut in cuts.sorted(by: { $0.start < $1.start }) {
            ranges = ranges.flatMap { range -> [Range] in
                guard cut.end > range.start, cut.start < range.end else { return [range] }
                return [Range(start: range.start, end: cut.start), Range(start: cut.end, end: range.end)].filter { $0.length > 0.01 }
            }
        }
        return ranges.filter { $0.length > 0.01 }
    }

    public static func total(_ ranges: [Range]) -> Double { ranges.reduce(0) { $0 + $1.length } }

    /// Time in the original recording for a time in the edited one.
    public static func sourceTime(_ time: Double, in ranges: [Range]) -> Double {
        var remaining = time
        for range in ranges {
            if remaining <= range.length { return range.start + remaining }
            remaining -= range.length
        }
        return ranges.last?.end ?? time
    }
}

/// Screen Studio–style automatic zoom: ease in towards each click, hold, ease back out.
public enum AutoZoom {
    public struct Click: Codable, Equatable, Sendable {
        public let time: Double
        /// Normalised 0…1, top-left origin.
        public let point: CGPoint

        public init(time: Double, point: CGPoint) {
            self.time = time
            self.point = point
        }
    }

    public static let maxScale = 1.6
    private static let easeIn = 0.3
    private static let hold = 1.2
    private static let easeOut = 0.4

    public static func state(at time: Double, clicks: [Click]) -> (scale: Double, center: CGPoint) {
        guard let click = clicks.last(where: { $0.time <= time + easeIn && time < $0.time + hold + easeOut }) else {
            return (1, CGPoint(x: 0.5, y: 0.5))
        }
        let since = time - (click.time - easeIn)
        let progress: Double
        if since < easeIn {
            progress = smooth(since / easeIn)
        } else if time < click.time + hold {
            progress = 1
        } else {
            progress = 1 - smooth((time - click.time - hold) / easeOut)
        }
        let scale = 1 + (maxScale - 1) * progress
        return (scale, progress > 0 ? click.point : CGPoint(x: 0.5, y: 0.5))
    }

    private static func smooth(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
