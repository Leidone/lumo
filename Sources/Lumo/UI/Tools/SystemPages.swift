import AppKit
import SwiftUI

// MARK: - Cleaner

struct CleanerPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: CleanerStore
    @State private var expanded: CleanerStore.Kind?

    var body: some View {
        let t = model.t
        TabScroll {
            LumoCard(padding: 16) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: FeatureID.cleaner.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 54, height: 54)
                            .shadow(color: Palette.blue.color.opacity(0.4), radius: 10)
                        Image(systemName: store.isScanning ? "magnifyingglass" : "sparkles")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolEffect(.pulse, isActive: store.isScanning || store.isCleaning)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.isScanning ? t("Ищу лишнее…", "Looking for clutter…") : Format.bytes(store.selectedBytes))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text(t("можно освободить из выбранного", "can be freed from the selection"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        if let freed = store.lastFreedBytes {
                            Label(t("Освобождено \(Format.bytes(freed))", "Freed \(Format.bytes(freed))"), systemImage: "checkmark.circle.fill")
                                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Palette.green.color)
                        }
                    }
                    Spacer(minLength: 0)
                }
                PrimaryButton(title: store.isCleaning ? t("Чищу…", "Cleaning…") : t("Очистить", "Clean up")) { store.clean() }
                    .disabled(store.selectedBytes == 0 || store.isCleaning || store.isScanning)
                    .opacity(store.selectedBytes == 0 ? 0.5 : 1)
            }
            .appear(order: 0).scrollFade()

            LumoCard {
                ForEach(Array(CleanerStore.Kind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { Divider().opacity(0.4) }
                    categoryRow(kind, t)
                }
            }
            .appear(order: 1).scrollFade()

            LumoCard {
                SettingToggle(symbol: "calendar.badge.clock", colors: [Palette.green.color, Palette.mint.color],
                              title: t("Чистить раз в неделю", "Clean weekly"),
                              subtitle: t("Только кэши и логи — в фоне, без вопросов", "Caches and logs only — quietly in the background"),
                              isOn: $store.autoCleanWeekly)
            }
            .appear(order: 2).scrollFade()
        }
        .onAppear { if store.findings.isEmpty { store.scan() } }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: expanded)
    }

    @ViewBuilder
    private func categoryRow(_ kind: CleanerStore.Kind, _ t: Localizer) -> some View {
        let finding = store.findings[kind]
        let info = describe(kind, t)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                IconBadge(symbol: info.symbol, colors: info.colors)
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.title).font(.system(size: 12.5, weight: .medium))
                    Text(info.subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                if kind == .downloads && !store.includeDownloads {
                    Button(t("Проверить", "Check")) {
                        store.includeDownloads = true
                        store.scan()
                    }
                    .controlSize(.small)
                } else {
                    Button {
                        expanded = expanded == kind ? nil : kind
                    } label: {
                        HStack(spacing: 3) {
                            Text(finding.map { Format.bytes($0.bytes) } ?? "—").monospacedDigit()
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                                .rotationEffect(.degrees(expanded == kind ? 90 : 0))
                        }
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled((finding?.items.isEmpty ?? true))
                    Toggle(info.title, isOn: selectionBinding(kind))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            if expanded == kind, let items = finding?.items, !items.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(items.prefix(8)) { item in
                        HStack {
                            Text(item.name).font(.system(size: 10.5)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Format.bytes(item.bytes)).font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                        }
                    }
                    if items.count > 8 {
                        Text(t("и ещё \(items.count - 8)", "and \(items.count - 8) more")).font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 38)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func selectionBinding(_ kind: CleanerStore.Kind) -> Binding<Bool> {
        Binding(get: { store.selection.contains(kind) },
                set: { store.selection = $0 ? store.selection.union([kind]) : store.selection.subtracting([kind]) })
    }

    private func describe(_ kind: CleanerStore.Kind, _ t: Localizer) -> (title: String, subtitle: String, symbol: String, colors: [Color]) {
        switch kind {
        case .caches:
            return (t("Кэши приложений", "App caches"), t("Неактивные сторонние приложения", "Idle third-party apps"),
                    "archivebox.fill", [Palette.cyan.color, Palette.blue.color])
        case .logs:
            return (t("Логи", "Logs"), t("~/Library/Logs", "~/Library/Logs"), "doc.text.fill", [Palette.indigo.color, Palette.purple.color])
        case .derivedData:
            return (t("Сборки Xcode", "Xcode builds"), "DerivedData", "hammer.fill", [Palette.blue.color, Palette.indigo.color])
        case .leftovers:
            return (t("Остатки удалённых приложений", "Leftovers of removed apps"), t("В Корзину — можно вернуть", "To the Trash — recoverable"),
                    "shippingbox.fill", [Palette.orange.color, Palette.red.color])
        case .downloads:
            return (t("Старые загрузки", "Old downloads"), t("Старше 30 дней, в Корзину", "Older than 30 days, to the Trash"),
                    "arrow.down.circle.fill", [Palette.green.color, Palette.mint.color])
        }
    }
}

// MARK: - Uninstaller

struct UninstallerPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: UninstallerStore
    @State private var query = ""

    var body: some View {
        let t = model.t
        Group {
            if let app = store.selected {
                detail(app, t).transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                list(t).transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: store.selected)
        .onAppear { if store.apps.isEmpty { store.loadApps() } }
    }

    private func list(_ t: Localizer) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                TextField(t("Найти приложение", "Find an app"), text: $query).textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 16)
            if let removed = store.lastRemoved {
                Label(t("\(removed) отправлено в Корзину", "\(removed) moved to the Trash"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.green.color)
            }
            TabScroll(topInset: 2) {
                if store.isLoading && store.apps.isEmpty { ProgressView().controlSize(.small).padding(.top, 30) }
                ForEach(store.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { app in
                    Button { store.select(app) } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: IconCache.icon(for: app.url.path)).resizable().frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                Text(app.version.map { t("Версия \($0)", "Version \($0)") } ?? app.bundleID ?? "")
                                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 7).padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.035)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .scrollFade()
                }
            }
        }
    }

    private func detail(_ app: UninstallerStore.InstalledApp, _ t: Localizer) -> some View {
        TabScroll {
            LumoCard(padding: 16) {
                HStack(spacing: 14) {
                    Image(nsImage: IconCache.icon(for: app.url.path)).resizable().frame(width: 56, height: 56)
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.system(size: 17, weight: .bold, design: .rounded))
                        Text(app.version.map { t("Версия \($0)", "Version \($0)") } ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(t("Всего: \(Format.bytes(store.totalBytes))", "Total: \(Format.bytes(store.totalBytes))"))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .contentTransition(.numericText())
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Button(t("Назад", "Back")) { store.select(nil) }.controlSize(.large)
                    Button(role: .destructive) {
                        store.uninstall { model.errorMessage = $0 }
                    } label: {
                        Label(store.isRemoving ? t("Удаляю…", "Removing…") : t("Удалить в Корзину", "Move to Trash"),
                              systemImage: "trash.fill").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.red.color)
                    .disabled(store.isRemoving)
                }
            }
            .appear(order: 0)
            SectionTitle(text: t("Найденные следы", "Traces found"), trailing: "\(store.traces.count)").appear(order: 1)
            LumoCard {
                if store.traces.isEmpty {
                    Text(t("В ~/Library ничего не найдено — удалится только само приложение.",
                           "Nothing in ~/Library — only the app itself will be removed."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(store.traces) { trace in
                    HStack(spacing: 10) {
                        Toggle(trace.url.lastPathComponent, isOn: Binding(
                            get: { !store.excluded.contains(trace.url) },
                            set: { store.excluded = $0 ? store.excluded.subtracting([trace.url]) : store.excluded.union([trace.url]) }))
                            .labelsHidden().toggleStyle(.checkbox)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(trace.url.lastPathComponent).font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
                            Text(trace.folder).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.bytes(trace.bytes)).font(.system(size: 10.5, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
            .appear(order: 2)
        }
    }
}

// MARK: - Sensors helpers

private func stat(_ title: String, _ value: String, _ symbol: String, _ colors: [Color]) -> some View {
    HStack(spacing: 10) {
        IconBadge(symbol: symbol, colors: colors, size: 30)
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
        }
        Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
}

private struct EnergyList: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var energy: EnergyMonitor
    @State private var timer: Timer?

    var body: some View {
        let t = model.t
        LumoCard {
            if energy.entries.isEmpty {
                HStack {
                    if energy.isLoading { ProgressView().controlSize(.small) }
                    Text(energy.isLoading ? t("Считаю…", "Measuring…") : t("Сейчас никто не нагружает Mac", "Nothing is draining power right now"))
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            let top = energy.entries.map(\.impact).max() ?? 1
            ForEach(energy.entries, id: \.pid) { entry in
                HStack(spacing: 10) {
                    let path = NSRunningApplication(processIdentifier: entry.pid)?.bundleURL?.path
                    Image(nsImage: path.map { IconCache.icon(for: $0) } ?? NSWorkspace.shared.icon(for: .unixExecutable))
                        .resizable().frame(width: 20, height: 20)
                    Text(NSRunningApplication(processIdentifier: entry.pid)?.localizedName ?? entry.name)
                        .font(.system(size: 12)).lineLimit(1)
                    Spacer()
                    CapsuleMeter(value: entry.impact / max(top, 1), colors: [Palette.yellow.color, Palette.orange.color]).frame(width: 70)
                    Text(String(format: "%.1f", entry.impact)).font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit().frame(width: 36, alignment: .trailing)
                }
            }
            Text(t("«Энергетическое воздействие» macOS, обновляется каждые 5 секунд", "macOS “Energy Impact”, refreshed every 5 seconds"))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .onAppear {
            energy.refresh()
            let timer = Timer(timeInterval: 5, repeats: true) { _ in MainActor.assumeIsolated { energy.refresh() } }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        .onDisappear { timer?.invalidate() }
    }
}

private struct FanControlRow: View {
    @EnvironmentObject private var model: AppModel
    let fan: SensorStore.Fan
    @ObservedObject var control: FanControl
    @State private var target: Double = 0.5

    var body: some View {
        let t = model.t
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Slider(value: $target, in: 0...1)
                Text("\(Int(rpm)) RPM").font(.system(size: 10.5, design: .rounded)).monospacedDigit().frame(width: 70, alignment: .trailing)
            }
            HStack {
                Button(t("Задать", "Set")) { control.set(fan, rpm: rpm, t: t) }
                Button(t("Авто", "Auto")) { control.automatic(fan, t: t) }
                if control.manual[fan.index] != nil {
                    Text(t("Ручной режим", "Manual mode")).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Palette.orange.color)
                }
            }
            .controlSize(.small)
            .disabled(control.isBusy || !control.isAvailable)
            if let error = control.lastError {
                Text(error).font(.system(size: 10)).foregroundStyle(Palette.orange.color)
            }
        }
    }

    private var rpm: Double { (fan.minRPM + (fan.maxRPM - fan.minRPM) * target).rounded() }
}

// MARK: - Sensors

struct SensorsPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: SensorStore
    @State private var showAll = false

    var body: some View {
        let t = model.t
        TabScroll {
            LumoCard(padding: 16) {
                HStack(spacing: 8) {
                    gauge(t("Процессор", "Chip"), store.socTemperature, "cpu")
                    gauge(t("Батарея", "Battery"), store.batteryTemperature, "battery.75percent")
                    gauge("SSD", store.ssdTemperature, "internaldrive")
                }
            }
            .appear(order: 0).scrollFade()

            LumoCard {
                HStack(spacing: 10) {
                    stat(t("Видеочип", "GPU"), model.gpuLoad.map(Format.percent) ?? "—", "cube.transparent", [Palette.purple.color, Palette.indigo.color])
                    stat(t("Потребление", "Power"), model.systemWatts.map { String(format: t("%.1f Вт", "%.1f W"), $0) } ?? "—",
                         "bolt.fill", [Palette.yellow.color, Palette.orange.color])
                }
            }
            .appear(order: 0).scrollFade()

            SectionTitle(text: t("Больше всех тратят энергию", "Using the most energy")).appear(order: 1)
            EnergyList(energy: model.energy)
                .appear(order: 1).scrollFade()

            SectionTitle(text: t("Вентиляторы", "Fans")).appear(order: 1)
            LumoCard {
                if store.fans.isEmpty {
                    SettingRow(symbol: "wind", colors: [Palette.cyan.color, Palette.blue.color],
                               title: t("Без вентилятора", "Fanless"),
                               subtitle: t("Этот Mac охлаждается пассивно — крутить нечего.", "This Mac is passively cooled — nothing to spin.")) { EmptyView() }
                }
                ForEach(store.fans) { fan in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(t("Вентилятор \(fan.index + 1)", "Fan \(fan.index + 1)"), systemImage: "fan.fill")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(Int(fan.rpm)) RPM").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                        CapsuleMeter(value: fan.fraction, colors: [Palette.cyan.color, Palette.blue.color])
                        FanControlRow(fan: fan, control: model.fanControl)
                    }
                }
            }
            .appear(order: 2).scrollFade()

            SectionTitle(text: t("Все датчики", "All sensors"), trailing: "\(store.readings.count)").appear(order: 3)
            LumoCard {
                if !store.isSupported {
                    Text(t("Датчики температуры недоступны на этом Mac.", "Temperature sensors aren't available on this Mac."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(showAll ? store.readings : Array(store.readings.prefix(6))) { reading in
                    HStack {
                        Circle().fill(Self.tint(reading.celsius)).frame(width: 7, height: 7)
                        Text(reading.name).font(.system(size: 11.5)).lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1f°", reading.celsius))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText(value: reading.celsius))
                    }
                }
                if store.readings.count > 6 {
                    Button(showAll ? t("Свернуть", "Show less") : t("Показать все", "Show all")) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showAll.toggle() }
                    }
                    .buttonStyle(.borderless).font(.system(size: 11, weight: .medium))
                }
            }
            .appear(order: 4).scrollFade()
        }
        .onAppear {
            model.sensorsVisible = true
            store.sample()
        }
        .onDisappear { model.sensorsVisible = false }
    }

    private func gauge(_ title: String, _ value: Double?, _ symbol: String) -> some View {
        let fraction = min(max(((value ?? 0) - 25) / 75, 0), 1)
        let scale = [Palette.green, Palette.yellow, Palette.orange, Palette.red].map(\.color)
        let colors = Array(scale.prefix(max(2, Int((fraction * 4).rounded(.up)))))
        return VStack(spacing: 6) {
            ZStack {
                ActivityRings(rings: [.init(id: title, value: fraction, colors: colors)], lineWidth: 8)
                VStack(spacing: 0) {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Text(value.map { "\(Int($0.rounded()))°" } ?? "—")
                        .font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText(value: value ?? 0))
                }
            }
            .frame(width: 72, height: 72)
            Text(title).font(.system(size: 11, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
    }

    private static func tint(_ celsius: Double) -> Color {
        switch celsius {
        case ..<50: return Palette.green.color
        case ..<70: return Palette.yellow.color
        case ..<85: return Palette.orange.color
        default: return Palette.red.color
        }
    }
}

// MARK: - Menu bar readouts

struct ReadoutsPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let t = model.t
        TabScroll {
            SectionTitle(text: t("Индикаторы в строке меню", "Menu bar readouts")).appear(order: 0)
            LumoCard {
                ForEach(Array(Readout.allCases.enumerated()), id: \.element) { index, readout in
                    if index > 0 { Divider().opacity(0.4) }
                    SettingToggle(symbol: readout.symbol, colors: colors(readout), title: readout.title(t),
                                  subtitle: subtitle(readout, t),
                                  isOn: Binding(get: { model.readouts.contains(readout) },
                                                set: { model.readouts = $0 ? model.readouts.union([readout]) : model.readouts.subtracting([readout]) }))
                }
            }
            .appear(order: 1).scrollFade()

            LumoCard {
                SettingToggle(symbol: "chart.bar.fill", colors: [Palette.blue.color, Palette.purple.color],
                              title: t("Полоски вместо чисел", "Bars instead of numbers"),
                              subtitle: t("Для процессора, памяти и видеочипа", "For CPU, memory and GPU"), isOn: $model.readoutBars)
            }
            .appear(order: 2).scrollFade()

            SectionTitle(text: t("Главная иконка", "Main icon")).appear(order: 2)
            LumoCard {
                SettingRow(symbol: "textformat", colors: [Palette.indigo.color, Palette.purple.color],
                           title: t("Текст у иконки", "Text next to icon")) {
                    Picker(t("Текст у иконки", "Text next to icon"), selection: $model.menuBarText) {
                        ForEach(MenuBarText.allCases) { Text($0.title(t)).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                Divider().opacity(0.4)
                SettingToggle(symbol: "sparkles", colors: [Palette.purple.color, Palette.pink.color],
                              title: t("Анимация иконки", "Icon animation"),
                              subtitle: t("Переливы и пульс", "Shimmer and pulse"), isOn: $model.animateIcon)
            }
            .appear(order: 3).scrollFade()
        }
    }

    private func colors(_ readout: Readout) -> [Color] {
        switch readout {
        case .cpu: return Palette.cpuColors
        case .memory: return Palette.memoryColors
        case .network: return [Palette.cyan.color, Palette.blue.color]
        case .temperature: return [Palette.yellow.color, Palette.orange.color]
        case .battery: return [Palette.green.color, Palette.mint.color]
        case .gpu: return [Palette.purple.color, Palette.indigo.color]
        case .fan: return [Palette.cyan.color, Palette.blue.color]
        case .power: return [Palette.yellow.color, Palette.orange.color]
        case .batteryTime: return [Palette.mint.color, Palette.green.color]
        }
    }

    private func subtitle(_ readout: Readout, _ t: Localizer) -> String {
        let snapshot = model.snapshot
        switch readout {
        case .cpu: return t("Сейчас ", "Now ") + Format.percent(snapshot.cpuLoad)
        case .memory: return t("Сейчас ", "Now ") + Format.percent(snapshot.memory.fraction)
        case .network: return "↓\(Format.compactRate(snapshot.network.downRate)) ↑\(Format.compactRate(snapshot.network.upRate))"
        case .temperature:
            return model.sensors.socTemperature.map { t("Чип \(Int($0.rounded()))°", "Chip \(Int($0.rounded()))°") }
                ?? t("Чип SoC", "SoC temperature")
        case .battery: return snapshot.battery.map { Format.percent($0.charge) } ?? t("Нет батареи", "No battery")
        case .gpu: return model.gpuLoad.map { t("Сейчас ", "Now ") + Format.percent($0) } ?? t("Нет данных", "Unavailable")
        case .power: return model.systemWatts.map { String(format: t("Сейчас %.1f Вт", "Now %.1f W"), $0) } ?? t("Нет данных", "Unavailable")
        case .fan: return model.sensors.fans.isEmpty ? t("У этого Mac нет вентилятора", "This Mac has no fan") : t("Обороты в минуту", "Revolutions per minute")
        case .batteryTime: return t("До разрядки или до полной зарядки", "Until empty, or until full")
        }
    }
}
