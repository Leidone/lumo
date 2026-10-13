import AppKit
import LumoCore
import SwiftUI

/// Explains a missing permission in plain words, with a one-tap way to grant it.
struct PermissionCard: View {
    @EnvironmentObject private var model: AppModel
    let permission: Permission
    let reason: String

    var body: some View {
        let t = model.t
        LumoCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(symbol: permission == .accessibility ? "hand.raised.square.fill" : "rectangle.dashed.badge.record",
                          colors: [Palette.orange.color, Palette.pink.color], size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(permission == .accessibility ? t("Нужен «Универсальный доступ»", "Needs Accessibility access")
                                                      : t("Нужна «Запись экрана»", "Needs Screen Recording access"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(reason).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button { permission.request() } label: {
                    Label(t("Разрешить", "Allow"), systemImage: "checkmark.shield.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Text(t("Включите Lumo в открывшемся окне — Lumo подхватит разрешение сам.",
                   "Turn Lumo on in the window that opens — Lumo picks it up automatically."))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.orange.color.opacity(0.35)))
    }
}

// MARK: - Window layout

struct WindowLayoutPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var input: InputFeatures

    private static let sheet: [(ShortcutID, WindowAction?)] = [
        (.windowLeft, .leftHalf), (.windowRight, .rightHalf), (.windowTop, .topHalf), (.windowBottom, .bottomHalf),
        (.windowTopLeft, .topLeft), (.windowTopRight, .topRight), (.windowBottomLeft, .bottomLeft), (.windowBottomRight, .bottomRight),
        (.windowLeftThird, .leftThird), (.windowCenterThird, .centerThird), (.windowRightThird, .rightThird), (.windowMaximize, .maximize),
        (.windowCenter, .center), (.windowRestore, nil),
    ]

    var body: some View {
        let t = model.t
        TabScroll {
            if input.usesAccessibility && !input.accessibilityGranted {
                PermissionCard(permission: .accessibility,
                               reason: t("Чтобы двигать и менять размер окон других приложений.", "To move and resize other apps' windows."))
                    .appear(order: 0)
            }
            LumoCard {
                SettingToggle(symbol: "keyboard.fill", colors: FeatureID.windowLayout.colors,
                              title: t("Горячие клавиши ⌃⌥", "⌃⌥ shortcuts"),
                              subtitle: t("Половины, четверти, трети и не только", "Halves, quarters, thirds and more"),
                              isOn: $input.windowShortcuts)
                Divider().opacity(0.4)
                SettingToggle(symbol: "hand.draw.fill", colors: [Palette.purple.color, Palette.blue.color],
                              title: t("Прилипание к краям", "Snap to edges"),
                              subtitle: t("Тащите окно к краю или углу экрана", "Drag a window to an edge or corner"),
                              isOn: $input.snapByDragging)
                Divider().opacity(0.4)
                SettingToggle(symbol: "arrow.up.and.down.and.arrow.left.and.right", colors: [Palette.orange.color, Palette.pink.color],
                              title: t("Двигать с ⌃⌥ за любое место", "Move with ⌃⌥ from anywhere"),
                              subtitle: t("⌃⌥ + перетаскивание двигает окно, ⌃⌥⇧ — меняет размер", "⌃⌥ + drag moves a window, ⌃⌥⇧ resizes it"),
                              isOn: $input.modifierDrag)
            }
            .appear(order: 1).scrollFade()

            SectionTitle(text: t("Шпаргалка (меняется в «Сочетаниях»)", "Cheat sheet (change in Shortcuts)")).appear(order: 2)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Array(Self.sheet.enumerated()), id: \.offset) { _, entry in
                    VStack(spacing: 5) {
                        LayoutGlyph(action: entry.1)
                        Text(ShortcutStore.shared.binding(entry.0)?.display ?? "—").font(.system(size: 10, weight: .bold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
                }
            }
            .appear(order: 3).scrollFade()
            Text(t("⌃⌥⌘→ — перенести окно на следующий монитор. ⌫ возвращает прежний размер.",
                   "⌃⌥⌘→ moves the window to the next display. ⌫ restores its previous size."))
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }
}

/// A tiny screen with the target region lit up.
private struct LayoutGlyph: View {
    let action: WindowAction?

    var body: some View {
        let unit = CGRect(x: 0, y: 0, width: 40, height: 26)
        let target = action.map { WindowLayout.frame(for: $0, in: unit, current: CGRect(x: 10, y: 6, width: 20, height: 14)) }
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.1))
            if let target {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(LinearGradient(colors: FeatureID.windowLayout.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: max(target.width - 2, 2), height: max(target.height - 2, 2))
                    .offset(x: target.minX + 1, y: target.minY + 1)
            } else {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: unit.width, height: unit.height)
            }
        }
        .frame(width: unit.width, height: unit.height)
    }
}

// MARK: - Quit protection

