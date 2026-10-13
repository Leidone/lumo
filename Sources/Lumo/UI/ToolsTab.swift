import SwiftUI

/// The tools hub: categories of feature tiles; a tile pushes its page with a slide.
/// Where the Tools tab is: the grid, one tool, or the hub/permissions pages.
enum ToolsRoute: Equatable {
    case feature(FeatureID), hub, permissions
}

struct ToolsTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var page: ToolsRoute?

    var body: some View {
        ZStack {
            if let page {
                FeaturePage(route: page) { navigate(to: nil) }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            } else {
                ToolsHome(hub: model.hub) { navigate(to: $0) }
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .clipped()
    }

    private func navigate(to route: ToolsRoute?) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) { page = route }
    }
}

private struct ToolsHome: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var hub: FeatureHub
    let open: (ToolsRoute) -> Void

    var body: some View {
        let t = model.t
        let columns = Array(repeating: GridItem(.flexible(), spacing: hub.compact ? 8 : 10), count: hub.compact ? 3 : 2)
        TabScroll {
            HStack(spacing: 8) {
                shortcut("square.grid.2x2.fill", t("Функции", "Features")) { open(.hub) }
                shortcut("lock.shield.fill", t("Разрешения", "Permissions")) { open(.permissions) }
            }
            .appear(order: 0)
            ForEach(Array(hub.visibleCategories.enumerated()), id: \.element) { index, category in
                let features = hub.features(in: category)
                if !features.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: category.title(t))
                        LazyVGrid(columns: columns, spacing: hub.compact ? 8 : 10) {
                            ForEach(features) { feature in
                                ToolTile(feature: feature, badge: badge(for: feature), compact: hub.compact) { open(.feature(feature)) }
                                    .scrollFade()
                            }
                        }
                    }
                    .appear(order: index + 1)
                }
            }
        }
    }

    private func shortcut(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 11.5, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(PressScaleStyle())
    }

    private func badge(for feature: FeatureID) -> String? {
        switch feature {
        case .updates: return model.brew.updateCount > 0 ? "\(model.brew.updateCount)" : nil
        case .sensors: return model.sensors.socTemperature.map { "\(Int($0.rounded()))°" }
        case .cleaner:
            let bytes = model.cleaner.findings.values.reduce(0) { $0 + $1.bytes }
            return bytes > 0 ? Format.bytes(bytes) : nil
        default: return nil
        }
    }
}

private struct ToolTile: View {
    @EnvironmentObject private var model: AppModel
    let feature: FeatureID
    let badge: String?
    var compact = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let t = model.t
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    IconBadge(symbol: feature.symbol, colors: feature.colors, size: 32)
                    Spacer()
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(LinearGradient(colors: feature.colors, startPoint: .leading, endPoint: .trailing)))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(feature.title(t)).font(.system(size: compact ? 11 : 12.5, weight: .semibold)).lineLimit(compact ? 2 : 1)
                    if !compact {
                        Text(feature.subtitle(t)).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(compact ? 9 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.02)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 0.7))
            .scaleEffect(hovering ? 1.025 : 1)
            .shadow(color: (feature.colors.last ?? .clear).opacity(hovering ? 0.25 : 0), radius: 12, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovering)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: badge)
    }
}

/// A pushed tool page: back button, title, then the tool itself.
private struct FeaturePage: View {
    @EnvironmentObject private var model: AppModel
    let route: ToolsRoute
    let back: () -> Void

    private var title: String {
        switch route {
        case .feature(let feature): return feature.title(model.t)
        case .hub: return model.t("Функции", "Features")
        case .permissions: return model.t("Разрешения", "Permissions")
        }
    }

    private var badge: (String, [Color]) {
        switch route {
        case .feature(let feature): return (feature.symbol, feature.colors)
        case .hub: return ("square.grid.2x2.fill", [Palette.blue.color, Palette.purple.color])
        case .permissions: return ("lock.shield.fill", [Palette.orange.color, Palette.pink.color])
        }
    }

    var body: some View {
        let t = model.t
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button(action: back) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                        Text(t("Инструменты", "Tools")).font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Palette.blue.color)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                Spacer()
                Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
                IconBadge(symbol: badge.0, colors: badge.1, size: 22)
            }
            .padding(.horizontal, 18)
            .padding(.top, 2)
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch route {
        case .hub: HubPage(hub: model.hub)
        case .permissions: PermissionsPage()
        case .feature(let feature): featureContent(feature)
        }
    }

    @ViewBuilder private func featureContent(_ feature: FeatureID) -> some View {
        switch feature {
        case .optimizer: OptimizerPage()
        case .cleaner: CleanerPage(store: model.cleaner)
        case .uninstaller: UninstallerPage(store: model.uninstaller)
        case .sensors: SensorsPage(store: model.sensors)
        case .network: NetworkPage(speedTest: model.speedTest)
        case .messaging: MessagingPage(messaging: model.messaging)
        case .updates: UpdatesPage(store: model.brew)
        case .readouts: ReadoutsPage()
        case .windowLayout: WindowLayoutPage(input: model.input)
        case .quitProtection: QuitProtectionPage(input: model.input)
        case .mouse: MousePage(input: model.input)
        case .keyboard: KeyboardPage(input: model.input, keyboard: model.input.keyboard)
        case .shortcuts: ShortcutsPage()
        case .appSwitcher: AppSwitcherPage(input: model.input)
        case .dock: DockPage(input: model.input, dock: model.input.dock)
        case .clipboard: ClipboardPage(store: model.clipboard)
        case .snippets: SnippetsPage(store: model.snippets)
        case .shelf: ShelfPage(shelf: model.shelf, panel: model.shelfPanel)
        case .fileTools: FileToolsPage(extras: model.clipExtras, installer: model.dmgInstaller)
        case .screenshot: ScreenshotPage(tools: model.capture)
        case .recorder: RecorderPage(recorder: model.recorder)
        case .mixer: MixerPage(mixer: model.mixer)
        case .audio: AudioPage(audio: model.audio)
        case .commandBar: CommandBarPage(bar: model.commandBar)
        case .island: IslandPage(island: model.island)
        case .notes: NotesPage(notes: model.notes, agents: model.agents)
        case .quickPanel: QuickActionsPage(panel: model.quickPanel, cleaning: model.cleaning)
        case .radial: RadialPage(menu: model.radial)
        case .keepAwake: EnergyPage(energy: model.power)
        case .displays: DisplaysPage(displays: model.displayTools)
        }
    }
}
