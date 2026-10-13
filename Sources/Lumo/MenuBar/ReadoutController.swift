import AppKit

enum Readout: String, CaseIterable, Identifiable {
    case cpu, memory, gpu, network, temperature, fan, power, battery, batteryTime

    var id: Self { self }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .gpu: return "cube.transparent"
        case .fan: return "fan.fill"
        case .power: return "bolt.fill"
        case .batteryTime: return "clock.fill"
        case .network: return "arrow.up.arrow.down"
        case .temperature: return "thermometer.medium"
        case .battery: return "battery.75percent"
        }
    }

    func title(_ t: Localizer) -> String {
        switch self {
        case .cpu: return t("Процессор", "CPU")
        case .memory: return t("Память", "Memory")
        case .gpu: return t("Видеочип", "GPU")
        case .fan: return t("Вентилятор", "Fan")
        case .power: return t("Потребление, Вт", "Power draw, W")
        case .batteryTime: return t("Время батареи", "Battery time")
        case .network: return t("Сеть", "Network")
        case .temperature: return t("Температура", "Temperature")
        case .battery: return t("Батарея", "Battery")
        }
    }
}

/// Optional extra menu bar items, each a small symbol plus a live value.
/// Clicking any of them opens Lumo's popover right under it.
@MainActor
final class ReadoutController: NSObject {
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)

    private var items: [Readout: NSStatusItem] = [:]
    private var lastText: [Readout: String] = [:]
    private let onClick: (NSStatusBarButton) -> Void

    init(onClick: @escaping (NSStatusBarButton) -> Void) {
        self.onClick = onClick
    }

    /// Readouts that can be drawn as a tiny vertical bar instead of a number.
    private static let barReadouts: Set<Readout> = [.cpu, .memory, .gpu]

    func update(from model: AppModel) {
        let wanted = Readout.allCases.filter { model.readouts.contains($0) && value(for: $0, model: model) != nil }
        for readout in items.keys where !wanted.contains(readout) {
            items[readout].map { NSStatusBar.system.removeStatusItem($0) }
            items[readout] = nil
            lastText[readout] = nil
        }
        // Created in reverse so they appear left-to-right in `Readout.allCases` order.
        for readout in wanted.reversed() where items[readout] == nil {
            items[readout] = makeItem(readout, model: model)
        }
        for readout in wanted {
            guard let text = value(for: readout, model: model), let button = items[readout]?.button else { continue }
            let asBar = model.readoutBars && Self.barReadouts.contains(readout)
            let key = asBar ? "bar:" + text : text
            guard key != lastText[readout] else { continue }
            lastText[readout] = key
            if asBar {
                button.attributedTitle = NSAttributedString(string: "")
                button.image = Self.bar(fraction: fraction(for: readout, model: model), symbol: readout.symbol)
                continue
            }
            button.image = readout == .battery ? image(batterySymbol(model)) : image(readout.symbol)
            button.attributedTitle = NSAttributedString(string: " " + text, attributes: [.font: Self.font])
        }
    }

    private func makeItem(_ readout: Readout, model: AppModel) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return item }
        button.image = image(readout == .battery ? batterySymbol(model) : readout.symbol)
        button.imagePosition = .imageLeft
        button.target = self
        button.action = #selector(clicked(_:))
        button.toolTip = "Lumo · " + readout.title(model.t)
        return item
    }

    @objc private func clicked(_ sender: NSStatusBarButton) { onClick(sender) }

    private func image(_ symbol: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(Self.symbolConfig)
        image?.isTemplate = true
        return image
    }

    private func batterySymbol(_ model: AppModel) -> String {
        guard let battery = model.snapshot.battery else { return "battery.100percent" }
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.charge {
        case ..<0.15: return "battery.0percent"
        case ..<0.4: return "battery.25percent"
        case ..<0.65: return "battery.50percent"
        case ..<0.9: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func value(for readout: Readout, model: AppModel) -> String? {
        let snapshot = model.snapshot
        switch readout {
        case .cpu: return Format.percent(snapshot.cpuLoad)
        case .memory: return Format.percent(snapshot.memory.fraction)
        case .network:
            return "↓\(Format.compactRate(snapshot.network.downRate)) ↑\(Format.compactRate(snapshot.network.upRate))"
        case .temperature:
            return model.sensors.socTemperature.map { "\(Int($0.rounded()))°" }
        case .battery:
            return snapshot.battery.map { Format.percent($0.charge) }
        case .gpu:
            return model.gpuLoad.map(Format.percent)
        case .power:
            return model.systemWatts.map { String(format: "%.1fW", $0) }
        case .fan:
            return model.sensors.fans.first.map { "\(Int($0.rpm))" }
        case .batteryTime:
            guard let battery = snapshot.battery, let minutes = battery.minutesRemaining else { return nil }
            return String(format: "%d:%02d", minutes / 60, minutes % 60)
        }
    }

    private func fraction(for readout: Readout, model: AppModel) -> Double {
        switch readout {
        case .cpu: return model.snapshot.cpuLoad
        case .memory: return model.snapshot.memory.fraction
        case .gpu: return model.gpuLoad ?? 0
        default: return 0
        }
    }

    /// A small icon plus a vertical fill bar, drawn as a template so it follows the menu bar's color.
    private static func bar(fraction: Double, symbol: String) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)) {
                glyph.draw(in: NSRect(x: 0, y: 2, width: 12, height: 12))
            }
            let frame = NSRect(x: 15, y: 1, width: 6, height: 14)
            NSColor.black.setStroke()
            let outline = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 1.5, yRadius: 1.5)
            outline.lineWidth = 1
            outline.stroke()
            let height = max((frame.height - 3) * CGFloat(min(max(fraction, 0), 1)), 1)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: frame.minX + 1.5, y: frame.minY + 1.5, width: frame.width - 3, height: height),
                         xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
