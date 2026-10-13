import AppKit
import SwiftUI

struct DockPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var input: InputFeatures
    @ObservedObject var dock: DockTools

    var body: some View {
        let t = model.t
        TabScroll {
            if dock.usesAccessibility && !input.accessibilityGranted {
                PermissionCard(permission: .accessibility,
                               reason: t("Чтобы видеть иконки Dock под курсором и управлять окнами.", "To see Dock icons under the pointer and manage windows."))
                    .appear(order: 0)
            }
            if dock.previewEnabled && !input.screenRecordingGranted {
                PermissionCard(permission: .screenRecording,
                               reason: t("Для миниатюр окон в превью. Без неё будут иконки.", "For window thumbnails in previews. Without it you get icons."))
                    .appear(order: 0)
            }
            SectionTitle(text: "Dock").appear(order: 1)
            LumoCard {
                SettingToggle(symbol: "rectangle.on.rectangle", colors: FeatureID.dock.colors,
                              title: t("Превью окон при наведении", "Window previews on hover"),
                              subtitle: t("Окна со всех рабочих столов: переключить, закрыть, прилепить к краю", "Windows from every desktop: switch, close, snap"),
                              isOn: $dock.previewEnabled)
                Divider().opacity(0.4)
                SettingRow(symbol: "cursorarrow.click.2", colors: [Palette.purple.color, Palette.pink.color],
                           title: t("Клик по иконке активного приложения", "Click on the active app's icon")) {
                    Picker("", selection: $dock.clickAction) {
                        Text(t("Ничего", "Nothing")).tag(DockTools.ClickAction.none)
                        Text(t("Свернуть окна", "Minimize windows")).tag(DockTools.ClickAction.minimize)
                        Text(t("Скрыть приложение", "Hide the app")).tag(DockTools.ClickAction.hide)
                        Text(t("Листать окна", "Cycle windows")).tag(DockTools.ClickAction.cycle)
                    }
                    .labelsHidden().fixedSize()
                }
            }
            .appear(order: 2).scrollFade()

            SectionTitle(text: t("Окна и рабочие столы", "Windows & Spaces")).appear(order: 3)
            LumoCard {
                SettingToggle(symbol: "plus.rectangle.fill", colors: [Palette.green.color, Palette.mint.color],
                              title: t("Зелёная кнопка — на весь экран", "Green button fills the screen"),
                              subtitle: t("Без нового рабочего стола; повторный клик вернёт размер. С ⌥ — как обычно.",
                                          "No new Space; click again to restore. Hold ⌥ for the usual behavior."),
                              isOn: $dock.greenMaximize)
                Divider().opacity(0.4)
                SettingToggle(symbol: "square.stack.3d.up.fill", colors: [Palette.blue.color, Palette.indigo.color],
                              title: t("Постоянный порядок рабочих столов", "Keep Spaces in order"),
                              subtitle: t("macOS перестанет переставлять их по недавнему использованию. Dock перезапустится на секунду.",
                                          "macOS stops reordering them by recent use. The Dock restarts for a second."),
                              isOn: $dock.fixedSpaces)
            }
            .appear(order: 4).scrollFade()

            SectionTitle(text: t("Выходить при закрытии последнего окна", "Quit when the last window closes"),
                         trailing: "\(dock.quitOnClose.count)").appear(order: 5)
            LumoCard {
                let apps = NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
                    .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
                ForEach(apps, id: \.processIdentifier) { app in
                    if let id = app.bundleIdentifier {
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon ?? NSImage()).resizable().frame(width: 22, height: 22)
                            Text(app.localizedName ?? id).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            Toggle(id, isOn: Binding(get: { dock.quitOnClose.contains(id) }, set: { _ in dock.toggleQuitOnClose(id) }))
                                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        }
                    }
                }
            }
            .appear(order: 6)
        }
    }
}
