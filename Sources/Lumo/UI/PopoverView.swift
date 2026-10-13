import LumoCore
import SwiftUI

struct PopoverView: View {
    enum Tab: Int, CaseIterable, Identifiable {
        case overview, tools, processes, settings

        var id: Self { self }

        var symbol: String {
            switch self {
            case .overview: return "gauge.with.dots.needle.67percent"
            case .processes: return "square.stack.3d.up.fill"
            case .tools: return "square.grid.2x2.fill"
            case .settings: return "gearshape.fill"
            }
        }

        func title(_ t: Localizer) -> String {
            switch self {
            case .overview: return t("Обзор", "Overview")
            case .processes: return t("Процессы", "Processes")
            case .tools: return t("Инструменты", "Tools")
            case .settings: return t("Настройки", "Settings")
            }
        }
    }

    static let size = CGSize(width: 380, height: 620)

    @EnvironmentObject private var model: AppModel
    @State private var tab: Tab = .overview
    @State private var forward = true

    var body: some View {
        ZStack(alignment: .bottom) {
            AmbientBackground(level: healthLevel)
            VStack(spacing: 0) {
                HeaderBar()
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                if let error = model.errorMessage {
                    ErrorBanner(message: error) { model.errorMessage = nil }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                ZStack {
                    if model.onboardingDone {
                        content
                            .id(tab)
                        .transition(.asymmetric(
                            insertion: .offset(x: forward ? 44 : -44).combined(with: .opacity),
                            removal: .offset(x: forward ? -44 : 44).combined(with: .opacity)))
                    }
                }
                .frame(maxHeight: .infinity)
            }
            LumoTabBar(selection: tabBinding, t: model.t)
                .padding(.horizontal, 26)
                .padding(.bottom, 12)
            if !model.onboardingDone {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(2)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
        .overlay {
            if model.isOptimizing { IntelligenceGlow().padding(1) }
        }
        .animation(.easeInOut(duration: 0.45), value: model.isOptimizing)
        .animation(.spring(response: 0.55, dampingFraction: 0.86), value: model.onboardingDone)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.errorMessage)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .overview: OverviewTab()
        case .processes: ProcessesTab()
        case .tools: ToolsTab()
        case .settings: SettingsTab()
        }
    }

    private var tabBinding: Binding<Tab> {
        Binding(get: { tab }, set: { next in
            forward = next.rawValue > tab.rawValue
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { tab = next }
        })
    }

    private var healthLevel: Int {
        switch model.healthLoad {
        case ..<0.6: return 0
        case ..<0.85: return 1
        default: return 2
        }
    }
}

// MARK: - Chrome

private struct HeaderBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let t = model.t
        HStack(spacing: 11) {
            LumoGlyph(size: 30, isBusy: model.isOptimizing)
            VStack(alignment: .leading, spacing: 1) {
                Text("Lumo")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.brand)
                Text(status(t))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: status(t))
            }
            Spacer()
            if model.keepAwake.isOn {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.orange.color)
                    .padding(6)
                    .background(Circle().fill(Palette.orange.color.opacity(0.16)))
                    .symbolEffect(.pulse)
                    .help(t("Mac не засыпает", "Mac stays awake"))
                    .transition(.scale.combined(with: .opacity))
            }
            ThermalChip(state: model.snapshot.thermal, t: t)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: model.keepAwake)
    }

    private func status(_ t: Localizer) -> String {
        if model.isOptimizing { return t("Навожу порядок…", "Tidying up…") }
        switch model.healthLoad {
        case ..<0.6: return t("Всё спокойно", "All calm")
        case ..<0.85: return t("Умеренная нагрузка", "Moderate load")
        default: return t("Высокая нагрузка", "Heavy load")
        }
    }
}

/// Floating glass tab bar with a sliding gradient pill.
struct LumoTabBar: View {
    @Binding var selection: PopoverView.Tab
    let t: Localizer
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PopoverView.Tab.allCases) { tab in
                let selected = tab == selection
                Button { selection = tab } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .symbolEffect(.bounce, value: selected)
                        Text(tab.title(t)).font(.system(size: 9.5, weight: .semibold)).lineLimit(1)
                    }
                    .foregroundStyle(selected ? Color.white : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background {
                        if selected {
                            Capsule()
                                .fill(LinearGradient(colors: [Palette.indigo, Palette.azure].map(\.color),
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .shadow(color: Palette.azure.color.opacity(0.45), radius: 8, y: 3)
                                .matchedGeometryEffect(id: "tab", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title(t))
            }
        }
        .padding(4)
        .glass(in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}

/// Every tab scrolls inside this: hidden indicators, soft fades at the edges,
/// and room at the bottom so content glides under the floating tab bar.
struct TabScroll<Content: View>: View {
    var topInset: CGFloat = 6
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 12) { content }
                .padding(.horizontal, 16)
                .padding(.top, topInset)
                .padding(.bottom, 86)
        }
        .scrollIndicators(.never)
        .mask(LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.025),
            .init(color: .black, location: 0.84),
            .init(color: .black.opacity(0.15), location: 1),
        ], startPoint: .top, endPoint: .bottom))
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.orange.color)
            Text(message).font(.system(size: 10.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.orange.color.opacity(0.14)))
    }
}

/// Simple gradient capsule — used where the animated Optimize button would compete.
struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Capsule().fill(LinearGradient(colors: [Palette.indigo, Palette.azure].map(\.color),
                                                          startPoint: .leading, endPoint: .trailing)))
                .shadow(color: Palette.azure.color.opacity(0.45), radius: 12, y: 5)
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let t = model.t
        ZStack {
            Rectangle().fill(.regularMaterial)
            AmbientBackground(level: 0)
            VStack(spacing: 20) {
                Spacer(minLength: 8)
                LumoGlyph(size: 76).appear(order: 0)
                VStack(spacing: 6) {
                    Text(t("Добро пожаловать в Lumo", "Welcome to Lumo"))
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                    Text(t("Ваш Mac — быстрый, прохладный и под контролем.", "Keep your Mac fast, cool and under control."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .appear(order: 1)
                VStack(alignment: .leading, spacing: 16) {
                    feature("waveform.path.ecg", [Palette.cyan, Palette.blue],
                            t("Живой монитор", "Live monitor"),
                            t("CPU, память, сеть и батарея в реальном времени", "CPU, memory, network and battery in real time"))
                        .appear(order: 2)
                    feature("sparkles", [Palette.purple, Palette.pink],
                            t("Оптимизация в один клик", "One-click optimize"),
                            t("Находит тяжёлые процессы и бережно их останавливает", "Finds heavy processes and gently stops them"))
                        .appear(order: 3)
                    feature("lock.shield.fill", [Palette.green, Palette.mint],
                            t("Безопасно по умолчанию", "Safe by default"),
                            t("Системные процессы и активное окно не трогаются", "System processes and your active app stay untouched"))
                        .appear(order: 4)
                }
                .padding(.horizontal, 8)
                PillPicker(options: AppLanguage.allCases, selection: $model.language) { $0.title }
                    .frame(width: 210)
                    .appear(order: 5)
                Spacer(minLength: 4)
                PrimaryButton(title: t("Начать", "Get started")) { model.onboardingDone = true }
                    .appear(order: 6)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
        }
    }

    private func feature(_ symbol: String, _ colors: [PaletteColor], _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 14) {
            IconBadge(symbol: symbol, colors: colors.map(\.color), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