struct QuitProtectionPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var input: InputFeatures

    var body: some View {
        let t = model.t
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        TabScroll {
            if input.usesAccessibility && !input.accessibilityGranted {
                PermissionCard(permission: .accessibility,
                               reason: t("Чтобы замечать ⌘Q и ⌘W до того, как их получит приложение.", "To catch ⌘Q and ⌘W before the app does."))
                    .appear(order: 0)
            }
            LumoCard {
                SettingToggle(symbol: "power", colors: FeatureID.quitProtection.colors,
                              title: t("Защитить ⌘Q", "Guard ⌘Q"), subtitle: t("Выход из приложения", "Quitting apps"),
                              isOn: $input.guardQuit)
                Divider().opacity(0.4)
                SettingToggle(symbol: "xmark.rectangle.fill", colors: [Palette.orange.color, Palette.pink.color],
                              title: t("Защитить ⌘W", "Guard ⌘W"), subtitle: t("Закрытие окна или вкладки", "Closing windows or tabs"),
                              isOn: $input.guardClose)
                Divider().opacity(0.4)
                HStack {
                    Text(t("Как подтверждать", "Confirm by")).font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    PillPicker(options: [QuitGuard.Mode.hold, .double], selection: $input.quitMode) {
                        $0 == .hold ? t("Удержанием", "Holding") : t("Двойным", "Pressing twice")
                    }
                    .frame(width: 200)
                }
            }
            .appear(order: 1).scrollFade()

            SectionTitle(text: t("Не защищать в приложениях", "Don't guard in"), trailing: "\(input.quitExceptions.count)").appear(order: 2)
            LumoCard {
                ForEach(apps, id: \.processIdentifier) { app in
                    if let id = app.bundleIdentifier {
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon ?? NSImage()).resizable().frame(width: 22, height: 22)
                            Text(app.localizedName ?? id).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            Toggle(id, isOn: Binding(get: { input.quitExceptions.contains(id) }, set: { _ in input.toggleException(id) }))
                                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        }
                    }
                }
            }
            .appear(order: 3)
        }
    }
}

extension QuitGuard.Mode: Identifiable {
    public var id: String { rawValue }
}

// MARK: - App switcher

struct AppSwitcherPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var input: InputFeatures

    var body: some View {
        let t = model.t
        TabScroll {
            if input.switcherEnabled && !input.accessibilityGranted {
                PermissionCard(permission: .accessibility,
                               reason: t("Чтобы перехватывать ⌘Tab и переключать приложения.", "To take over ⌘Tab and switch apps."))
                    .appear(order: 0)
            }
            if input.switcherEnabled && input.switcherPreviews && !input.screenRecordingGranted {
                PermissionCard(permission: .screenRecording,
                               reason: t("Только для миниатюр окон. Без него будут иконки — всё остальное работает.",
                                         "Only for window thumbnails. Without it you get icons — everything else works."))
                    .appear(order: 1)
            }
            LumoCard {
                SettingToggle(symbol: "command", colors: FeatureID.appSwitcher.colors,
                              title: t("Заменить ⌘Tab", "Replace ⌘Tab"),
                              subtitle: t("Большие превью и все приложения сразу", "Big previews, every app at a glance"),
                              isOn: $input.switcherEnabled)
                Divider().opacity(0.4)
                SettingToggle(symbol: "photo.on.rectangle.angled", colors: [Palette.cyan.color, Palette.blue.color],
                              title: t("Превью окон", "Window previews"), subtitle: t("Иначе — иконки приложений", "Otherwise app icons"),
                              isOn: $input.switcherPreviews)
                Divider().opacity(0.4)
                SettingToggle(symbol: "macwindow.on.rectangle", colors: [Palette.indigo.color, Palette.blue.color],
                              title: t("Каждое окно отдельно", "Every window separately"),
                              subtitle: t("Плитка на окно, а не на приложение", "One tile per window, not per app"),
                              isOn: $input.switcherPerWindow)
                Divider().opacity(0.4)
                SettingToggle(symbol: "display", colors: [Palette.mint.color, Palette.cyan.color],
                              title: t("Только этот дисплей", "This display only"),
                              subtitle: t("Приложения с окнами на мониторе под курсором", "Apps with windows on the display under the pointer"),
                              isOn: $input.switcherCurrentDisplay)
            }
            .appear(order: 2).scrollFade()

            SectionTitle(text: t("Управление", "Controls")).appear(order: 3)
            LumoCard {
                ForEach([("⌘ Tab", t("следующее приложение", "next app")), ("⇧ ⌘ Tab", t("предыдущее", "previous")),
                         ("← →", t("выбор стрелками", "move with arrows")), ("Q", t("закрыть выбранное", "quit the selected app")),
                         ("A–Z", t("поиск по имени, ⌫ стирает", "search by name, ⌫ erases")),
                         ("Esc", t("отмена", "cancel")), (t("Отпустить ⌘", "Release ⌘"), t("перейти", "switch"))], id: \.0) { key, text in
                    HStack {
                        Text(key).font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                        Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .appear(order: 4).scrollFade()
        }
    }
}
