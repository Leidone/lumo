import LumoCore
import SwiftUI

struct OverviewTab: View {
    @EnvironmentObject private var model: AppModel

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let t = model.t
        TabScroll {
            HeroCard().appear(order: 0).scrollFade()
            OptimizeButton(isBusy: model.isOptimizing, targets: model.plan.count,
                           title: t("Оптимизировать", "Optimize"), busyTitle: t("Оптимизация…", "Optimizing…")) {
                model.optimize()
            }
            .padding(.horizontal, 4)
            .appear(order: 1)
            if let report = model.lastReport {
                ReportBanner(report: report, t: t, dismiss: model.dismissReport)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            CPUTile().appear(order: 2).scrollFade()
            LazyVGrid(columns: columns, spacing: 12) {
                MemoryTile().scrollFade()
                if model.isTileVisible(.network) { NetworkTile().scrollFade() }
                if model.isTileVisible(.battery), let battery = model.snapshot.battery {
                    BatteryTile(battery: battery).scrollFade()
                }
                DiskTile().scrollFade()
            }
            .appear(order: 3)
            if model.isTileVisible(.quickActions) {
                QuickActionsSection().appear(order: 4).scrollFade()
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: model.lastReport)
    }
}

// MARK: - Hero

private struct HeroCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let t = model.t
        let snapshot = model.snapshot
        LumoCard(padding: 16) {
            HStack(spacing: 18) {
                ActivityRings(rings: [
                    .init(id: "cpu", value: snapshot.cpuLoad, colors: Palette.cpuColors),
                    .init(id: "memory", value: snapshot.memory.fraction, colors: Palette.memoryColors),
                    .init(id: "disk", value: snapshot.disk.fraction, colors: Palette.diskColors),
                ], lineWidth: 12, gap: 3)
                .frame(width: 114, height: 114)

                VStack(alignment: .leading, spacing: 9) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline(t))
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .contentTransition(.opacity)
                        Text(subline(t)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    LegendRow(colors: Palette.cpuColors, title: "CPU", value: snapshot.cpuLoad)
                    LegendRow(colors: Palette.memoryColors, title: t("Память", "Memory"), value: snapshot.memory.fraction)
                    LegendRow(colors: Palette.diskColors, title: t("Диск", "Disk"), value: snapshot.disk.fraction)
                }
            }
        }
    }

    private func headline(_ t: Localizer) -> String {
        switch model.healthLoad {
        case ..<0.6: return t("Всё спокойно", "All calm")
        case ..<0.85: return t("Работает в меру", "Working steadily")
        default: return t("Mac под нагрузкой", "Mac under load")
        }
    }

    private func subline(_ t: Localizer) -> String {
        let targets = model.plan.count
        return targets == 0
            ? t("Лишних процессов нет", "Nothing to clean up")
            : t("Можно освободить: \(targets)", "Ready to free up: \(targets)")
    }
}

private struct LegendRow: View {
    let colors: [Color]
    let title: String
    let value: Double

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 8, height: 8)
            Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(Format.percent(value))
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: value))
                .animation(.spring(response: 0.5), value: value)
        }
    }
}

// MARK: - Tiles

private struct TileHeader: View {
    let symbol: String
    let colors: [Color]
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            IconBadge(symbol: symbol, colors: colors, size: 20)
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
        }
    }
}

