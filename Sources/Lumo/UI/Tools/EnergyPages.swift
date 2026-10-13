import AppKit
import SwiftUI

struct EnergyPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var energy: EnergyTools

    var body: some View {
        let t = model.t
        TabScroll {
            LumoCard {
                HStack(spacing: 8) {
                    ForEach([30, 60, 180], id: \.self) { minutes in
                        Button(Format.duration(minutes: minutes, t)) { model.startKeepAwake(minutes: minutes) }
                    }
                    Button(t("Пока не выключу", "Until I stop")) { model.startKeepAwake(minutes: nil) }
                    if model.keepAwake.isOn {
                        Button(t("Стоп", "Stop"), role: .destructive) { model.stopKeepAwake() }
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)
                if let reason = energy.activeReason {
                    Label(t("Mac не уснёт: ", "Mac stays awake: ") + reason, systemImage: "cup.and.saucer.fill")
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.orange.color)
                }
            }
            .appear(order: 0).scrollFade()

            SectionTitle(text: t("Не засыпать, пока…", "Stay awake while…")).appear(order: 1)
            LumoCard {
                SettingToggle(symbol: "powerplug.fill", colors: [Palette.green.color, Palette.mint.color],
                              title: t("Mac на зарядке", "Mac is plugged in"), isOn: $energy.awakeOnPower)
                Divider().opacity(0.4)
                SettingToggle(symbol: "display.2", colors: [Palette.blue.color, Palette.indigo.color],
                              title: t("Подключён внешний монитор", "An external display is connected"), isOn: $energy.awakeWithDisplay)
            }
            .appear(order: 2).scrollFade()
            SectionTitle(text: t("…или открыто приложение", "…or an app is open"), trailing: "\(energy.awakeApps.count)").appear(order: 3)
            AppToggleList(selected: energy.awakeApps) { energy.toggleApp($0) }.appear(order: 4)

            SectionTitle(text: t("Крышка и Bluetooth", "Lid & Bluetooth")).appear(order: 5)
            LumoCard {
                SettingToggle(symbol: "laptopcomputer", colors: [Palette.purple.color, Palette.pink.color],
                              title: t("Работать с закрытой крышкой", "Keep running with the lid closed"),
                              subtitle: t("Без внешнего монитора. macOS спросит пароль администратора при каждом изменении. Следите за температурой в сумке.",
                                          "Even without an external display. macOS asks for the admin password on each change. Mind the heat in a bag."),
                              isOn: Binding(get: { energy.lidSleepDisabled }, set: { energy.setLidSleepDisabled($0) }))
                    .disabled(energy.isChangingLid)
                Divider().opacity(0.4)
                SettingToggle(symbol: "dot.radiowaves.left.and.right", colors: [Palette.blue.color, Palette.cyan.color],
                              title: t("Bluetooth выключать во сне", "Bluetooth off during sleep"),
                              subtitle: t("И включать при пробуждении — только если его выключил Lumo", "And back on at wake — only if Lumo turned it off"),
                              isOn: $energy.bluetoothOnSleep)
            }
            .appear(order: 6).scrollFade()
        }
        .onAppear { energy.refreshLidState() }
    }
}

struct DisplaysPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var displays: DisplayTools

    var body: some View {
        let t = model.t
        TabScroll {
            ForEach(displays.displays) { display in
                LumoCard {
                    HStack {
                        Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display").foregroundStyle(Palette.yellow.color)
                        Text(display.name).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(display.isBuiltIn ? t("встроенный", "built-in") : display.hasDDC ? "DDC/CI" : t("программно", "software"))
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "sun.min").font(.system(size: 11)).foregroundStyle(.secondary)
                        GradientSlider(value: Binding(get: { display.brightness }, set: { displays.setBrightness(display, $0) }),
                                       colors: [Palette.orange.color, Palette.yellow.color], label: t("Яркость", "Brightness"))
                        Image(systemName: "sun.max.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text(t("Затемнение", "Dimming")).font(.system(size: 11))
                        Slider(value: Binding(get: { display.dimming }, set: { displays.setDimming(display, $0) }), in: 0...0.85)
                        Text(Format.percent(display.dimming)).font(.system(size: 10.5, design: .rounded)).monospacedDigit().frame(width: 36)
                    }
                }
                .scrollFade()
            }
            .appear(order: 0)

            SectionTitle(text: t("Клавиши яркости", "Brightness keys")).appear(order: 1)
            LumoCard {
                SettingRow(symbol: "dial.low.fill", colors: FeatureID.displays.colors, title: t("Шаг", "Step")) {
                    Picker("", selection: $displays.steps) {
                        Text(t("Обычный", "Normal")).tag(DisplayTools.StepMode.normal)
                        Text("½").tag(DisplayTools.StepMode.half)
                        Text("¼").tag(DisplayTools.StepMode.quarter)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 150)
                }
                Divider().opacity(0.4)
                SettingToggle(symbol: "moon.fill", colors: [Palette.indigo.color, Palette.purple.color],
                              title: t("Темнее минимума", "Darker than the minimum"),
                              subtitle: t("Когда яркость на нуле, клавиша добавляет программное затемнение", "At zero brightness the key adds software dimming"),
                              isOn: $displays.extraDimming)
                if displays.usesTap && !model.input.accessibilityGranted {
                    Text(t("Нужен «Универсальный доступ», чтобы видеть клавиши яркости", "Needs Accessibility to see the brightness keys"))
                        .font(.system(size: 10.5)).foregroundStyle(Palette.orange.color)
                }
            }
            .appear(order: 2).scrollFade()

            SectionTitle(text: t("Экстра-яркость XDR", "XDR extra brightness")).appear(order: 3)
            LumoCard {
                if displays.supportsXDR {
                    SettingToggle(symbol: "sun.max.trianglebadge.exclamationmark.fill", colors: [Palette.yellow.color, Palette.orange.color],
                                  title: t("Ярче максимума", "Brighter than maximum"),
                                  subtitle: t("Использует запас HDR экрана XDR. Расходует больше батареи.", "Uses the XDR display's HDR headroom. Uses more battery."),
                                  isOn: $displays.xdrBoost)
                    if displays.xdrBoost {
                        Slider(value: $displays.boost, in: 1.1...2.0)
                    }
                } else {
                    Text(t("У этого экрана нет запаса HDR — функция для MacBook Pro с XDR-дисплеем.",
                           "This screen has no HDR headroom — the feature is for MacBook Pro XDR displays."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .appear(order: 4).scrollFade()
        }
        .onAppear { displays.refresh() }
    }
}
