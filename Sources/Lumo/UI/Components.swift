import AppKit
import SwiftUI

/// The custom "resource dial": a gradient track that reveals more color as it grows.
/// A light haptic tick marks every 10%.
struct GradientSlider: View {
    @Binding var value: Double
    let colors: [Color]
    let label: String

    private let knob: CGFloat = 22
    private let trackHeight: CGFloat = 7
    private let step = 0.05
    @State private var dragging = false

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - knob, 1)
            let offset = CGFloat(value) * travel
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1)).frame(height: trackHeight)
                LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
                    .frame(height: trackHeight)
                    .mask(alignment: .leading) { Capsule().frame(width: offset + knob / 2) }
                    .shadow(color: (colors.last ?? .accentColor).opacity(0.45), radius: 5)
                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.25), radius: dragging ? 5 : 2, y: 1)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.06)))
                    .scaleEffect(dragging ? 1.15 : 1)
                    .offset(x: offset)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: dragging)
            }
            .frame(height: knob)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    dragging = true
                    let next = min(max(Double((drag.location.x - knob / 2) / travel), 0), 1)
                    if Int(next * 10) != Int(value * 10) {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                    value = next
                }
                .onEnded { _ in dragging = false })
        }
        .frame(height: knob)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(Format.percent(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, 1)
            case .decrement: value = max(value - step, 0)
            @unknown default: break
            }
        }
    }
}

/// Big gradient call-to-action with an apple.com-style rotating glow.
struct OptimizeButton: View {
    @EnvironmentObject private var model: AppModel
    let isBusy: Bool
    let targets: Int
    let title: String
    let busyTitle: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !(hovering || isBusy) || !model.isPopoverVisible)) { timeline in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                let angle = Angle.degrees((seconds * (isBusy ? 240 : 60)).truncatingRemainder(dividingBy: 360))
                ZStack {
                    Capsule()
                        .fill(AngularGradient(colors: Palette.rainbowLoop.map(\.color), center: .center, angle: angle))
                        .blur(radius: 16)
                        .opacity(hovering || isBusy ? 0.9 : 0.45)
                        .padding(.horizontal, 14)
                    Capsule()
                        .fill(Palette.accent)
                    Capsule()
                        .fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                    Capsule()
                        .strokeBorder(
                            AngularGradient(colors: [.white.opacity(0.9), .white.opacity(0.1), .white.opacity(0.6),
                                                     .white.opacity(0.1), .white.opacity(0.9)],
                                            center: .center, angle: angle),
                            lineWidth: 1.2)
                    label
                }
            }
            .frame(height: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(isBusy)
        .onHover { hovering = $0 }
        // A popover closed under the pointer never sends "hover ended".
        .onChange(of: model.isPopoverVisible) { _, visible in if !visible { hovering = false } }
        .keyboardShortcut(.defaultAction)
    }

    private var label: some View {
        HStack(spacing: 8) {
            if isBusy {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Image(systemName: "sparkles").symbolEffect(.pulse, isActive: hovering)
            }
            Text(isBusy ? busyTitle : title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            if !isBusy && targets > 0 {
                Text("\(targets)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.white.opacity(0.25)))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .foregroundStyle(.white)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: targets)
    }
}

/// Animated two-ring logo mirroring the menu bar icon. The rotation runs as Core Animation
/// in the render server — SwiftUI-drawn conic gradients would be re-shaded on the CPU every frame.
struct LumoGlyph: NSViewRepresentable {
    var size: CGFloat = 30
    var isBusy = false

    func makeNSView(context: Context) -> GlyphLayerView { GlyphLayerView(size: size) }

    func updateNSView(_ view: GlyphLayerView, context: Context) { view.setBusy(isBusy) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GlyphLayerView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}

final class GlyphLayerView: NSView {
    private static let idleTurn: CFTimeInterval = 10
    private static let busyTurn: CFTimeInterval = 1.6

    private let outer = CAGradientLayer()
    private let inner = CAGradientLayer()
    private var isBusy: Bool?

    init(size: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        addRing(outer, colors: Palette.cpuLoop, inset: size * 0.135, lineWidth: size * 0.13, bounds: bounds)
        addRing(inner, colors: Palette.memoryLoop, inset: size * 0.335, lineWidth: size * 0.13, bounds: bounds)
        layer?.shadowColor = Palette.purple.cgColor
        layer?.shadowOpacity = 0.5
        layer?.shadowRadius = size / 5
        layer?.shadowOffset = .zero
        setBusy(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { frame.size }

    func setBusy(_ busy: Bool) {
        guard busy != isBusy else { return }
        isBusy = busy
        let turn = busy ? Self.busyTurn : Self.idleTurn
        outer.add(Self.spin(turn, clockwise: true), forKey: "spin")
        inner.add(Self.spin(turn * 0.8, clockwise: false), forKey: "spin")
    }

    private func addRing(_ gradient: CAGradientLayer, colors: [PaletteColor], inset: CGFloat, lineWidth: CGFloat, bounds: CGRect) {
        gradient.type = .conic
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        gradient.colors = colors.map(\.cgColor)
        gradient.frame = bounds
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: bounds.insetBy(dx: inset, dy: inset), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = NSColor.black.cgColor
        ring.lineWidth = lineWidth
        let container = CALayer()
        container.frame = bounds
        container.mask = ring
        container.addSublayer(gradient)
        layer?.addSublayer(container)
    }

    private static func spin(_ duration: CFTimeInterval, clockwise: Bool) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = clockwise ? -2 * Double.pi : 2 * Double.pi
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }
}

struct ThermalChip: View {
    let state: ProcessInfo.ThermalState
    let t: Localizer

    var body: some View {
        Label(title, systemImage: "thermometer.medium")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.15)))
            .help(t("Температурный режим macOS", "macOS thermal state"))
            .animation(.easeInOut, value: state)
    }

    private var title: String {
        switch state {
        case .nominal: return t("Прохладно", "Cool")
        case .fair: return t("Тепло", "Warm")
        case .serious: return t("Горячо", "Hot")
        case .critical: return t("Перегрев", "Overheating")
        @unknown default: return "—"
        }
    }

    private var tint: Color {
        switch state {
        case .nominal: return Palette.green.color
        case .fair: return Palette.yellow.color
        case .serious: return Palette.orange.color
        default: return Palette.red.color
        }
    }
}

/// Generic sliding-pill segmented control (Apple Music / Fitness style).
struct PillPicker<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option == selection
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selected {
                                Capsule().fill(Color.primary.opacity(0.12))
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

enum IconCache {
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    static func icon(for path: String) -> NSImage {
        let target = enclosingBundle(of: path) ?? path
        if let hit = cache[target] { return hit }
        let image = NSWorkspace.shared.icon(forFile: target)
        cache[target] = image
        return image
    }

    private static func enclosingBundle(of path: String) -> String? {
        if path.hasSuffix(".app") { return path }
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
}
