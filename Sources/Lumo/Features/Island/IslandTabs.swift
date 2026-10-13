import AppKit
import LumoCore
import SwiftUI
import UniformTypeIdentifiers

/// Sections of the open island. Users pick which ones appear.
enum IslandTab: String, CaseIterable, Identifiable {
    case home, calendar, files, notes, agents, notifications, camera

    var id: Self { self }

    var symbol: String {
        switch self {
        case .home: return "music.note.house.fill"
        case .calendar: return "calendar"
        case .files: return "tray.full.fill"
        case .notes: return "note.text"
        case .agents: return "sparkles"
        case .notifications: return "bell.badge.fill"
        case .camera: return "camera.fill"
        }
    }

    func title(_ t: Localizer) -> String {
        switch self {
        case .home: return t("Музыка и таймер", "Music & timer")
        case .calendar: return t("Календарь", "Calendar")
        case .files: return t("Файлы (полка)", "Files (shelf)")
        case .notes: return t("Заметки", "Notes")
        case .agents: return t("AI-агенты", "AI agents")
        case .notifications: return t("Уведомления", "Notifications")
        case .camera: return t("Камера-зеркало", "Camera mirror")
        }
    }
}

private struct IslandEmpty: View {
    let symbol: String
    let text: String
    var action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(.white.opacity(0.35))
            Text(text).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1).buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Calendar

struct IslandCalendarTab: View {
    @ObservedObject var calendar: CalendarFeed
    let t: Localizer

