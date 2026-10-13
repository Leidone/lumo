import AppKit
import LumoCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Quick actions

struct QuickActionsPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var panel: QuickPanel
    @ObservedObject var cleaning: CleaningMode

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        let t = model.t
        TabScroll {
            LumoCard {
                SettingToggle(symbol: "square.grid.3x3.fill", colors: FeatureID.quickPanel.colors,
                              title: t("Быстрая панель по ", "Quick panel on ") + (ShortcutStore.shared.binding(.quickPanel)?.display ?? ""),
                              subtitle: t("Палитра избранных инструментов посреди экрана", "A palette of favorite tools in the middle of the screen"),
                              isOn: $panel.isEnabled)
                Button { panel.toggle() } label: {
                    Label(t("Показать", "Show"), systemImage: "square.grid.3x3").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .appear(order: 0).scrollFade()

            SectionTitle(text: t("Все действия · ★ — в панели", "All actions · ★ — in the panel")).appear(order: 1)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(LumoTool.allCases) { tool in
                    VStack(spacing: 2) {
                        QuickToolButton(tool: tool, title: tool.title(t)) { tool.run(model) }
                            .frame(maxWidth: .infinity)
                        Button { panel.toggleFavorite(tool) } label: {
                            Image(systemName: panel.favorites.contains(tool) ? "star.fill" : "star")
                                .font(.system(size: 10)).foregroundStyle(panel.favorites.contains(tool) ? Palette.yellow.color : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
                }
            }
            .appear(order: 2)

            SectionTitle(text: t("Режим чистки", "Cleaning mode")).appear(order: 3)
            LumoCard {
                SettingRow(symbol: "keyboard.badge.eye", colors: [Palette.yellow.color, Palette.green.color],
                           title: t("Как показывать", "Show as"),
                           subtitle: t("Клавиатура и медиаклавиши блокируются, мышь работает — «Готово» вернёт всё", "Keys and media keys are locked, the mouse works — “Done” brings it back")) {
                    Picker("", selection: $cleaning.style) {
                        Text(t("Чёрный экран", "Black screen")).tag(CleaningMode.Style.blackScreen)
                        Text(t("Индикатор", "Indicator")).tag(CleaningMode.Style.indicator)
                    }
                    .labelsHidden().fixedSize()
                }
                Button { cleaning.start() } label: {
                    Label(t("Начать чистку", "Start cleaning"), systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .appear(order: 4).scrollFade()
        }
    }
}

// MARK: - Radial menu

struct RadialPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var menu: RadialMenu
    @State private var profileIndex = 0
    @State private var folder: UUID?

    var body: some View {
        let t = model.t
        TabScroll {
            LumoCard {
                SettingToggle(symbol: "circle.circle.fill", colors: FeatureID.radial.colors,
                              title: t("Колесо по ", "Wheel on ") + (ShortcutStore.shared.binding(.radialMenu)?.display ?? ""),
                              subtitle: t("Появляется вокруг курсора: наведите и щёлкните", "Appears around the pointer: hover and click"),
                              isOn: $menu.isEnabled)
            }
            .appear(order: 0).scrollFade()

            if menu.profiles.indices.contains(profileIndex) {
                HStack {
                    Picker("", selection: $profileIndex) {
                        ForEach(menu.profiles.indices, id: \.self) { Text(menu.profiles[$0].name).tag($0) }
                    }
                    .labelsHidden()
                    Button { addProfile(t) } label: { Image(systemName: "plus") }
                    if menu.profiles.count > 1 {
                        Button(role: .destructive) {
                            menu.profiles.remove(at: profileIndex)
                            profileIndex = 0
                        } label: { Image(systemName: "trash") }
                    }
                }
                .buttonStyle(.borderless)
                .appear(order: 1)

                profileEditor(t)
            }
        }
    }

    @ViewBuilder
    private func profileEditor(_ t: Localizer) -> some View {
        let binding = $menu.profiles[profileIndex]
        LumoCard {
            HStack {
                Text(t("Название", "Name")).font(.system(size: 12))
                TextField("", text: binding.name).textFieldStyle(.roundedBorder)
            }
            if profileIndex > 0 {
                Text(t("Работает в приложениях:", "Used in apps:")).font(.system(size: 11, weight: .medium))
                AppToggleList(selected: binding.wrappedValue.apps) { id in
                    var apps = binding.wrappedValue.apps
                    if let index = apps.firstIndex(of: id) { apps.remove(at: index) } else { apps.append(id) }
                    binding.wrappedValue.apps = apps
                }
            } else {
                Text(t("Основной профиль — когда для приложения нет своего", "Default profile — used when an app has none of its own"))
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
        .appear(order: 2)

        let items = folder.flatMap { id in binding.wrappedValue.items.first { $0.id == id }?.children } ?? binding.wrappedValue.items
        SectionTitle(text: folder == nil ? t("Секторы", "Slices") : t("Папка", "Folder"), trailing: "\(items.count)/\(RadialMenu.maxSlices)")
        LumoCard {
            if folder != nil {
                Button { folder = nil } label: { Label(t("Назад к секторам", "Back to slices"), systemImage: "chevron.backward") }
                    .buttonStyle(.borderless)
            }
            ForEach(items) { item in
                HStack(spacing: 10) {
                    Text(menu.title(of: item)).font(.system(size: 12)).lineLimit(1)
                    Text(kindTitle(item.kind, t)).font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    if item.kind == .submenu, folder == nil {
                        Button(t("Открыть", "Open")) { folder = item.id }.buttonStyle(.borderless)
                    }
                    Button(role: .destructive) { update { $0.removeAll { $0.id == item.id } } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            if items.count < RadialMenu.maxSlices {
                Menu {
                    Menu(t("Инструмент Lumo", "Lumo tool")) {
                        ForEach(LumoTool.allCases) { tool in
                            Button(tool.title(t)) { add(RadialItem(kind: .tool, value: tool.rawValue, title: "")) }
                        }
                    }
                    Button(t("Приложение…", "App…")) { pick(apps: true) }
                    Button(t("Файл или папку…", "File or folder…")) { pick(apps: false) }
                    Menu(t("Сочетание клавиш", "Key combo")) {
                        ForEach(Self.presetKeys, id: \.1) { binding, name in
                            Button("\(name) \(binding.display)") { add(RadialItem(kind: .keys, value: name, title: name, binding: binding)) }
                        }
                    }
                    if folder == nil {
                        Button(t("Папку с секторами", "A folder of slices")) { add(RadialItem(kind: .submenu, value: "", title: t("Папка", "Folder"))) }
                    }
                } label: {
                    Label(t("Добавить сектор", "Add slice"), systemImage: "plus.circle.fill")
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }
        .appear(order: 3)
    }

    private static let presetKeys: [(ShortcutBinding, String)] = [
        (ShortcutBinding(keyCode: 8, modifiers: [.command]), "Copy"), (ShortcutBinding(keyCode: 9, modifiers: [.command]), "Paste"),
        (ShortcutBinding(keyCode: 6, modifiers: [.command]), "Undo"), (ShortcutBinding(keyCode: 17, modifiers: [.command]), "New tab"),
        (ShortcutBinding(keyCode: 13, modifiers: [.command]), "Close"), (ShortcutBinding(keyCode: 1, modifiers: [.command]), "Save"),
        (ShortcutBinding(keyCode: 15, modifiers: [.command]), "Reload"), (ShortcutBinding(keyCode: 3, modifiers: [.command]), "Find"),
    ]

    private func kindTitle(_ kind: RadialItem.Kind, _ t: Localizer) -> String {
        switch kind {
        case .tool: return "Lumo"
        case .app: return t("приложение", "app")
        case .file: return t("файл", "file")
        case .keys: return t("клавиши", "keys")
        case .submenu: return t("папка", "folder")
        }
    }

    private func addProfile(_ t: Localizer) {
        menu.profiles.append(RadialProfile(name: t("Профиль \(menu.profiles.count + 1)", "Profile \(menu.profiles.count + 1)"),
                                           items: RadialMenu.defaultProfile.items))
        profileIndex = menu.profiles.count - 1
    }

    private func add(_ item: RadialItem) { update { $0.append(item) } }

    /// Edits the top-level slices or the open folder's.
    private func update(_ change: (inout [RadialItem]) -> Void) {
        var profile = menu.profiles[profileIndex]
        if let folder, let index = profile.items.firstIndex(where: { $0.id == folder }) {
            change(&profile.items[index].children)
        } else {
            change(&profile.items)
        }
        menu.profiles[profileIndex] = profile
    }

    private func pick(apps: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = !apps
        panel.allowsMultipleSelection = false
        if apps {
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(RadialItem(kind: apps ? .app : .file, value: url.path, title: ""))
    }
}

// MARK: - Command Bar scripts

struct ScriptsCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var bar: CommandBar
    @State private var name = ""
    @State private var command = ""

    var body: some View {
        let t = model.t
        LumoCard {
            ForEach(bar.scripts) { script in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(script.name).font(.system(size: 12, weight: .medium))
                        Text(script.command).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { bar.run(script) } label: { Image(systemName: "play.fill") }.buttonStyle(.borderless)
                    Button(role: .destructive) { bar.removeScript(script) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            TextField(t("Название, например «Обновить brew»", "Name, e.g. “Update brew”"), text: $name).textFieldStyle(.roundedBorder)
            TextField(t("Команда, например brew upgrade", "Command, e.g. brew upgrade"), text: $command)
                .textFieldStyle(.roundedBorder).font(.system(size: 11.5, design: .monospaced))
            Button(t("Добавить скрипт", "Add script")) {
                bar.addScript(name: name, command: command)
                name = ""
                command = ""
            }
            .disabled(name.isEmpty || command.isEmpty)
            Text(t("Скрипты запускаются в вашем zsh только по вашему выбору в Command Bar.", "Scripts run in your zsh only when you pick them in the Command Bar."))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}
