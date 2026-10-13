import LumoCore
import SwiftUI

struct ProcessesTab: View {
    enum Mode: String, CaseIterable, Identifiable {
        case processes, ports

        var id: Self { self }
    }

    private static let visibleLimit = 60

    @EnvironmentObject private var model: AppModel
    @State private var mode: Mode = .processes
    @State private var query = ""

    var body: some View {
        let t = model.t
        VStack(spacing: 10) {
            VStack(spacing: 8) {
                PillPicker(options: Mode.allCases, selection: $mode) { mode in
                    mode == .processes
                        ? t("Процессы", "Processes") + "  \(model.groups.count)"
                        : t("Порты", "Ports") + "  \(model.ports.count)"
                }
                SearchField(text: $query, prompt: t("Поиск", "Search"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)

            TabScroll(topInset: 2) {
                switch mode {
                case .processes: processList(t)
                case .ports: portList(t)
                }
            }
            .id(mode)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.25), value: mode)
        .onAppear { model.refreshPorts() }
    }

    @ViewBuilder
    private func processList(_ t: Localizer) -> some View {
        let targets = Set(model.plan.map(\.id))
        let rows = Array(model.groups.filter { matches($0.displayName) }.prefix(Self.visibleLimit))
        if rows.isEmpty {
            EmptyState(symbol: model.groups.isEmpty ? "hourglass" : "magnifyingglass",
                       title: model.groups.isEmpty ? t("Загружаю…", "Loading…") : t("Ничего не найдено", "No matches"))
        } else {
            ForEach(rows) { group in
                ProcessRow(group: group, isTarget: targets.contains(group.id)).scrollFade()
            }
        }
    }

    @ViewBuilder
    private func portList(_ t: Localizer) -> some View {
        let rows = model.ports.filter { matches($0.command) || matches(String($0.port)) }
        if rows.isEmpty {
            EmptyState(symbol: "network.slash",
                       title: model.ports.isEmpty ? t("Открытых портов нет", "No open ports") : t("Ничего не найдено", "No matches"),
                       subtitle: t("Здесь появятся серверы, которые слушают сеть: например, dev-сервер на :3000",
                                   "Servers listening on the network show up here — like a dev server on :3000"))
        } else {
            ForEach(rows) { port in
                PortRow(port: port).scrollFade()
            }
        }
    }

    private func matches(_ text: String) -> Bool {
        query.isEmpty || text.localizedCaseInsensitiveContains(query)
    }
}

private struct SearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.primary.opacity(focused ? 0.09 : 0.06)))
        .overlay(Capsule().strokeBorder(Palette.blue.color.opacity(focused ? 0.6 : 0), lineWidth: 1.2))
        .animation(.easeInOut(duration: 0.2), value: focused)
        .animation(.spring(response: 0.3), value: text.isEmpty)
    }
}

private struct EmptyState: View {
    let symbol: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Palette.brand)
                .symbolEffect(.pulse)
            Text(title).font(.system(size: 13, weight: .semibold))
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }
}

/// Shared row chrome: rounded, lifts slightly on hover.
private struct RowBackground: ViewModifier {
    let highlighted: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(highlighted ? Palette.pink.color.opacity(0.09) : Color.primary.opacity(hovering ? 0.07 : 0.035)))
            .scaleEffect(hovering ? 1.01 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovering)
            .onHover { hovering = $0 }
    }
}

private struct ProcessRow: View {
    let group: UsageGroup
    let isTarget: Bool

    @EnvironmentObject private var model: AppModel

    var body: some View {
        let t = model.t
        HStack(spacing: 10) {
            Image(nsImage: IconCache.icon(for: group.iconPath))
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.displayName).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(subtitle(t)).font(.system(size: 10)).foregroundStyle(isTarget ? Palette.pink.color : .secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f%%", group.cpuPercent)).font(.system(size: 11.5, weight: .semibold, design: .rounded))
                Text(Format.bytes(group.residentBytes)).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .monospacedDigit()
            Button {
                model.toggleException(group.exceptionKey)
            } label: {
                Image(systemName: group.isException ? "lock.shield.fill" : "shield")
                    .foregroundStyle(group.isException ? Palette.green.color : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(group.isException ? t("Убрать из исключений", "Remove from exceptions") : t("Никогда не трогать", "Never touch"))
            Button {
                model.stopNow(group)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .help(group.isApp ? t("Закрыть приложение", "Quit app") : t("Завершить процесс", "End process"))
            .disabled(group.isFrontmost || model.isOptimizing)
        }
        .buttonStyle(.borderless)
        .modifier(RowBackground(highlighted: isTarget))
    }

    private func subtitle(_ t: Localizer) -> String {
        if group.isFrontmost { return t("Активное окно — не трогаем", "Active window — left alone") }
        if group.isException { return t("В исключениях", "In exceptions") }
        if isTarget { return group.isApp ? t("Будет закрыто", "Will be quit") : t("Будет завершён", "Will be ended") }
        return group.isApp
            ? t("Приложение · процессов: \(group.pids.count)", "App · \(group.pids.count) processes")
            : t("Фоновый процесс", "Background process")
    }
}

private struct PortRow: View {
    let port: ListeningPort

    @EnvironmentObject private var model: AppModel

    var body: some View {
        let t = model.t
        let stoppable = model.canStop(port)
        HStack(spacing: 10) {
            if let path = model.executablePath(for: port.pid) {
                Image(nsImage: IconCache.icon(for: path)).resizable().frame(width: 26, height: 26)
            } else {
                IconBadge(symbol: "network", colors: [Palette.cyan.color, Palette.blue.color], size: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(port.command).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(port.isLocalOnly ? t("Только этот Mac", "This Mac only") : t("Доступен в сети", "Reachable on network"))
                    .font(.system(size: 10))
                    .foregroundStyle(port.isLocalOnly ? Color.secondary : Palette.orange.color)
            }
            Spacer(minLength: 4)
            Text(":\(port.port)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(LinearGradient(colors: [Palette.blue.color, Palette.purple.color],
                                                          startPoint: .leading, endPoint: .trailing)))
            Button {
                model.stop(port)
            } label: {
                Image(systemName: "stop.circle.fill").foregroundStyle(stoppable ? Palette.pink.color : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.borderless)
            .disabled(!stoppable)
            .help(stoppable ? t("Остановить процесс на этом порту", "Stop the process on this port")
                            : t("Системный процесс — Lumo его не трогает", "System process — Lumo leaves it alone"))
        }
        .modifier(RowBackground(highlighted: false))
    }
}