    var body: some View {
        if !calendar.isAuthorized {
            IslandEmpty(symbol: "calendar.badge.lock", text: t("Lumo покажет ближайшие встречи", "Lumo shows your next meetings"),
                        action: (t("Разрешить доступ", "Allow access"), calendar.requestAccess))
        } else if calendar.events.isEmpty {
            IslandEmpty(symbol: "calendar", text: t("В ближайшие сутки событий нет", "Nothing in the next day"))
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(calendar.events) { event in row(event) }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private func row(_ event: CalendarFeed.Event) -> some View {
        HStack(spacing: 10) {
            Capsule().fill(event.color).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(when(event)).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            if let url = event.meetingURL {
                Button(t("Войти", "Join")) { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderedProminent).tint(Palette.green.color).controlSize(.small)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func when(_ event: CalendarFeed.Event) -> String {
        if event.isAllDay { return t("Весь день", "All day") }
        let now = Date()
        if event.start <= now { return t("Идёт · до ", "Now · until ") + event.end.formatted(date: .omitted, time: .shortened) }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        let range = "\(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))"
        return minutes < 60 ? t("Через \(max(minutes, 1)) мин · ", "In \(max(minutes, 1)) min · ") + range
                            : (Calendar.current.isDateInToday(event.start) ? range : t("Завтра ", "Tomorrow ") + range)
    }
}

// MARK: - Files

struct IslandFilesTab: View {
    @ObservedObject var shelf: ShelfStore
    let t: Localizer
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 10) {
            dropZone
            if !shelf.items.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(shelf.items) { item in tile(item) }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: targeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 22, weight: .semibold))
                .symbolEffect(.bounce, value: targeted)
            Text(t("Перетащите сюда", "Drop here")).font(.system(size: 10.5, weight: .medium))
            if !shelf.items.isEmpty {
                HStack(spacing: 10) {
                    Button { shelf.airDrop(shelf.items) } label: { Image(systemName: "airplayaudio") }
                        .help("AirDrop")
                    Button { shelf.clear() } label: { Image(systemName: "trash") }
                        .help(t("Очистить полку", "Clear the shelf"))
                }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(targeted ? Palette.cyan.color : .white.opacity(0.6))
        .frame(width: shelf.items.isEmpty ? nil : 112)
        .frame(maxWidth: shelf.items.isEmpty ? .infinity : nil, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .foregroundStyle(targeted ? Palette.cyan.color : .white.opacity(0.2)))
        .onDrop(of: ShelfStore.dropTypes, isTargeted: $targeted.animation(.spring(response: 0.3))) { shelf.accept($0) }
    }

    private func tile(_ item: ShelfStore.Item) -> some View {
        VStack(spacing: 5) {
            Group {
                switch item.kind {
                case .file: Image(nsImage: IconCache.icon(for: item.value)).resizable().aspectRatio(contentMode: .fit)
                case .link: Image(systemName: "link").font(.system(size: 22)).foregroundStyle(Palette.blue.color)
                case .text: Image(systemName: "text.alignleft").font(.system(size: 22)).foregroundStyle(Palette.yellow.color)
                }
            }
            .frame(width: 42, height: 42)
            Text(item.title).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center).frame(width: 72)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        .onDrag { item.provider }
        .onTapGesture(count: 2) { shelf.open(item) }
        .contextMenu {
            Button(t("Открыть", "Open")) { shelf.open(item) }
            Button(t("Скопировать", "Copy")) { shelf.copy(item) }
            Button("AirDrop") { shelf.airDrop([item]) }
            Divider()
            Button(t("Убрать с полки", "Remove from shelf"), role: .destructive) { shelf.remove(item) }
        }
    }
}

// MARK: - Notes

struct IslandNotesTab: View {
    @ObservedObject var notes: NotesStore
    let t: Localizer

    var body: some View {
        if let note = notes.selected ?? notes.notes.first {
            TextEditor(text: Binding(get: { note.body }, set: { notes.update(note.id, body: $0) }))
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        } else {
            IslandEmpty(symbol: "note.text", text: t("Здесь будет черновик под рукой", "A scratchpad, always at hand"),
                        action: (t("Новая заметка", "New note"), { notes.add() }))
        }
    }
}

// MARK: - AI agents

struct IslandAgentsTab: View {
    @ObservedObject var agents: AgentUsageStore
    let t: Localizer

    var body: some View {
        HStack(spacing: 10) {
            card("Claude Code", agents.claude, [Palette.orange.color, Palette.pink.color])
            card("Codex", agents.codex, [Palette.green.color, Palette.cyan.color])
        }
        .onAppear { agents.refresh() }
    }

    private func card(_ name: String, _ summary: AgentUsageStore.Summary, _ colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                Text(name).font(.system(size: 12, weight: .bold, design: .rounded))
                if summary.isWorking { Circle().fill(Palette.green.color).frame(width: 6, height: 6) }
            }
            if let window = summary.limits?.windows.first {
                Text("\(Int(window.usedPercent.rounded()))%").font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                CapsuleMeter(value: window.usedPercent / 100, colors: colors)
                Text(t("Лимит ", "Limit ") + window.name + (window.resetsAt.map { " · " + $0.formatted(.relative(presentation: .named)) } ?? ""))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            } else if let block = summary.block {
                let remaining = max(block.end.timeIntervalSinceNow, 0)
                Text(Self.compact(block.tokens)).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                CapsuleMeter(value: 1 - remaining / UsageBlocks.length, colors: colors)
                Text(t("Сброс через ", "Resets in ") + Format.duration(minutes: Int(remaining / 60), t))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
            } else {
                Text(summary.isInstalled ? t("Нет активного окна", "No active window") : t("Не установлен", "Not installed"))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.1fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }
}

// MARK: - Notifications

struct IslandNotificationsTab: View {
    @ObservedObject var feed: NotificationFeed
    let t: Localizer

    var body: some View {
        if !feed.hasAccess {
            IslandEmpty(symbol: "lock.shield", text: t("Нужен «Полный доступ к диску», чтобы читать уведомления. Lumo только читает их локально.",
                                                        "Needs Full Disk Access to read notifications. Lumo only reads them locally."),
                        action: (t("Открыть настройки", "Open Settings"), NotificationFeed.openFullDiskAccessSettings))
        } else if feed.notices.isEmpty {
            IslandEmpty(symbol: "bell.slash", text: t("Уведомлений нет", "No notifications"))
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(feed.notices) { notice in
                        HStack(alignment: .top, spacing: 10) {
                            let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: notice.bundleID)?.path
                            Image(nsImage: path.map { IconCache.icon(for: $0) } ?? NSImage()).resizable().frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(notice.payload.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text([notice.payload.subtitle, notice.payload.body].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Text(notice.date, style: .relative).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                        .onTapGesture {
                            NSRunningApplication.runningApplications(withBundleIdentifier: notice.bundleID).first?.activate()
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

// MARK: - Camera

struct IslandCameraTab: View {
    var body: some View {
        CameraPreview()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            .frame(maxWidth: 260, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
    }
}
