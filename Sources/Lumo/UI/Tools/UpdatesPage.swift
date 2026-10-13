import AppKit
import LumoCore
import SwiftUI

struct UpdatesPage: View {
    enum Section: String, CaseIterable, Identifiable {
        case updates, install, installed

        var id: Self { self }
    }

    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: BrewStore
    @State private var section: Section = .updates
    @State private var query = ""

    var body: some View {
        let t = model.t
        VStack(spacing: 8) {
            if store.hasBrew {
                PillPicker(options: Section.allCases, selection: $section) { title($0, t) }
                    .padding(.horizontal, 16)
            }
            TabScroll(topInset: 2) {
                if section == .updates || !store.hasBrew {
                    FeedUpdatesCard(feeds: model.feedUpdates)
                }
                if let error = store.lastError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.orange.color)
                        Text(error).font(.system(size: 10.5)).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button { store.lastError = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.orange.color.opacity(0.13)))
                }
                if !store.hasBrew {
                    noBrew(t)
                } else {
                    switch section {
                    case .updates: updates(t)
                    case .install: install(t)
                    case .installed: installed(t)
                    }
                }
            }
            .id(section)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.25), value: section)
        .onAppear { if store.lastChecked == nil { store.refresh() } }
    }

    private func title(_ section: Section, _ t: Localizer) -> String {
        switch section {
        case .updates: return t("Обновления", "Updates")
        case .install: return t("Найти", "Find")
        case .installed: return t("Установлено", "Installed")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func updates(_ t: Localizer) -> some View {
        LumoCard(padding: 16) {
            HStack(spacing: 14) {
                IconBadge(symbol: store.updateCount > 0 ? "arrow.down.circle.fill" : "checkmark.seal.fill",
                          colors: store.updateCount > 0 ? FeatureID.updates.colors : [Palette.green.color, Palette.mint.color], size: 46)
                    .symbolEffect(.bounce, value: store.updateCount)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.isRefreshing ? t("Проверяю…", "Checking…")
                         : store.updateCount > 0 ? t("Доступно обновлений: \(store.updateCount)", "\(store.updateCount) updates available")
                         : t("Всё актуально", "Everything is up to date"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(store.lastChecked.map { t("Проверено в \($0.formatted(date: .omitted, time: .shortened))",
                                                   "Checked at \($0.formatted(date: .omitted, time: .shortened))") } ?? "")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Button { store.refresh(updateIndex: true) } label: {
                    Label(t("Проверить", "Check"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .disabled(store.isRefreshing)
                Button { store.upgradeAll() } label: {
                    Label(t("Обновить всё", "Update all"), systemImage: "arrow.down.to.line").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.updateCount == 0 || store.busy.contains("all"))
            }
            .controlSize(.large)
        }
        .appear(order: 0).scrollFade()

        if !store.outdated.isEmpty {
            SectionTitle(text: "Homebrew", trailing: "\(store.outdated.count)").appear(order: 1)
            ForEach(store.outdated) { package in
                packageRow(package, detail: versions(package.installedVersion, package.latestVersion)) {
                    actionButton(busy: store.busy.contains(package.id) || store.busy.contains("all"),
                                 title: t("Обновить", "Update")) { store.upgrade(package) }
                }
                .modifier(ListRow())
                .scrollFade()
            }
        }

        SectionTitle(text: "App Store", trailing: store.storeUpdates.isEmpty ? nil : "\(store.storeUpdates.count)").appear(order: 3)
        LumoCard {
            if store.masPath == nil {
                SettingRow(symbol: "bag.fill", colors: [Palette.blue.color, Palette.cyan.color],
                           title: t("Нужна утилита mas", "Needs the mas tool"),
                           subtitle: t("Чтобы видеть обновления App Store здесь", "To see App Store updates here")) {
                    actionButton(busy: store.busy.contains("formula:mas"), title: t("Установить", "Install")) {
                        store.install(BrewPackage(name: "mas", isCask: false, installedVersion: nil, latestVersion: nil))
                    }
                }
            }
            ForEach(store.storeUpdates) { update in
                packageRow(name: update.name, isCask: true, detail: versions(update.installedVersion, update.latestVersion)) {
                    actionButton(busy: store.busy.contains(update.id), title: t("Обновить", "Update")) { store.upgrade(update) }
                }
            }
            Button { store.openAppStoreUpdates() } label: {
                Label(t("Открыть обновления в App Store", "Open App Store updates"), systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless).font(.system(size: 11, weight: .medium))
        }
        .appear(order: 4).scrollFade()
    }

    @ViewBuilder
    private func install(_ t: Localizer) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField(t("Пакет или приложение, например wget или firefox", "Package or app, e.g. wget or firefox"), text: $query)
                .textFieldStyle(.plain).font(.system(size: 12))
                .onSubmit { store.search(query) }
            if store.isSearching { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Capsule().fill(Color.primary.opacity(0.06)))

        if store.searchResults.isEmpty {
            Text(t("Введите название и нажмите ↩︎", "Type a name and press ↩︎"))
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 20)
        } else {
            ForEach(store.searchResults) { package in
                let installed = store.isInstalled(package)
                packageRow(package, detail: installed ? t("Установлено", "Installed") : nil) {
                    if installed {
                        actionButton(busy: store.busy.contains(package.id), title: t("Удалить", "Remove"), destructive: true) {
                            store.uninstall(package)
                        }
                    } else {
                        actionButton(busy: store.busy.contains(package.id), title: t("Установить", "Install")) { store.install(package) }
                    }
                }
                .modifier(ListRow())
                .scrollFade()
            }
        }
    }

    @ViewBuilder
    private func installed(_ t: Localizer) -> some View {
        let casks = store.installedCasks.map { BrewPackage(name: $0, isCask: true, installedVersion: nil, latestVersion: nil) }
        let formulae = store.installedFormulae.map { BrewPackage(name: $0, isCask: false, installedVersion: nil, latestVersion: nil) }
        ForEach([(t("Приложения (casks)", "Apps (casks)"), casks), (t("Утилиты (formulae)", "Tools (formulae)"), formulae)], id: \.0) { title, packages in
            if !packages.isEmpty {
                SectionTitle(text: title, trailing: "\(packages.count)")
                ForEach(packages) { package in
                    packageRow(package, detail: nil) {
                        actionButton(busy: store.busy.contains(package.id), title: t("Удалить", "Remove"), destructive: true) {
                            store.uninstall(package)
                        }
                    }
                    .modifier(ListRow())
                    .scrollFade()
                }
            }
        }
    }

    @ViewBuilder
    private func noBrew(_ t: Localizer) -> some View {
        LumoCard(padding: 18) {
            IconBadge(symbol: "mug.fill", colors: [Palette.orange.color, Palette.yellow.color], size: 46)
            Text(t("Homebrew не найден", "Homebrew isn't installed")).font(.system(size: 15, weight: .bold, design: .rounded))
            Text(t("Homebrew — менеджер пакетов для Mac. Установите его с brew.sh, и Lumo сможет обновлять и ставить программы в один клик.",
                   "Homebrew is the package manager for Mac. Install it from brew.sh and Lumo can update and install software in one click."))
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { if let url = URL(string: "https://brew.sh") { NSWorkspace.shared.open(url) } } label: {
                Label(t("Открыть brew.sh", "Open brew.sh"), systemImage: "safari")
            }
            .controlSize(.large)
            Button { store.openAppStoreUpdates() } label: {
                Label(t("Обновления App Store", "App Store updates"), systemImage: "bag")
            }
        }
    }

    // MARK: Rows

    private func packageRow<Action: View>(_ package: BrewPackage, detail: String?, @ViewBuilder action: () -> Action) -> some View {
        packageRow(name: package.name, isCask: package.isCask, detail: detail, action: action)
    }

    private func packageRow<Action: View>(name: String, isCask: Bool, detail: String?, @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 10) {
            IconBadge(symbol: isCask ? "app.fill" : "terminal.fill",
                      colors: isCask ? [Palette.blue.color, Palette.indigo.color] : [Palette.orange.color, Palette.yellow.color], size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let detail { Text(detail).font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 6)
            action()
        }
    }

    private func actionButton(busy: Bool, title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Group {
            if busy {
                ProgressView().controlSize(.small).frame(width: 70)
            } else {
                Button(title, role: destructive ? .destructive : nil, action: action)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }
        }
        .transition(.opacity)
    }

    private func versions(_ installed: String?, _ latest: String?) -> String {
        [installed, latest].compactMap { $0 }.joined(separator: " → ")
    }
}

/// Standalone list row chrome, so long lists scroll row by row instead of as one giant card.
struct ListRow: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.07 : 0.04)))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Apps that update themselves (Sparkle): Lumo reads their feeds and opens the app's own updater.
struct FeedUpdatesCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var feeds: FeedUpdates

    var body: some View {
        let t = model.t
        LumoCard {
            HStack {
                IconBadge(symbol: "arrow.triangle.2.circlepath", colors: [Palette.purple.color, Palette.blue.color], size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t("Приложения со своими обновлениями", "Apps that update themselves")).font(.system(size: 12.5, weight: .semibold))
                    Text(feeds.lastCheck == nil ? t("Проверяет фиды разработчиков", "Checks developers' update feeds")
                                                : t("Проверено приложений: \(feeds.checkedApps)", "Checked \(feeds.checkedApps) apps"))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer()
                if feeds.isChecking { ProgressView().controlSize(.small) } else {
                    Button(t("Проверить", "Check")) { feeds.check() }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            ForEach(feeds.updates) { update in
                HStack(spacing: 10) {
                    Image(nsImage: IconCache.icon(for: update.app.path)).resizable().frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(update.name).font(.system(size: 12, weight: .medium))
                        Text("\(update.installed) → \(update.latest)").font(.system(size: 10.5, design: .rounded)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(t("Обновить", "Update")) { feeds.openUpdater(update) }.buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
            if feeds.lastCheck != nil && feeds.updates.isEmpty && !feeds.isChecking {
                Text(t("Всё свежее", "Everything is up to date")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .onAppear { if feeds.lastCheck == nil { feeds.check() } }
    }
}

struct MessagingPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var messaging: MessagingDownloads

    var body: some View {
        let t = model.t
        TabScroll {
            LumoCard {
                SettingRow(symbol: "calendar.badge.clock", colors: FeatureID.messaging.colors, title: t("Хранить", "Keep for")) {
                    Picker("", selection: $messaging.retentionDays) {
                        ForEach([7, 14, 30, 90, 180], id: \.self) { Text(t("\($0) дн.", "\($0) days")).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                Divider().opacity(0.4)
                SettingToggle(symbol: "sparkles", colors: [Palette.green.color, Palette.mint.color],
                              title: t("Убирать старое раз в неделю", "Clear old files weekly"),
                              subtitle: t("В Корзину, оттуда можно вернуть", "To the Trash, so it can be restored"), isOn: $messaging.autoClean)
            }
            .appear(order: 0).scrollFade()

            if messaging.sources.isEmpty && !messaging.isScanning {
                Text(t("Папки загрузок Telegram, WhatsApp, Viber и WeChat не найдены", "No Telegram, WhatsApp, Viber or WeChat download folders found"))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            ForEach(messaging.sources) { source in
                LumoCard {
                    HStack {
                        Text(source.name).font(.system(size: 14, weight: .bold, design: .rounded))
                        Spacer()
                        Text(Format.bytes(source.bytes)).font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    Text(t("Файлов: \(source.files) · старше срока: \(source.oldFiles) (\(Format.bytes(source.oldBytes)))",
                           "\(source.files) files · \(source.oldFiles) past the limit (\(Format.bytes(source.oldBytes)))"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack {
                        Button(t("Показать", "Show")) { NSWorkspace.shared.open(source.folder) }
                        Button(t("Разложить по папкам", "Organize")) { messaging.organize(source) }
                        Spacer()
                        Button(t("Старое в Корзину", "Old to Trash")) { messaging.trashOld(source) }
                            .buttonStyle(.borderedProminent).tint(Palette.orange.color).disabled(source.oldFiles == 0)
                    }
                    .controlSize(.small)
                }
                .scrollFade()
            }
            if messaging.isScanning { ProgressView().controlSize(.small) }
        }
        .onAppear { messaging.scan() }
    }
}
