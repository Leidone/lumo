import AppKit
import SwiftUI

// MARK: - Features hub

struct HubPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var hub: FeatureHub

    var body: some View {
        let t = model.t
        TabScroll {
            LumoCard {
                Text(t("Установите только то, чем пользуетесь. Убранные функции перестают работать и пропадают из списка; при возврате их настройки восстановятся.",
                       "Install only what you use. Removed features stop running and leave the list; adding one back restores its settings."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ForEach(FeatureHub.Preset.allCases) { preset in
                        Button(preset.title(t)) { hub.apply(preset) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                Divider().opacity(0.4)
                SettingToggle(symbol: "square.grid.3x3.fill", colors: [Palette.blue.color, Palette.cyan.color],
                              title: t("Компактная сетка", "Compact grid"), subtitle: t("Три плитки в ряд", "Three tiles per row"), isOn: $hub.compact)
                Divider().opacity(0.4)
                HStack {
                    Button { SettingsTransfer.export(t: t) } label: { Label(t("Экспорт настроек", "Export settings"), systemImage: "square.and.arrow.up") }
                    Button { SettingsTransfer.importSettings(t: t) } label: { Label(t("Импорт", "Import"), systemImage: "square.and.arrow.down") }
                }
                .buttonStyle(.borderless).font(.system(size: 11.5))
            }
            .appear(order: 0).scrollFade()

            ForEach(Array(hub.order.enumerated()), id: \.element) { index, category in
                SectionTitle(text: category.title(t))
                LumoCard {
                    HStack(spacing: 8) {
                        Toggle(t("Показывать раздел", "Show section"), isOn: Binding(get: { !hub.hiddenCategories.contains(category) }, set: { show in
                            hub.hiddenCategories = show ? hub.hiddenCategories.subtracting([category]) : hub.hiddenCategories.union([category])
                        }))
                        .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11.5))
                        Spacer()
                        Button { hub.move(category, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                        Button { hub.move(category, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(index == hub.order.count - 1)
                    }
                    .buttonStyle(.borderless)
                    ForEach(FeatureID.allCases.filter { $0.category == category }) { feature in
                        HStack(spacing: 10) {
                            IconBadge(symbol: feature.symbol, colors: feature.colors, size: 24)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(feature.title(t)).font(.system(size: 12, weight: .medium))
                                Text(feature.subtitle(t)).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle(feature.title(t), isOn: Binding(get: { hub.isInstalled(feature) }, set: { hub.setInstalled(feature, $0) }))
                                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        }
                    }
                }
                .scrollFade()
            }
        }
    }
}

// MARK: - Permissions

struct PermissionsPage: View {
    @EnvironmentObject private var model: AppModel
    @State private var tick = 0

    var body: some View {
        let t = model.t
        TabScroll {
            Text(t("Каждое разрешение необязательно. Здесь видно, зачем оно и какие ваши функции им пользуются.",
                   "Every permission is optional. Here's what each is for and which of your features use it."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .appear(order: 0)
            ForEach(Array(AppPermission.allCases.enumerated()), id: \.element) { index, permission in
                row(permission, t).appear(order: index + 1).scrollFade()
            }
        }
        .id(tick)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in tick += 1 }
    }

    private func row(_ permission: AppPermission, _ t: Localizer) -> some View {
        let status = permission.status
        let users = permission.usedBy(model)
        let unused = status == .granted && users.isEmpty
        return LumoCard {
            HStack(alignment: .top, spacing: 10) {
                IconBadge(symbol: permission.symbol, colors: status == .granted ? [Palette.green.color, Palette.mint.color]
                                                                               : [Palette.orange.color, Palette.pink.color], size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(permission.title(t)).font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Text(statusText(status, t)).font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(status == .granted ? Palette.green.color : status == .missing ? Palette.orange.color : .secondary)
                    }
                    Text(permission.purpose(t)).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !users.isEmpty {
                        Text(t("Нужно для: ", "Used by: ") + users.map { $0.title(t) }.joined(separator: ", "))
                            .font(.system(size: 10.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    }
                    if unused {
                        Text(t("Сейчас ни одна включённая функция его не использует — можно отозвать.", "No enabled feature uses it now — you can revoke it."))
                            .font(.system(size: 10.5)).foregroundStyle(Palette.orange.color)
                    }
                }
            }
            HStack {
                Spacer()
                Button(unused ? t("Отозвать в Настройках", "Revoke in Settings") : status == .granted ? t("Открыть Настройки", "Open Settings") : t("Разрешить", "Allow")) {
                    if permission == .screenRecording, status != .granted { CGRequestScreenCaptureAccess() }
                    if permission == .accessibility, status != .granted { Permission.accessibility.request() }
                    NSWorkspace.shared.open(permission.settingsURL)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private func statusText(_ status: AppPermission.Status, _ t: Localizer) -> String {
        switch status {
        case .granted: return t("разрешено", "allowed")
        case .missing: return t("нет", "off")
        case .unknown: return t("спросит при первом использовании", "asked on first use")
        }
    }
}