private struct BigNumber: View {
    let text: String
    var value: Double = 0

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(value: value))
            .animation(.spring(response: 0.5), value: value)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct CPUTile: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let t = model.t
        let snapshot = model.snapshot
        LumoCard {
            HStack(alignment: .firstTextBaseline) {
                TileHeader(symbol: "cpu", colors: Palette.cpuColors, title: t("Процессор", "Processor"))
                Spacer()
                BigNumber(text: Format.percent(snapshot.cpuLoad), value: snapshot.cpuLoad)
            }
            Sparkline(values: snapshot.cpuHistory.values, colors: Palette.cpuColors)
                .frame(height: 46)
            if model.isTileVisible(.cores), !snapshot.coreLoads.isEmpty {
                CoreBars(loads: snapshot.coreLoads).frame(height: 24)
                Text(t("\(snapshot.coreLoads.count) ядер · пик за 2 мин \(Format.percent(snapshot.cpuHistory.peak))",
                       "\(snapshot.coreLoads.count) cores · 2-min peak \(Format.percent(snapshot.cpuHistory.peak))"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MemoryTile: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let t = model.t
        let snapshot = model.snapshot
        LumoCard(padding: 12) {
            TileHeader(symbol: "memorychip", colors: Palette.memoryColors, title: t("Память", "Memory"))
            BigNumber(text: Format.percent(snapshot.memory.fraction), value: snapshot.memory.fraction)
            Sparkline(values: snapshot.memoryHistory.values, colors: Palette.memoryColors, showsDot: false)
                .frame(height: 24)
            PressureChip(pressure: snapshot.pressure, t: t)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct PressureChip: View {
    let pressure: MemoryPressure
    let t: Localizer

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.14)))
        .help(t("Давление памяти по оценке macOS", "Memory pressure as reported by macOS"))
    }

    private var title: String {
        switch pressure {
        case .normal: return t("Давление в норме", "Pressure normal")
        case .warning: return t("Давление растёт", "Pressure rising")
        case .critical: return t("Памяти мало", "Memory critical")
        }
    }

    private var tint: Color {
        switch pressure {
        case .normal: return Palette.green.color
        case .warning: return Palette.yellow.color
        case .critical: return Palette.red.color
        }
    }
}

private struct NetworkTile: View {
    @EnvironmentObject private var model: AppModel
    private static let minimumScale = 64_000.0

    var body: some View {
        let t = model.t
        let snapshot = model.snapshot
        let scale = max(snapshot.downHistory.peak, snapshot.upHistory.peak, Self.minimumScale)
        LumoCard(padding: 12) {
            TileHeader(symbol: "arrow.up.arrow.down", colors: [Palette.cyan.color, Palette.blue.color], title: t("Сеть", "Network"))
            VStack(alignment: .leading, spacing: 2) {
                rate("arrow.down", Palette.cyan.color, snapshot.network.downRate)
                rate("arrow.up", Palette.pink.color, snapshot.network.upRate)
            }
            ZStack {
                Sparkline(values: snapshot.downHistory.values.map { $0 / scale },
                          colors: [Palette.blue.color, Palette.cyan.color], showsDot: false)
                Sparkline(values: snapshot.upHistory.values.map { $0 / scale },
                          colors: [Palette.purple.color, Palette.pink.color], showsDot: false)
                    .opacity(0.8)
            }
            .frame(height: 22)
            Text(snapshot.network.localIP ?? t("Нет подключения", "Offline"))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func rate(_ symbol: String, _ tint: Color, _ value: Double) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
            Text(Format.rate(value))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: value))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .animation(.spring(response: 0.5), value: value)
    }
}

private struct BatteryTile: View {
    @EnvironmentObject private var model: AppModel
    let battery: BatteryReading

    var body: some View {
        let t = model.t
        let low = battery.charge < 0.2 && !battery.isPluggedIn
        let colors = low ? [Palette.red.color, Palette.orange.color] : [Palette.green.color, Palette.mint.color]
        LumoCard(padding: 12) {
            TileHeader(symbol: battery.isCharging ? "bolt.fill" : "battery.75percent", colors: colors,
                       title: t("Батарея", "Battery"))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                BigNumber(text: Format.percent(battery.charge), value: battery.charge)
                if battery.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.yellow.color)
                        .symbolEffect(.pulse)
                }
            }
            CapsuleMeter(value: battery.charge, colors: colors)
            Text(status(t)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
            Text(details(t)).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func status(_ t: Localizer) -> String {
        if let minutes = battery.minutesRemaining {
            let time = Format.duration(minutes: minutes, t)
            return battery.isCharging ? t("До полной: \(time)", "Full in \(time)") : t("Осталось: \(time)", "\(time) left")
        }
        if battery.isPluggedIn { return battery.isCharging ? t("Заряжается", "Charging") : t("Подключено", "Plugged in") }
        return t("Считаю время…", "Estimating…")
    }

    private func details(_ t: Localizer) -> String {
        var parts: [String] = []
        if let health = battery.health { parts.append(t("здоровье \(Format.percent(health))", "health \(Format.percent(health))")) }
        if let cycles = battery.cycleCount { parts.append(t("\(cycles) цикл.", "\(cycles) cycles")) }
        if let watts = battery.watts { parts.append(String(format: t("%.1f Вт", "%.1f W"), watts)) }
        return parts.joined(separator: " · ")
    }
}

