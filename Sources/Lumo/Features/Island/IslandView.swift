import AppKit
import LumoCore
import SwiftUI

/// The notch silhouette: concave "ears" where it meets the top edge, rounded bottom corners.
struct NotchShape: Shape {
    static let earRadius: CGFloat = 7
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let ear = Self.earRadius
        let radius = min(bottomRadius, (rect.height - ear) / 1, (rect.width - ear * 2) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + ear, y: rect.minY + ear), control: CGPoint(x: rect.minX + ear, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + ear + radius, y: rect.maxY), control: CGPoint(x: rect.minX + ear, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - ear - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - ear, y: rect.maxY - radius), control: CGPoint(x: rect.maxX - ear, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - ear, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct IslandView: View {
    @ObservedObject var island: DynamicIsland
    @ObservedObject var nowPlaying: NowPlayingService

    init(island: DynamicIsland) {
        self.island = island
        nowPlaying = island.nowPlaying
    }

    var body: some View {
        let mode = island.mode
        let size = island.shapeSize(for: mode)
        let shape = NotchShape(bottomRadius: mode == .expanded ? 30 : mode == .peek ? 20 : island.notchSize.height * 0.42)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(Color.black)
                    .shadow(color: .black.opacity(mode == .expanded || mode == .peek ? 0.5 : 0), radius: 16, y: 6)
                    .opacity(island.hasNotch || mode != .idle ? 1 : 0)
                content(mode)
                    .padding(.horizontal, NotchShape.earRadius)
                    .frame(width: size.width, height: size.height, alignment: .top)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .contentShape(shape)
            Spacer(minLength: 0)
        }
        .frame(width: DynamicIsland.panelSize.width, height: DynamicIsland.panelSize.height, alignment: .top)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: mode)
    }

