import AppKit
import SwiftUI

enum Format {
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private static let rateFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    static func rate(_ bytesPerSecond: Double) -> String {
        rateFormatter.string(fromByteCount: Int64(max(bytesPerSecond, 0))) + "/s"
    }

    /// Menu bar friendly: "840K", "1.2M".
    static func compactRate(_ bytesPerSecond: Double) -> String {
        let units = [(1_000_000_000.0, "G"), (1_000_000.0, "M"), (1_000.0, "K")]
        for (scale, suffix) in units where bytesPerSecond >= scale {
            let value = bytesPerSecond / scale
            return (value < 10 ? String(format: "%.1f", value) : String(Int(value))) + suffix
        }
        return "\(Int(bytesPerSecond))B"
    }

    static func duration(minutes: Int, _ t: Localizer) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return t("\(rest) мин", "\(rest)m")
        case (_, 0): return t("\(hours) ч", "\(hours)h")
        default: return t("\(hours) ч \(rest) мин", "\(hours)h \(rest)m")
        }
    }
}

// MARK: - Glass

/// Liquid Glass on macOS 26+, a vibrant material elsewhere.
struct GlassBackground<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 0.6))
        }
    }
}

extension View {
    func glass<S: Shape>(in shape: S) -> some View { modifier(GlassBackground(shape: shape)) }

    /// Cards gently shrink and fade as they scroll out of view, like on iOS.
    func scrollFade() -> some View {
        scrollTransition(.animated(.spring(response: 0.4, dampingFraction: 0.85))) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.35)
                .scaleEffect(phase.isIdentity ? 1 : 0.94, anchor: phase.value < 0 ? .bottom : .top)
                .blur(radius: phase.isIdentity ? 0 : 1.5)
        }
    }

    /// Staggered entrance: each element rises into place a beat after the previous one.
    func appear(order: Int) -> some View { modifier(AppearModifier(order: order)) }
}

private struct AppearModifier: ViewModifier {
    let order: Int
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 14)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(Double(order) * 0.045)) {
                    visible = true
                }
            }
            .onDisappear { visible = false }
    }
}

// MARK: - Cards

/// Rounded card with a soft top highlight and a hover lift.
struct LumoCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    @State private var hovering = false

    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(LinearGradient(colors: [Palette.navyLight.color.opacity(hovering ? 0.75 : 0.55),
                                                           Color.white.opacity(hovering ? 0.06 : 0.035)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [Palette.periwinkle.color.opacity(0.28), Color.white.opacity(0.02)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.7))
            .shadow(color: .black.opacity(hovering ? 0.16 : 0.06), radius: hovering ? 14 : 6, y: hovering ? 6 : 2)
            .scaleEffect(hovering ? 1.012 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: hovering)
            .onHover { hovering = $0 }
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.system(size: 13, weight: .bold, design: .rounded))
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.horizontal, 4)
    }
}

/// System Settings–style icon: a white symbol on a gradient rounded square.
struct IconBadge: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white))
            .shadow(color: (colors.last ?? .clear).opacity(0.35), radius: 4, y: 2)
    }
}

/// A row inside a settings card: badge, title, subtitle and a trailing control.
struct SettingRow<Trailing: View>: View {
    let symbol: String
    let colors: [Color]
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, colors: colors)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                if let subtitle {
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

struct SettingToggle: View {
    let symbol: String
    let colors: [Color]
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(symbol: symbol, colors: colors, title: title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn.animation(.spring(response: 0.3, dampingFraction: 0.8)))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The deep navy field behind the popover: indigo and blue at the top, violet to the right, plum below.
/// Under real strain a faint red warms the bottom corner.
struct AmbientBackground: View {
    let level: Int

    var body: some View {
        ZStack {
            Palette.navyDeep.color
            Group {
                if #available(macOS 15.0, *) {
                    MeshGradient(width: 3, height: 3, points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.55, 0.45], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1],
                    ], colors: colors)
                } else {
                    LinearGradient(colors: [Palette.navyLight.color, Palette.navy.color, Palette.plum.color],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }
        .animation(.easeInOut(duration: 1.4), value: level)
        .allowsHitTesting(false)
    }

    private var colors: [Color] {
        let corner = level >= 2 ? Palette.red.color.opacity(0.28) : Palette.plum.color
        return [
            Palette.navyLight.color, Palette.indigo.color.opacity(0.32), Palette.purple.color.opacity(0.28),
            Palette.blue.color.opacity(0.16), Palette.navy.color, Palette.plum.color.opacity(0.85),
            Palette.navy.color, Palette.navyLight.color.opacity(0.7), corner,
        ]
    }
}

/// Dark blue glass for floating panels (Command Bar, Quick panel, switcher…).
struct NavyGlass<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background(shape.fill(Palette.panelFill))
            .background(shape.fill(.ultraThinMaterial))
            .overlay(shape.strokeBorder(LinearGradient(colors: [Palette.periwinkle.color.opacity(0.35), Color.white.opacity(0.04)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func navyGlass<S: InsettableShape>(in shape: S) -> some View { modifier(NavyGlass(shape: shape)) }
}

/// Apple Intelligence–style glow that runs around the edge while Lumo is working.
struct IntelligenceGlow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.isPopoverVisible)) { timeline in
            let angle = Angle.degrees((timeline.date.timeIntervalSinceReferenceDate * 120).truncatingRemainder(dividingBy: 360))
            let gradient = AngularGradient(colors: Palette.rainbowLoop.map(\.color), center: .center, angle: angle)
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            ZStack {
                shape.strokeBorder(gradient, lineWidth: 2.5)
                shape.strokeBorder(gradient, lineWidth: 8).blur(radius: 10).opacity(0.75)
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