private struct DiskTile: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let t = model.t
        let disk = model.snapshot.disk
        LumoCard(padding: 12) {
            TileHeader(symbol: "internaldrive.fill", colors: Palette.diskColors, title: t("Диск", "Disk"))
            BigNumber(text: Format.bytes(disk.availableBytes))
            Text(t("свободно", "free")).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
            CapsuleMeter(value: disk.fraction, colors: Palette.diskColors)
            Text(t("занято \(Format.percent(disk.fraction)) из \(Format.bytes(disk.totalBytes))",
                   "\(Format.percent(disk.fraction)) of \(Format.bytes(disk.totalBytes)) used"))
                .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Quick actions

private struct QuickActionsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var showDurations = false
    @State private var confirmTrash = false

    private static let durations: [Int?] = [15, 30, 60, 120, nil]

    var body: some View {
        let t = model.t
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: t("Быстрые действия", "Quick actions"), trailing: awakeCaption(t))
            LumoCard(padding: 12) {
                HStack(spacing: 4) {
                    QuickToggleButton(symbol: "cup.and.saucer.fill", title: t("Не спать", "Awake"),
                                      isOn: model.keepAwake.isOn, tint: Palette.orange.color) {
                        if model.keepAwake.isOn { model.stopKeepAwake() } else { showDurations.toggle() }
                    }
                    QuickToggleButton(symbol: "moon.fill", title: t("Тёмная", "Dark"),
                                      isOn: model.darkMode, tint: Palette.indigo.color) { model.toggleDarkMode() }
                    QuickToggleButton(symbol: "eye.slash.fill", title: t("Без иконок", "No icons"),
                                      isOn: model.desktopIconsHidden, tint: Palette.blue.color) { model.toggleDesktopIcons() }
                    QuickToggleButton(symbol: "lock.fill", title: t("Блокировка", "Lock"),
                                      isOn: false, tint: Palette.purple.color) { model.lockScreen() }
                    QuickToggleButton(symbol: confirmTrash ? "checkmark" : "trash.fill",
                                      title: confirmTrash ? t("Точно?", "Sure?") : t("Корзина", "Trash"),
                                      isOn: confirmTrash, tint: Palette.red.color) { trashTapped() }
                }
                if showDurations && !model.keepAwake.isOn {
                    HStack(spacing: 6) {
                        ForEach(Self.durations, id: \.self) { minutes in
                            Button {
                                model.startKeepAwake(minutes: minutes)
                                showDurations = false
                            } label: {
                                Text(minutes.map { Format.duration(minutes: $0, t) } ?? "∞")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Palette.orange.color.opacity(0.16)))
                                    .foregroundStyle(Palette.orange.color)
                            }
                            .buttonStyle(PressScaleStyle())
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showDurations)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.keepAwake)
    }

    private func awakeCaption(_ t: Localizer) -> String? {
        guard case .on(let until) = model.keepAwake else { return nil }
        guard let until else { return t("Не засыпает", "Staying awake") }
        return t("Не засыпает до \(until.formatted(date: .omitted, time: .shortened))",
                 "Awake until \(until.formatted(date: .omitted, time: .shortened))")
    }

    /// Two-step confirmation: emptying the Trash can't be undone.
    private func trashTapped() {
        guard confirmTrash else {
            confirmTrash = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                confirmTrash = false
            }
            return
        }
        confirmTrash = false
        model.emptyTrash()
    }
}

private struct QuickToggleButton: View {
    let symbol: String
    let title: String
    let isOn: Bool
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(isOn
                        ? AnyShapeStyle(LinearGradient(colors: [tint.opacity(0.8), tint], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Color.primary.opacity(hovering ? 0.14 : 0.08)))
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: isOn)
                }
                .frame(width: 42, height: 42)
                .shadow(color: isOn ? tint.opacity(0.5) : .clear, radius: 8, y: 3)
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isOn)
        .help(title)
    }
}

// MARK: - Report

struct ReportBanner: View {
    let report: OptimizationReport
    let t: Localizer
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: report.didAnything ? "checkmark.seal.fill" : "hand.thumbsup.fill")
                .font(.system(size: 20))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: report.date)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.system(size: 12.5, weight: .semibold))
                Text(details).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.13)))
    }

    private var tint: Color { report.didAnything ? Palette.green.color : Palette.blue.color }

    private var headline: String {
        let prefix = report.isAutomatic ? t("Авто · ", "Auto · ") : ""
        guard report.didAnything else {
            return prefix + t("Mac уже в форме — лишнего не нашлось", "Your Mac is already in shape")
        }
        let freed = Format.bytes(report.freedMemoryBytes)
        return prefix + t("Готово: освобождено \(freed) RAM", "Done: \(freed) of RAM freed")
    }

    private var details: String {
        var parts: [String] = []
        if !report.stopped.isEmpty {
            parts.append(t("Остановлено: ", "Stopped: ") + report.stopped.joined(separator: ", "))
        }
        if report.cacheBytes > 0 { parts.append(t("Кэш: ", "Cache: ") + Format.bytes(report.cacheBytes)) }
        if report.purged { parts.append(t("RAM и DNS-кэш сброшены", "RAM and DNS cache purged")) }
        if !report.failed.isEmpty {
            parts.append(t("Не удалось: ", "Failed: ") + report.failed.joined(separator: ", "))
        }
        parts += report.notes
        return parts.isEmpty
            ? t("Никто не превышает выбранные лимиты", "Nothing exceeds the chosen limits")
            : parts.joined(separator: " · ")
    }
}
