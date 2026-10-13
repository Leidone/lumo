import AppKit
import LumoCore
import SwiftUI

// MARK: - Cleanup

struct OptimizerPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let t = model.t
        TabScroll {
            LumoCard {
                HStack {
                    IconBadge(symbol: "dial.high.fill", colors: Palette.intensityColors, size: 24)
                    Text(t("Интенсивность очистки", "Cleanup intensity")).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(levelTitle(t)) · \(Format.percent(model.intensity))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: model.intensity))
                }
                GradientSlider(value: $model.intensity, colors: Palette.intensityColors,
                               label: t("Интенсивность очистки", "Cleanup intensity"))
                HStack {
                    Text(t("Мягко", "Gentle"))
                    Spacer()
                    Text(t("Баланс", "Balanced"))
                    Spacer()
                    Text(t("Максимум", "Maximum"))
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
                Text(limitsDescription(t))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .appear(order: 0).scrollFade()

            LumoCard {
                SettingToggle(symbol: "bolt.badge.automatic.fill", colors: Palette.thresholdColors,
                              title: t("Авто-оптимизация", "Auto-optimize"),
                              subtitle: t("Сама наводит порядок при высокой нагрузке", "Tidies up by itself under heavy load"),
                              isOn: $model.autoEnabled)
                GradientSlider(value: thresholdBinding, colors: Palette.thresholdColors,
                               label: t("Порог авто-оптимизации", "Auto-optimize threshold"))
                    .disabled(!model.autoEnabled)
                    .opacity(model.autoEnabled ? 1 : 0.35)
                Text(t("Сработает, если CPU или память ≥ \(Format.percent(model.autoThreshold)) дольше 6 с. Не чаще раза в 5 минут.",
                       "Runs when CPU or memory stays ≥ \(Format.percent(model.autoThreshold)) for 6 s. At most once every 5 minutes."))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .appear(order: 1).scrollFade()

            SectionTitle(text: t("Что делать при очистке", "What cleanup does")).appear(order: 2)
            LumoCard {
                SettingToggle(symbol: "macwindow", colors: [Palette.blue.color, Palette.indigo.color],
                              title: t("Закрывать тяжёлые приложения", "Quit heavy apps"),
                              subtitle: t("Как ⌘Q — с предложением сохранить", "Like ⌘Q — you're asked to save"),
                              isOn: $model.closeApps)
                Divider().opacity(0.4)
                SettingToggle(symbol: "trash.fill", colors: [Palette.orange.color, Palette.red.color],
                              title: t("Чистить кэши", "Clean caches"),
                              subtitle: t("Кэши неактивных сторонних приложений", "Caches of idle third-party apps"),
                              isOn: $model.cleanCaches)
                Divider().opacity(0.4)
                SettingToggle(symbol: "memorychip.fill", colors: [Palette.green.color, Palette.mint.color],
                              title: t("Сбрасывать RAM и DNS-кэш", "Purge RAM and DNS cache"),
                              subtitle: model.passwordlessPurge
                                  ? t("Без пароля, и в авто-режиме тоже", "No password, auto mode included")
                                  : t("macOS спросит пароль администратора", "macOS asks for the admin password"),
                              isOn: $model.purgeMemory)
                Divider().opacity(0.4)
                SettingToggle(symbol: "key.fill", colors: [Palette.yellow.color, Palette.orange.color],
                              title: t("Без пароля", "No password"),
                              subtitle: model.passwordlessPurge
                                  ? t("Разрешено только для purge и DNS-кэша", "Allowed for purge and DNS cache only")
                                  : t("Пароль один раз — дальше без запросов", "Enter the password once, never again"),
                              isOn: passwordlessBinding)
                    .disabled(model.isConfiguringPurge)
            }
            .appear(order: 3).scrollFade()

            if !model.exceptions.isEmpty {
                SectionTitle(text: t("Исключения", "Exceptions"), trailing: "\(model.exceptions.count)")
                LumoCard {
                    ForEach(model.exceptions, id: \.self) { key in
                        HStack(spacing: 10) {
                            IconBadge(symbol: "lock.shield.fill", colors: [Palette.green.color, Palette.mint.color], size: 22)
                            Text(key).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            Button(t("Убрать", "Remove")) { model.toggleException(key) }
                                .buttonStyle(.borderless)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .scrollFade()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.exceptions)
    }

    private func levelTitle(_ t: Localizer) -> String {
        switch model.policy.level {
        case .gentle: return t("Мягко", "Gentle")
        case .balanced: return t("Баланс", "Balanced")
        case .maximum: return t("Максимум", "Maximum")
        }
    }

    private func limitsDescription(_ t: Localizer) -> String {
        let policy = model.policy
        let cpu = Int(policy.cpuLimitPercent)
        let background = Format.bytes(policy.backgroundMemoryLimitBytes)
        let apps = model.closeApps
            ? t("приложения > ", "apps > ") + Format.bytes(policy.appMemoryLimitBytes)
            : t("приложения не закрываются", "apps are never closed")
        let targets = model.plan.count
        return t("Цели: > \(cpu)% CPU, фоновые > \(background), \(apps). Сейчас под прицелом: \(targets).",
                 "Targets: > \(cpu)% CPU, background > \(background), \(apps). Currently targeted: \(targets).")
    }

    private var thresholdBinding: Binding<Double> {
        let range = AppModel.autoThresholdRange
        return Binding(
            get: { (model.autoThreshold - range.lowerBound) / (range.upperBound - range.lowerBound) },
            set: { model.autoThreshold = range.lowerBound + $0 * (range.upperBound - range.lowerBound) })
    }

    private var passwordlessBinding: Binding<Bool> {
        Binding(get: { model.passwordlessPurge }, set: { model.setPasswordlessPurge($0) })
    }
}

// MARK: - Settings

struct SettingsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let t = model.t
        TabScroll {
            LumoCard {
                SettingRow(symbol: "globe", colors: [Palette.blue.color, Palette.cyan.color], title: t("Язык", "Language")) {
                    PillPicker(options: AppLanguage.allCases, selection: $model.language) { $0.title }
                        .frame(width: 170)
                }
            }
            .appear(order: 0).scrollFade()

            SectionTitle(text: t("Уведомления", "Notifications")).appear(order: 1)
            LumoCard {
                alertToggle(.cpu, "cpu", Palette.cpuColors, t("Долгая нагрузка CPU", "Sustained CPU load"),
                            t("Выше 90% дольше 15 секунд", "Above 90% for over 15 seconds"))
                Divider().opacity(0.4)
                alertToggle(.memory, "memorychip.fill", Palette.memoryColors, t("Нехватка памяти", "Memory pressure"),
                            t("Когда macOS сообщает о давлении памяти", "When macOS reports memory pressure"))
                Divider().opacity(0.4)
                alertToggle(.disk, "internaldrive.fill", Palette.diskColors, t("Мало места на диске", "Low disk space"),
                            t("Свободно меньше 10%", "Less than 10% free"))
                Divider().opacity(0.4)
                alertToggle(.battery, "battery.25percent", [Palette.red.color, Palette.orange.color],
                            t("Низкий заряд", "Low battery"), t("15% и меньше, без зарядки", "15% or less, unplugged"))
                Divider().opacity(0.4)
                alertToggle(.temperature, "thermometer.sun.fill", [Palette.orange.color, Palette.red.color],
                            t("Перегрев", "Overheating"), t("Чип 95° и выше дольше 20 секунд", "Chip at 95° or more for 20 seconds"))
            }
            .appear(order: 2).scrollFade()

            SectionTitle(text: t("Обзор", "Overview")).appear(order: 3)
            LumoCard {
                tileToggle(.cores, "square.grid.3x3.fill", Palette.cpuColors, t("Нагрузка по ядрам", "Per-core load"))
                Divider().opacity(0.4)
                tileToggle(.network, "arrow.up.arrow.down", [Palette.cyan.color, Palette.blue.color], t("Сеть", "Network"))
                Divider().opacity(0.4)
                tileToggle(.battery, "battery.75percent", [Palette.green.color, Palette.mint.color], t("Батарея", "Battery"))
                Divider().opacity(0.4)
                tileToggle(.quickActions, "switch.2", [Palette.purple.color, Palette.pink.color], t("Быстрые действия", "Quick actions"))
            }
            .appear(order: 4).scrollFade()

            SectionTitle(text: t("Система", "System")).appear(order: 5)
            LumoCard {
                SettingToggle(symbol: "display", colors: [Palette.orange.color, Palette.yellow.color],
                              title: t("«Не спать» держит экран", "“Awake” keeps the display on"),
                              subtitle: t("Иначе гаснет только экран, Mac работает", "Otherwise only the display sleeps"),
                              isOn: $model.keepDisplayAwake)
                Divider().opacity(0.4)
                SettingToggle(symbol: "power", colors: [Palette.green.color, Palette.mint.color],
                              title: t("Запускать при входе", "Launch at login"),
                              subtitle: t("Lumo стартует вместе с macOS", "Lumo starts with macOS"),
                              isOn: launchBinding)
            }
            .appear(order: 6).scrollFade()

            AboutCard().appear(order: 7).scrollFade()
        }
    }

    private func alertToggle(_ kind: AlertKind, _ symbol: String, _ colors: [Color], _ title: String, _ subtitle: String) -> some View {
        SettingToggle(symbol: symbol, colors: colors, title: title, subtitle: subtitle, isOn: Binding(
            get: { model.enabledAlerts.contains(kind) },
            set: { model.setAlert(kind, enabled: $0) }))
    }

    private func tileToggle(_ tile: OverviewTile, _ symbol: String, _ colors: [Color], _ title: String) -> some View {
        SettingToggle(symbol: symbol, colors: colors, title: title, isOn: Binding(
            get: { model.isTileVisible(tile) },
            set: { model.setTile(tile, visible: $0) }))
    }

    private var launchBinding: Binding<Bool> {
        Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
    }
}

private struct AboutCard: View {
    @EnvironmentObject private var model: AppModel
    private static let repository = URL(string: "https://github.com/Leidone/lumo")

    var body: some View {
        let t = model.t
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let usage = model.snapshot.selfUsage
        LumoCard {
            HStack(spacing: 12) {
                LumoGlyph(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lumo \(version)").font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(t("Lumo сейчас: \(String(format: "%.1f", usage.cpuPercent))% CPU · \(Format.bytes(usage.footprintBytes))",
                           "Lumo now: \(String(format: "%.1f", usage.cpuPercent))% CPU · \(Format.bytes(usage.footprintBytes))"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
            }
            HStack(spacing: 8) {
                if let url = Self.repository {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right").frame(maxWidth: .infinity)
                    }
                }
                Button { model.onboardingDone = false } label: {
                    Label(t("Приветствие", "Welcome tour"), systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                Button(role: .destructive) { NSApp.terminate(nil) } label: {
                    Label(t("Выйти", "Quit"), systemImage: "power").frame(maxWidth: .infinity)
                }
            }
            .controlSize(.regular)
            .buttonStyle(.bordered)
            .font(.system(size: 11, weight: .medium))
        }
    }
}