    @ViewBuilder
    private func content(_ mode: DynamicIsland.Mode) -> some View {
        switch mode {
        case .idle:
            Color.clear
        case .compact:
            compact.transition(.opacity.combined(with: .scale(scale: 0.9)))
        case .peek:
            peek.transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
        case .expanded:
            IslandExpanded(island: island, nowPlaying: nowPlaying)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)).animation(.spring(response: 0.4).delay(0.06)),
                                        removal: .opacity.animation(.easeOut(duration: 0.12))))
        }
    }

    // MARK: Compact — live activity beside the notch

    private var compact: some View {
        HStack(spacing: 0) {
            leftWing.frame(width: DynamicIsland.wingWidth)
            Spacer(minLength: island.notchSize.width)
            rightWing.frame(width: DynamicIsland.wingWidth)
        }
        .frame(height: island.notchSize.height)
    }

    @ViewBuilder private var leftWing: some View {
        if island.model?.recorder.isRecording == true {
            Circle().fill(Palette.red.color).frame(width: 9, height: 9).shadow(color: Palette.red.color, radius: 4)
        } else if island.timerEnd != nil {
            Image(systemName: "timer").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.orange.color)
        } else if let track = nowPlaying.track, track.state.isPlaying {
            ArtworkView(image: nowPlaying.artwork, bundleID: track.bundleID, size: 20, radius: 5)
        } else if !island.downloads.active.isEmpty {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 13)).foregroundStyle(Palette.blue.color)
        } else if island.model?.keepAwake.isOn == true {
            Image(systemName: "cup.and.saucer.fill").font(.system(size: 12)).foregroundStyle(Palette.orange.color)
        }
    }

    @ViewBuilder private var rightWing: some View {
        if let started = island.model?.recorder.startedAt {
            Text(started, style: .timer).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Palette.red.color).lineLimit(1).minimumScaleFactor(0.7)
        } else if let end = island.timerEnd {
            Text(end, style: .timer).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Palette.orange.color).lineLimit(1).minimumScaleFactor(0.7)
        } else if nowPlaying.track?.state.isPlaying == true {
            EqualizerBars(color: nowPlaying.accent, levels: island.levelSource).frame(width: 16, height: 14)
        } else if let download = island.downloads.active.first {
            DownloadRing(progress: download.progress)
        }
    }

    // MARK: Peek — a short banner (new track, timer done…)

    @ViewBuilder private var peek: some View {
        if let peek = island.peek {
            VStack(spacing: 0) {
                Spacer().frame(height: island.notchSize.height)
                HStack(spacing: 10) {
                    if peek.symbol == "music.note", let track = nowPlaying.track {
                        ArtworkView(image: nowPlaying.artwork, bundleID: track.bundleID, size: 28, radius: 7)
                    } else {
                        Image(systemName: peek.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(peek.tint)
                            .frame(width: 28)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(peek.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        if !peek.subtitle.isEmpty {
                            Text(peek.subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if peek.symbol == "music.note" { EqualizerBars(color: nowPlaying.accent).frame(width: 16, height: 14) }
                }
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// A small progress ring for a download (indeterminate when the size is unknown).
struct DownloadRing: View {
    let progress: Double?

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 2.5)
            Circle().trim(from: 0, to: progress ?? 0.3)
                .stroke(Palette.blue.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
        }
        .frame(width: 14, height: 14)
    }
}

/// Album art, or the playing app's icon when the player shares none.
struct ArtworkView: View {
    let image: NSImage?
    let bundleID: String?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                let path = bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path }
                Image(nsImage: path.map { IconCache.icon(for: $0) } ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) ?? NSImage())
                    .resizable().aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Bouncing bars, animated by Core Animation in the render server (no SwiftUI redraws).
struct EqualizerBars: NSViewRepresentable {
    var color: Color
    /// Live bands from the audio meter; nil keeps the built-in animation.
    var levels: (() -> [Float])?

    func makeNSView(context: Context) -> EqualizerLayerView { EqualizerLayerView() }

    func updateNSView(_ view: EqualizerLayerView, context: Context) {
        view.setColor(NSColor(color))
        view.setLevelSource(levels)
    }

    static func dismantleNSView(_ view: EqualizerLayerView, coordinator: ()) { view.setLevelSource(nil) }
}

final class EqualizerLayerView: NSView {
    private static let durations: [CFTimeInterval] = [0.42, 0.55, 0.37, 0.5]
    private var bars: [CALayer] = []
    private var levelTimer: Timer?
    private var source: (() -> [Float])?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 14))
        wantsLayer = true
        for index in 0..<4 {
            let bar = CALayer()
            bar.cornerRadius = 1.25
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            layer?.addSublayer(bar)
            bars.append(bar)
            let pulse = CABasicAnimation(keyPath: "transform.scale.y")
            pulse.fromValue = 0.25
            pulse.toValue = 1
            pulse.duration = Self.durations[index]
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.timeOffset = Double(index) * 0.13
            bar.add(pulse, forKey: "pulse")
        }
        setColor(.systemPink)
    }

    private static func pulse(_ index: Int) -> CABasicAnimation {
        let pulse = CABasicAnimation(keyPath: "transform.scale.y")
        pulse.fromValue = 0.25
        pulse.toValue = 1
        pulse.duration = durations[index]
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.timeOffset = Double(index) * 0.13
        return pulse
    }

    /// Switches between the canned animation and real audio levels (read 30 times a second).
    func setLevelSource(_ next: (() -> [Float])?) {
        guard (next == nil) != (source == nil) else {
            source = next
            return
        }
        source = next
        levelTimer?.invalidate()
        levelTimer = nil
        if next == nil {
            for (index, bar) in bars.enumerated() {
                bar.setAffineTransform(.identity)
                bar.add(Self.pulse(index), forKey: "pulse")
            }
            return
        }
        bars.forEach { $0.removeAnimation(forKey: "pulse") }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyLevels() }
        }
        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
    }

    private func applyLevels() {
        guard let levels = source?(), window?.isVisible == true else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(1.0 / 30)
        for (index, bar) in bars.enumerated() where index < levels.count {
            bar.setAffineTransform(CGAffineTransform(scaleX: 1, y: CGFloat(max(levels[index], 0.12))))
        }
        CATransaction.commit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let width: CGFloat = 2.5
        let gap = (bounds.width - width * 4) / 3
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(index) * (width + gap) + width / 2, y: 0)
        }
    }

    func setColor(_ color: NSColor) {
        bars.forEach { $0.backgroundColor = color.cgColor }
    }
}
