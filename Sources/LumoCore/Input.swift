import CoreGraphics
import Foundation

// MARK: - Window layout

public enum WindowAction: String, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird
    case maximize, center
}

/// Pure geometry in a top-left-origin coordinate space (the one the Accessibility API uses).
public enum WindowLayout {
    public static func frame(for action: WindowAction, in visible: CGRect, current: CGRect) -> CGRect {
        let x = visible.minX, y = visible.minY, w = visible.width, h = visible.height
        let halfW = (w / 2).rounded(.down), halfH = (h / 2).rounded(.down), third = (w / 3).rounded(.down)
        switch action {
        case .leftHalf: return CGRect(x: x, y: y, width: halfW, height: h)
        case .rightHalf: return CGRect(x: x + w - halfW, y: y, width: halfW, height: h)
        case .topHalf: return CGRect(x: x, y: y, width: w, height: halfH)
        case .bottomHalf: return CGRect(x: x, y: y + h - halfH, width: w, height: halfH)
        case .topLeft: return CGRect(x: x, y: y, width: halfW, height: halfH)
        case .topRight: return CGRect(x: x + w - halfW, y: y, width: halfW, height: halfH)
        case .bottomLeft: return CGRect(x: x, y: y + h - halfH, width: halfW, height: halfH)
        case .bottomRight: return CGRect(x: x + w - halfW, y: y + h - halfH, width: halfW, height: halfH)
        case .leftThird: return CGRect(x: x, y: y, width: third, height: h)
        case .centerThird: return CGRect(x: x + third, y: y, width: third, height: h)
        case .rightThird: return CGRect(x: x + w - third, y: y, width: third, height: h)
        case .maximize: return visible
        case .center:
            let size = CGSize(width: min(current.width, w), height: min(current.height, h))
            return CGRect(x: (x + (w - size.width) / 2).rounded(), y: (y + (h - size.height) / 2).rounded(),
                          width: size.width, height: size.height)
        }
    }

    /// Where a window dragged to `point` should snap, if anywhere. `screen` is the full screen frame.
    public static func snapAction(for point: CGPoint, in screen: CGRect, margin: CGFloat = 6, corner: CGFloat = 60) -> WindowAction? {
        let nearLeft = point.x <= screen.minX + margin
        let nearRight = point.x >= screen.maxX - margin
        let nearTop = point.y <= screen.minY + margin
        let nearBottom = point.y >= screen.maxY - margin
        let inTopBand = point.y <= screen.minY + corner
        let inBottomBand = point.y >= screen.maxY - corner
        switch true {
        case nearLeft && inTopBand: return .topLeft
        case nearLeft && inBottomBand: return .bottomLeft
        case nearRight && inTopBand: return .topRight
        case nearRight && inBottomBand: return .bottomRight
        case nearLeft: return .leftHalf
        case nearRight: return .rightHalf
        case nearTop: return .maximize
        case nearBottom: return nil
        default: return nil
        }
    }
}

// MARK: - Quit protection

/// Decides whether a guarded shortcut (⌘Q / ⌘W) goes through.
/// Hold mode: the key must stay down for `holdDuration`. Double mode: press twice within `doubleWindow`.
public struct QuitGuard: Equatable, Sendable {
    public enum Mode: String, Sendable { case hold, double }

    public enum Decision: Equatable, Sendable {
        /// Swallow the key and show the hint; `progress` is how far the hold has come (0…1).
        case block(progress: Double)
        case allow
    }

    public let mode: Mode
    public let holdDuration: TimeInterval
    public let doubleWindow: TimeInterval
    private var pressStart: TimeInterval?
    private var lastTap: TimeInterval?
    private var fired = false

    public init(mode: Mode, holdDuration: TimeInterval = 0.6, doubleWindow: TimeInterval = 0.5) {
        self.mode = mode
        self.holdDuration = holdDuration
        self.doubleWindow = doubleWindow
    }

    public mutating func keyDown(isRepeat: Bool, at time: TimeInterval) -> Decision {
        switch mode {
        case .hold:
            if !isRepeat {
                pressStart = time
                fired = false
                return .block(progress: 0)
            }
            guard let start = pressStart, !fired else { return .block(progress: fired ? 1 : 0) }
            let progress = min((time - start) / holdDuration, 1)
            if progress >= 1 {
                fired = true
                return .allow
            }
            return .block(progress: progress)
        case .double:
            guard !isRepeat else { return .block(progress: 0) }
            if let last = lastTap, time - last <= doubleWindow {
                lastTap = nil
                return .allow
            }
            lastTap = time
            return .block(progress: 0.5)
        }
    }

    public mutating func keyUp() {
        pressStart = nil
        fired = false
    }
}

// MARK: - Smooth scrolling

/// Turns coarse mouse-wheel notches into a glide: each tick emits a share of the remaining distance.
public struct ScrollGlide: Equatable, Sendable {
    public let response: Double
    public private(set) var remaining: Double = 0

    /// `response` is the share of the remaining distance emitted per 1/120 s frame (0.05 slow … 0.5 snappy).
    public init(response: Double) {
        self.response = min(max(response, 0.02), 1)
    }

    public mutating func add(_ distance: Double) {
        // Reversing direction cancels the leftover glide instead of fighting it.
        if remaining != 0, (remaining > 0) != (distance > 0) { remaining = 0 }
        remaining += distance
    }

    /// The delta to emit this frame; 0 when the glide is done.
    public mutating func step() -> Double {
        guard abs(remaining) >= 0.5 else {
            let rest = remaining
            remaining = 0
            return rest.rounded()
        }
        let delta = remaining * response
        let emitted = delta.magnitude < 1 ? (remaining > 0 ? 1 : -1) : delta.rounded()
        remaining -= emitted
        return emitted
    }

    public var isIdle: Bool { remaining == 0 }
}

// MARK: - App switcher

/// Most-recently-used ordering of app identifiers.
public enum RecentApps {
    public static func activating(_ id: String, in list: [String], limit: Int = 50) -> [String] {
        Array(([id] + list.filter { $0 != id }).prefix(limit))
    }

    /// Keeps MRU order for apps still running, appending newly seen ones at the end.
    public static func ordered(running: [String], recent: [String]) -> [String] {
        let alive = Set(running)
        let known = recent.filter { alive.contains($0) }
        return known + running.filter { !known.contains($0) }
    }
}
