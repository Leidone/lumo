import SwiftUI

/// Apple Fitness–style concentric rings: each ring has a tinted track and a gradient arc.
struct ActivityRings: View {
    struct Ring: Identifiable {
        let id: String
        let value: Double
        let colors: [Color]
    }

    let rings: [Ring]
    var lineWidth: CGFloat = 13
    var gap: CGFloat = 3

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                RingArc(value: ring.value, colors: ring.colors, lineWidth: lineWidth)
                    .padding(CGFloat(index) * (lineWidth + gap))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(8)
        .drawingGroup()
        .padding(-8)
    }
}

private struct RingArc: View {
    let value: Double
    let colors: [Color]
    let lineWidth: CGFloat

    var body: some View {
        let tint = colors.last ?? .accentColor
        ZStack {
            Circle().stroke(tint.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(min(value, 1), 0.002))
                .stroke(
                    AngularGradient(colors: colors, center: .center, startAngle: .degrees(0),
                                    endAngle: .degrees(360 * max(value, 0.08))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.55), radius: 6)
        }
        .padding(lineWidth / 2)
        .animation(.spring(response: 1, dampingFraction: 0.78), value: value)
    }
}

/// Smooth area chart for 0…1 values, with a glowing "now" dot.
struct Sparkline: View {
    let values: [Double]
    let colors: [Color]
    var showsDot = true

    var body: some View {
        GeometryReader { geometry in
            let points = Self.points(for: values, in: geometry.size)
            let tint = colors.last ?? .accentColor
            ZStack {
                Self.area(points, height: geometry.size.height)
                    .fill(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                Self.curve(points)
                    .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                if showsDot, let last = points.last {
                    Circle().fill(tint).frame(width: 5, height: 5)
                        .shadow(color: tint, radius: 4)
                        .position(last)
                }
            }
        }
        .drawingGroup()
        .animation(.easeOut(duration: 0.5), value: values)
    }

    private static func points(for values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step, y: size.height * (1 - CGFloat(min(max(value, 0), 1))) * 0.92 + size.height * 0.04)
        }
    }

    /// Quadratic curves through segment midpoints — smooth, without overshoot.
    private static func curve(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
                path.addQuadCurve(to: mid, control: previous)
                if index == points.count - 1 { path.addQuadCurve(to: current, control: mid) }
            }
        }
    }

    private static func area(_ points: [CGPoint], height: CGFloat) -> Path {
        var path = curve(points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.addLine(to: CGPoint(x: first.x, y: height))
        path.closeSubpath()
        return path
    }
}

/// One slim vertical bar per CPU core.
struct CoreBars: View {
    let loads: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(loads.enumerated()), id: \.offset) { _, load in
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(LinearGradient(colors: [Palette.azure.color, Palette.indigo.color, Palette.purple.color],
                                                 startPoint: .bottom, endPoint: .top))
                            .frame(height: max(geometry.size.height * CGFloat(load), 3))
                    }
                }
                .frame(maxWidth: 10)
            }
        }
        .frame(maxWidth: .infinity)
        .drawingGroup()
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: loads)
    }
}

/// Horizontal capsule meter with a gradient fill.
struct CapsuleMeter: View {
    let value: Double
    let colors: [Color]
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geometry.size.width * CGFloat(min(max(value, 0), 1)), height))
                    .shadow(color: (colors.last ?? .clear).opacity(0.4), radius: 3)
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: value)
    }
}
