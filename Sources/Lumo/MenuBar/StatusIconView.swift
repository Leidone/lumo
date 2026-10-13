import AppKit
import QuartzCore

/// Layer-based menu bar icon: Activity-ring style CPU (outer) and memory (inner)
/// rings with rotating Apple gradients and a pulsing health dot.
/// All motion is Core Animation running in the render server, so Lumo itself
/// stays near 0% CPU while the icon shimmers.
final class StatusIconView: NSView {
    private struct Ring {
        let track = CAShapeLayer()
        let spinner = CALayer()
        let gradient = CAGradientLayer()
        let arc = CAShapeLayer()
    }

    private enum AnimationKey {
        static let shimmer = "shimmer"
        static let spin = "spin"
        static let pulse = "pulse"
        static let flash = "flash"
    }

    private static let iconSize: CGFloat = 18
    private static let lineWidth: CGFloat = 2.3
    private static let outerRadius: CGFloat = 7.6
    private static let innerRadius: CGFloat = 4.4
    private static let padding: CGFloat = 3
    private static let textGap: CGFloat = 4
    private static let minimumArc = 0.025
    private static let busyArc = 0.32
    private static let valueAnimationDuration = 0.8
    private static let shimmerDuration: CFTimeInterval = 9
    private static let busySpinDuration: CFTimeInterval = 1.1

    private let iconLayer = CALayer()
    private let outer = Ring()
    private let inner = Ring()
    private let dot = CALayer()
    private let label = NSTextField(labelWithString: "")

    private var cpu = 0.0
    private var memory = 0.0
    private var isBusy = false
    private var isAnimated = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        setUpLayers()
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Clicks must reach the status bar button underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var preferredWidth: CGFloat {
        let text = label.stringValue
        guard !text.isEmpty else { return Self.iconSize + Self.padding * 2 }
        return Self.padding + Self.iconSize + Self.textGap + ceil(label.intrinsicContentSize.width) + Self.padding
    }

    // MARK: Updates

    func setValues(cpu: Double, memory: Double) {
        guard abs(cpu - self.cpu) > 0.004 || abs(memory - self.memory) > 0.004 else { return }
        self.cpu = cpu
        self.memory = memory
        guard !isBusy else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.valueAnimationDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        outer.arc.strokeEnd = Self.arcLength(cpu)
        inner.arc.strokeEnd = Self.arcLength(memory)
        CATransaction.commit()
    }

    func setHealth(_ color: PaletteColor) {
        guard !isBusy else { return }
        dot.backgroundColor = color.cgColor
    }

    func setText(_ text: String) {
        guard text != label.stringValue else { return }
        label.stringValue = text
        needsLayout = true
    }

    func setBusy(_ busy: Bool) {
        guard busy != isBusy else { return }
        isBusy = busy
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (ring, clockwise) in [(outer, true), (inner, false)] {
            ring.gradient.colors = (busy ? Palette.rainbowLoop : loop(for: ring)).map(\.cgColor)
            if busy {
                ring.arc.strokeEnd = Self.busyArc
                ring.spinner.add(Self.rotation(duration: Self.busySpinDuration * (clockwise ? 1 : 1.4),
                                               clockwise: clockwise), forKey: AnimationKey.spin)
            } else {
                ring.spinner.removeAnimation(forKey: AnimationKey.spin)
            }
        }
        if !busy {
            outer.arc.strokeEnd = Self.arcLength(cpu)
            inner.arc.strokeEnd = Self.arcLength(memory)
        }
        dot.backgroundColor = busy ? NSColor.white.cgColor : dot.backgroundColor
        CATransaction.commit()
    }

