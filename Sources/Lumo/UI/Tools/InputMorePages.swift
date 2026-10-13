import AppKit
import LumoCore
import SwiftUI

// MARK: - Mouse

struct MousePage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var input: InputFeatures

    var body: some View {
        let t = model.t
        TabScroll {
            if input.usesAccessibility && !input.accessibilityGranted {
                PermissionCard(permission: .accessibility,
                               reason: t("Чтобы менять прокрутку и кнопки мыши.", "To change scrolling and mouse buttons."))
                    .appear(order: 0)
            }
            SectionTitle(text: t("Прокрутка", "Scrolling")).appear(order: 1)
            LumoCard {
                SettingToggle(symbol: "scroll.fill", colors: FeatureID.mouse.colors,
                              title: t("Плавная прокрутка", "Smooth scrolling"),
                              subtitle: t("Колесо мыши скользит, как трекпад", "The mouse wheel glides like a trackpad"), isOn: $input.smoothScroll)
                if input.smoothScroll {
                    HStack(spacing: 10) {
                        Text(t("Резко", "Snappy")).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        GradientSlider(value: $input.smoothness, colors: FeatureID.mouse.colors, label: t("Плавность", "Smoothness"))
                        Text(t("Плавно", "Silky")).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                Divider().opacity(0.4)
                SettingToggle(symbol: "line.3.horizontal", colors: [Palette.blue.color, Palette.indigo.color],
                              title: t("Линейная прокрутка", "Linear scrolling"),
                              subtitle: t("Каждый щелчок колеса — одинаковое число строк", "Every wheel notch scrolls the same number of lines"),
                              isOn: $input.linearScroll)
                if input.linearScroll {
                    Stepper(t("Строк за щелчок: \(input.linesPerNotch)", "Lines per notch: \(input.linesPerNotch)"),
                            value: $input.linesPerNotch, in: 1...12)
                        .font(.system(size: 12))
                }
                Divider().opacity(0.4)
                SettingToggle(symbol: "arrow.up.arrow.down", colors: [Palette.blue.color, Palette.cyan.color],
                              title: t("Обратный скролл мыши", "Reverse mouse scrolling"),
                              subtitle: t("По обеим осям, трекпад не меняется", "Both axes; the trackpad stays as is"), isOn: $input.reverseMouse)
                Divider().opacity(0.4)
                SettingRow(symbol: "arrow.left.and.right", colors: [Palette.purple.color, Palette.pink.color],
                           title: t("Вбок, пока зажата", "Sideways while holding"),
                           subtitle: t("Колесо прокручивает горизонтально", "The wheel scrolls horizontally")) {
                    Picker("", selection: $input.sideways) {
                        Text(t("Выкл.", "Off")).tag(SidewaysModifier.none)
                        Text("⇧").tag(SidewaysModifier.shift)
                        Text("⌥").tag(SidewaysModifier.option)
                        Text("⌃").tag(SidewaysModifier.control)
                    }
                    .labelsHidden().fixedSize()
                }
            }
            .appear(order: 2).scrollFade()
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: input.smoothScroll)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: input.linearScroll)

            SectionTitle(text: t("Кнопки и жесты", "Buttons & gestures")).appear(order: 3)
            LumoCard {
                SettingToggle(symbol: "computermouse.fill", colors: [Palette.purple.color, Palette.indigo.color],
                              title: t("Боковые кнопки: назад и вперёд", "Side buttons: back and forward"),
                              subtitle: t("В Finder, Safari и других", "In Finder, Safari and more"), isOn: $input.sideButtons)
                Divider().opacity(0.4)
                ForEach([(2, t("Средняя кнопка", "Middle button")), (3, t("Кнопка 4 (назад)", "Button 4 (back)")),
                         (4, t("Кнопка 5 (вперёд)", "Button 5 (forward)")), (5, t("Кнопка 6", "Button 6")), (6, t("Кнопка 7", "Button 7"))],
                        id: \.0) { button, title in
                    actionPicker(title, Binding(get: { input.buttonActions[button] ?? .none },
                                                set: { input.buttonActions[button] = $0 == .none ? nil : $0 }), t)
                }
                actionPicker(t("Колесо влево", "Wheel tilt left"), $input.tiltLeft, t)
                actionPicker(t("Колесо вправо", "Wheel tilt right"), $input.tiltRight, t)
                Divider().opacity(0.4)
                SettingToggle(symbol: "hand.draw.fill", colors: [Palette.orange.color, Palette.pink.color],
                              title: t("Жесты средней кнопкой", "Middle-button gestures"),
                              subtitle: t("Зажмите и ведите: ← → рабочие столы, ↑ Mission Control, ↓ окна приложения",
                                          "Hold and drag: ← → Spaces, ↑ Mission Control, ↓ App Exposé"),
                              isOn: $input.gestures)
                Divider().opacity(0.4)
                SettingToggle(symbol: "hand.point.up.braille.fill", colors: [Palette.cyan.color, Palette.blue.color],
                              title: t("Средний клик тремя пальцами", "Three-finger middle click"),
                              subtitle: t("Нажатие трекпада тремя пальцами", "Press the trackpad with three fingers"),
                              isOn: $input.threeFingerMiddleClick)
            }
            .appear(order: 4).scrollFade()

            SectionTitle(text: t("Поведение", "Behavior")).appear(order: 5)
            LumoCard {
                SettingToggle(symbol: "scope", colors: [Palette.green.color, Palette.mint.color],
                              title: t("Фокус за курсором", "Focus follows mouse"),
                              subtitle: t("Окно под курсором выходит вперёд после паузы", "The window under the pointer comes forward after a pause"),
                              isOn: $input.focusFollowsMouse)
                if input.focusFollowsMouse {
                    HStack {
                        Text(t("Пауза", "Pause")).font(.system(size: 11.5))
                        Slider(value: $input.focusDelay, in: 0.1...1.5, step: 0.1)
                        Text(String(format: "%.1f s", input.focusDelay)).font(.system(size: 11, design: .rounded)).monospacedDigit()
                    }
                }
                Divider().opacity(0.4)
                SettingToggle(symbol: "cursorarrow.click.badge.clock", colors: [Palette.red.color, Palette.orange.color],
                              title: t("Фильтр лишних кликов", "Extra click filter"),
                              subtitle: t("Для изношенных кнопок: игнорирует дребезг, обычные двойные клики работают",
                                          "For worn buttons: ignores chatter, normal double-clicks still work"),
                              isOn: $input.clickFilter)
                if input.clickFilter {
                    HStack {
                        Text(t("Порог", "Threshold")).font(.system(size: 11.5))
                        Slider(value: $input.clickThreshold, in: 0.02...0.12, step: 0.01)
                        Text("\(Int(input.clickThreshold * 1000)) ms").font(.system(size: 11, design: .rounded)).monospacedDigit()
                    }
                }
                Divider().opacity(0.4)
                SettingToggle(symbol: "cursorarrow.motionlines", colors: [Palette.orange.color, Palette.yellow.color],
                              title: t("Без ускорения указателя", "No pointer acceleration"),
                              subtitle: t("Курсор движется ровно за рукой; выключите, чтобы вернуть как было",
                                          "The pointer follows your hand 1:1; turn off to restore"),
                              isOn: $input.linearPointer)
            }
            .appear(order: 6).scrollFade()

            SectionTitle(text: t("Не трогать мышь в приложениях", "Leave the mouse alone in"), trailing: "\(input.mouseExclusions.count)")
                .appear(order: 7)
            AppToggleList(selected: input.mouseExclusions) { input.toggleMouseExclusion($0) }
                .appear(order: 8)
        }
    }

    private func actionPicker(_ title: String, _ selection: Binding<MouseAction>, _ t: Localizer) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Picker("", selection: selection) {
                ForEach(MouseAction.allCases) { Text($0.title(t)).tag($0) }
            }
            .labelsHidden().frame(maxWidth: 170)
        }
    }
}

