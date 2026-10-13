import AppKit
import SwiftUI

// MARK: - Outputs & microphone

struct AudioPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var audio: AudioDevices

    var body: some View {
        let t = model.t
        TabScroll {
            SectionTitle(text: t("Выход звука", "Sound output")).appear(order: 0)
            LumoCard {
                ForEach(audio.outputs) { device in
                    deviceRow(device, selected: device.id == audio.defaultOutput) { audio.setOutput(device) }
                }
                Divider().opacity(0.4)
                SettingToggle(symbol: "keyboard.fill", colors: FeatureID.audio.colors,
                              title: t("Следующий выход по ⌃⌥⌘O", "Next output with ⌃⌥⌘O"), isOn: $audio.outputHotKey)
                Divider().opacity(0.4)
                SettingToggle(symbol: "headphones", colors: [Palette.orange.color, Palette.yellow.color],
                              title: t("Тише, когда наушники отключились", "Quieter when headphones disconnect"),
                              subtitle: t("Динамики не заорут на весь офис", "Speakers won't blast the whole room"),
                              isOn: $audio.headphoneGuard)
                if audio.headphoneGuard {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                        GradientSlider(value: $audio.guardVolume, colors: [Palette.green.color, Palette.orange.color],
                                       label: t("Громкость", "Volume"))
                        Text(Format.percent(audio.guardVolume)).font(.system(size: 11, design: .rounded)).monospacedDigit().frame(width: 38)
                    }
                }
            }
            .appear(order: 1).scrollFade()
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: audio.headphoneGuard)

            SectionTitle(text: t("Микрофон", "Microphone")).appear(order: 2)
            LumoCard {
                ForEach(audio.inputs) { device in
                    deviceRow(device, selected: device.id == audio.defaultInput) { audio.setInput(device) }
                }
                if let level = audio.inputLevel {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                        GradientSlider(value: Binding(get: { level }, set: { audio.setInputLevel($0) }),
                                       colors: [Palette.cyan.color, Palette.blue.color], label: t("Уровень входа", "Input level"))
                        Text(Format.percent(level)).font(.system(size: 11, design: .rounded)).monospacedDigit().frame(width: 38)
                    }
                }
                Divider().opacity(0.4)
                SettingRow(symbol: "star.fill", colors: [Palette.yellow.color, Palette.orange.color],
                           title: t("Предпочитать", "Prefer"),
                           subtitle: t("Lumo вернёт его, как только он подключится", "Lumo switches back whenever it's connected")) {
                    Picker("", selection: $audio.preferredInputUID) {
                        Text(t("Как в системе", "System choice")).tag(String?.none)
                        ForEach(audio.inputs) { Text($0.name).tag(Optional($0.uid)) }
                    }
                    .labelsHidden().frame(maxWidth: 150)
                }
                Divider().opacity(0.4)
                SettingToggle(symbol: "mic.slash.fill", colors: [Palette.red.color, Palette.pink.color],
                              title: t("Выключить все микрофоны ⌃⌥⌘M", "Mute every mic with ⌃⌥⌘M"),
                              subtitle: t("Для созвонов: одно нажатие — тишина везде", "For calls: one press, silence everywhere"),
                              isOn: $audio.muteHotKey)
                Button { audio.toggleMicsMuted() } label: {
                    Label(audio.micsMuted ? t("Включить микрофоны", "Unmute microphones") : t("Выключить сейчас", "Mute now"),
                          systemImage: audio.micsMuted ? "mic.fill" : "mic.slash.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(audio.micsMuted ? Palette.green.color : Palette.red.color)
            }
            .appear(order: 3).scrollFade()

            SectionTitle(text: "Music").appear(order: 4)
            if audio.musicBlocker && !AXIsProcessTrusted() {
                PermissionCard(permission: .accessibility,
                               reason: t("Чтобы заметить нажатие ▶︎ на клавиатуре или наушниках.", "To notice ▶︎ presses on the keyboard or headphones."))
            }
            LumoCard {
                SettingToggle(symbol: "music.note.house.fill", colors: [Palette.pink.color, Palette.red.color],
                              title: t("Не запускать Music от ▶︎", "Don't launch Music on ▶︎"),
                              subtitle: audio.blockedLaunches > 0
                                  ? t("Остановлено запусков: \(audio.blockedLaunches)", "Launches stopped: \(audio.blockedLaunches)")
                                  : t("Если Music открылась сама после кнопки воспроизведения, Lumo её закроет",
                                      "If Music opens by itself after a play press, Lumo closes it"),
                              isOn: $audio.musicBlocker)
            }
            .appear(order: 5).scrollFade()
        }
        .onAppear { audio.reload() }
    }

    private func deviceRow(_ device: AudioDevices.Device, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: device.symbol).font(.system(size: 13)).frame(width: 22)
                    .foregroundStyle(selected ? Palette.blue.color : .secondary)
                Text(device.name).font(.system(size: 12.5, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.blue.color) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