    /// Rings sweep to full and settle back — "done!" feedback.
    func flash() {
        for (ring, value) in [(outer, cpu), (inner, memory)] {
            let animation = CAKeyframeAnimation(keyPath: "strokeEnd")
            animation.values = [Self.arcLength(value), 1, 1, Self.arcLength(value)]
            animation.keyTimes = [0, 0.35, 0.6, 1]
            animation.duration = 1.4
            animation.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .linear),
                                         CAMediaTimingFunction(name: .easeInEaseOut)]
            ring.arc.add(animation, forKey: AnimationKey.flash)
        }
    }

    func setAnimated(_ animated: Bool) {
        guard animated != isAnimated else { return }
        isAnimated = animated
        if animated {
            outer.gradient.add(Self.rotation(duration: Self.shimmerDuration, clockwise: true), forKey: AnimationKey.shimmer)
            inner.gradient.add(Self.rotation(duration: Self.shimmerDuration * 0.8, clockwise: false), forKey: AnimationKey.shimmer)
            dot.add(Self.pulse(), forKey: AnimationKey.pulse)
        } else {
            [outer.gradient, inner.gradient].forEach { $0.removeAnimation(forKey: AnimationKey.shimmer) }
            dot.removeAnimation(forKey: AnimationKey.pulse)
        }
    }

    // MARK: Layout & appearance

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.frame = CGRect(x: Self.padding, y: (bounds.height - Self.iconSize) / 2,
                                 width: Self.iconSize, height: Self.iconSize)
        CATransaction.commit()
        let size = label.intrinsicContentSize
        label.frame = CGRect(x: Self.padding + Self.iconSize + Self.textGap, y: (bounds.height - size.height) / 2,
                             width: ceil(size.width), height: size.height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTrackColor()
    }

    // MARK: Private

    private func setUpLayers() {
        guard let root = layer else { return }
        iconLayer.frame = CGRect(x: Self.padding, y: 0, width: Self.iconSize, height: Self.iconSize)
        root.addSublayer(iconLayer)
        configure(outer, radius: Self.outerRadius, colors: Palette.cpuLoop)
        configure(inner, radius: Self.innerRadius, colors: Palette.memoryLoop)

        let dotSize: CGFloat = 2.8
        dot.frame = CGRect(x: (Self.iconSize - dotSize) / 2, y: (Self.iconSize - dotSize) / 2, width: dotSize, height: dotSize)
        dot.cornerRadius = dotSize / 2
        dot.backgroundColor = Palette.green.cgColor
        iconLayer.addSublayer(dot)
        applyTrackColor()
    }

    private func configure(_ ring: Ring, radius: CGFloat, colors: [PaletteColor]) {
        let bounds = CGRect(x: 0, y: 0, width: Self.iconSize, height: Self.iconSize)
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius,
                    startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)

        for shape in [ring.track, ring.arc] {
            shape.frame = bounds
            shape.path = path
            shape.fillColor = nil
            shape.lineWidth = Self.lineWidth
            shape.lineCap = .round
        }
        ring.arc.strokeColor = NSColor.black.cgColor
        ring.arc.strokeEnd = Self.arcLength(0)

        ring.gradient.type = .conic
        ring.gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        ring.gradient.endPoint = CGPoint(x: 0.5, y: 1)
        ring.gradient.colors = colors.map(\.cgColor)
        ring.gradient.frame = bounds

        ring.spinner.frame = bounds
        ring.spinner.mask = ring.arc
        ring.spinner.addSublayer(ring.gradient)

        iconLayer.addSublayer(ring.track)
        iconLayer.addSublayer(ring.spinner)
    }

    private func applyTrackColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = NSColor.labelColor.withAlphaComponent(0.2).cgColor
            outer.track.strokeColor = color
            inner.track.strokeColor = color
        }
    }

    private func loop(for ring: Ring) -> [PaletteColor] {
        ring.arc === outer.arc ? Palette.cpuLoop : Palette.memoryLoop
    }

    private static func arcLength(_ fraction: Double) -> CGFloat {
        CGFloat(min(max(fraction, minimumArc), 1))
    }

    private static func rotation(duration: CFTimeInterval, clockwise: Bool) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = clockwise ? -2 * Double.pi : 2 * Double.pi
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }

    private static func pulse() -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 0.8
        animation.toValue = 1.25
        animation.duration = 1.2
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        return animation
    }
}