/// Running apps with a switch each — used for exclusion lists.
struct AppToggleList: View {
    let selected: [String]
    let toggle: (String) -> Void

    var body: some View {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        LumoCard {
            ForEach(apps, id: \.processIdentifier) { app in
                if let id = app.bundleIdentifier {
                    HStack(spacing: 10) {
                        Image(nsImage: app.icon ?? NSImage()).resizable().frame(width: 22, height: 22)
                        Text(app.localizedName ?? id).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        Toggle(id, isOn: Binding(get: { selected.contains(id) }, set: { _ in toggle(id) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    }
                }
            }
        }
    }
}

// MARK: - Keyboard

struct KeyboardPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var input: InputFeatures
    @ObservedObject var keyboard: KeyboardTools

    var body: some View {
        let t = model.t
        TabScroll {
            if keyboard.usesTap && !input.accessibilityGranted {
                PermissionCard(permission: .accessibility, reason: t("Чтобы видеть нажатия клавиш.", "To see key presses."))
                    .appear(order: 0)
            }
            SectionTitle(text: "Super key").appear(order: 1)
            LumoCard {
                SettingRow(symbol: "capslock.fill", colors: FeatureID.keyboard.colors, title: t("Клавиша", "Key"),
                           subtitle: t("Зажата — работает как ⌃⌥⇧⌘ для любых сочетаний", "Held, it acts as ⌃⌥⇧⌘ for any shortcut")) {
                    Picker("", selection: $keyboard.superSource) {
                        Text(t("Выкл.", "Off")).tag(KeyboardTools.SuperSource.off)
                        Text("Caps Lock").tag(KeyboardTools.SuperSource.capsLock)
                        Text(t("Правая ⌘", "Right ⌘")).tag(KeyboardTools.SuperSource.rightCommand)
                        Text(t("Правая ⌥", "Right ⌥")).tag(KeyboardTools.SuperSource.rightOption)
                    }
                    .labelsHidden().fixedSize()
                }
                if keyboard.superSource != .off {
                    Divider().opacity(0.4)
                    SettingRow(symbol: "hand.tap.fill", colors: [Palette.pink.color, Palette.orange.color],
                               title: t("Если нажать отдельно", "When tapped alone")) {
                        Picker("", selection: $keyboard.tapAction) {
                            Text(t("Ничего", "Nothing")).tag(KeyboardTools.TapAction.none)
                            Text("Esc").tag(KeyboardTools.TapAction.escape)
                            Text("Command Bar").tag(KeyboardTools.TapAction.commandBar)
                            Text(t("Быстрая панель", "Quick panel")).tag(KeyboardTools.TapAction.quickPanel)
                        }
                        .labelsHidden().fixedSize()
                    }
                }
                if keyboard.superSource == .capsLock {
                    Text(t("Caps Lock переназначается через системный hidutil до перезагрузки; Lumo восстанавливает его при выходе.",
                           "Caps Lock is remapped with macOS's hidutil until restart; Lumo restores it when it quits."))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .appear(order: 2).scrollFade()

            SectionTitle(text: t("Без дребезга", "Key debounce")).appear(order: 3)
            LumoCard {
                SettingToggle(symbol: "keyboard.badge.ellipsis", colors: [Palette.red.color, Palette.pink.color],
                              title: t("Убирать двойные буквы", "Filter doubled letters"),
                              subtitle: t("Для изношенной клавиатуры: повтор той же клавиши слишком быстро игнорируется",
                                          "For a worn keyboard: the same key repeated too quickly is ignored"),
                              isOn: $keyboard.debounce)
                if keyboard.debounce {
                    HStack {
                        Text(t("Порог", "Threshold")).font(.system(size: 11.5))
                        Slider(value: $keyboard.debounceThreshold, in: 0.02...0.12, step: 0.01)
                        Text("\(Int(keyboard.debounceThreshold * 1000)) ms").font(.system(size: 11, design: .rounded)).monospacedDigit()
                    }
                }
            }
            .appear(order: 4).scrollFade()

            if keyboard.superSource != .off {
                SectionTitle(text: t("Super key не работает в", "Super key is off in"), trailing: "\(keyboard.superExclusions.count)")
                    .appear(order: 5)
                AppToggleList(selected: keyboard.superExclusions) { keyboard.toggleExclusion($0) }
                    .appear(order: 6)
            }
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store = ShortcutStore.shared

    var body: some View {
        let t = model.t
        TabScroll {
            LumoCard {
                SettingToggle(symbol: "camera.viewfinder", colors: FeatureID.screenshot.colors,
                              title: t("⌘⇧3/4/5 открывают инструменты Lumo", "⌘⇧3/4/5 open Lumo's tools"),
                              subtitle: t("Пока Lumo работает; при выходе системные сочетания возвращаются",
                                          "While Lumo runs; the system shortcuts come back when it quits"),
                              isOn: $store.takeoverScreenshots)
            }
            .appear(order: 0).scrollFade()

            ForEach(Array(ShortcutID.Group.allCases.enumerated()), id: \.element) { index, group in
                SectionTitle(text: title(group, t)).appear(order: index + 1)
                LumoCard {
                    ForEach(ShortcutID.allCases.filter { $0.group == group }) { id in
                        HStack {
                            Text(id.title(t)).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            ShortcutRecorder(id: id, t: t)
                        }
                    }
                }
                .appear(order: index + 1).scrollFade()
            }
            Text(t("Нажмите на сочетание и введите новое. Esc — отмена, ⌫ — выключить. Сочетание работает, когда включена его функция.",
                   "Click a shortcut and press a new one. Esc cancels, ⌫ turns it off. A shortcut works while its feature is on."))
                .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func title(_ group: ShortcutID.Group, _ t: Localizer) -> String {
        switch group {
        case .windows: return t("Окна", "Windows")
        case .capture: return t("Захват экрана", "Screen capture")
        case .everyday: return t("Каждый день", "Everyday")
        case .sound: return t("Звук", "Sound")
        }
    }
}
