import AppKit
import LumoCore
import SwiftUI

// MARK: - Mixer

struct MixerPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var mixer: VolumeMixer
    @State private var refreshTimer: Timer?

    var body: some View {
        let t = model.t
        TabScroll {
            LumoCard {
                SettingToggle(symbol: "slider.vertical.3", colors: FeatureID.mixer.colors,
                              title: t("Громкость по приложениям", "Per-app volume"),
                              subtitle: t("Без драйверов. Трогает только те приложения, что вы настроили.",
                                          "No driver. Only touches apps you adjust."),
                              isOn: $mixer.isEnabled)
                if !mixer.devices.isEmpty {
                    Divider().opacity(0.4)
                    SettingRow(symbol: "hifispeaker.2.fill", colors: [Palette.blue.color, Palette.cyan.color],
                               title: t("Выход звука", "Sound output")) {
                        Picker("", selection: Binding(get: { mixer.defaultOutputUID ?? "" }, set: { mixer.setDefaultOutput($0) })) {
                            ForEach(mixer.devices) { Text($0.name).tag($0.uid) }
                        }
                        .labelsHidden().frame(maxWidth: 170)
                    }
                }
            }
            .appear(order: 0).scrollFade()

            if let error = mixer.lastError {
                Text(error).font(.system(size: 10.5)).foregroundStyle(Palette.orange.color).fixedSize(horizontal: false, vertical: true)
            }

            if mixer.isEnabled {
                SectionTitle(text: t("Сейчас играют", "Playing now"), trailing: "\(mixer.channels.count)").appear(order: 1)
                if mixer.channels.isEmpty {
                    Text(t("Включите музыку или видео — приложение появится здесь", "Play music or a video — the app shows up here"))
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.top, 12)
                }
                ForEach(mixer.channels) { channel in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            let path = channel.bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path }
                            Image(nsImage: path.map { IconCache.icon(for: $0) } ?? NSImage()).resizable().frame(width: 26, height: 26)
                            Text(channel.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                            if channel.isPlaying { Image(systemName: "waveform").font(.system(size: 10)).foregroundStyle(Palette.green.color) }
                            Spacer()
                            HStack(spacing: 6) {
                                if mixer.isPinned(channel) {
                                    Button { mixer.movePinned(channel, by: -1) } label: { Image(systemName: "chevron.up") }
                                    Button { mixer.movePinned(channel, by: 1) } label: { Image(systemName: "chevron.down") }
                                }
                                Button { mixer.togglePin(channel) } label: {
                                    Image(systemName: mixer.isPinned(channel) ? "pin.fill" : "pin")
                                        .foregroundStyle(mixer.isPinned(channel) ? Palette.orange.color : .secondary)
                                }
                                .help(t("Закрепить в избранном", "Pin to favorites"))
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10.5, weight: .semibold))
                            Text(Format.percent(channel.volume)).font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(channel.volume > 1 ? Palette.orange.color : .primary)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                            GradientSlider(value: Binding(get: { channel.volume / VolumeMixer.maxVolume },
                                                          set: { mixer.setVolume(channel, ($0 * VolumeMixer.maxVolume * 20).rounded() / 20) }),
                                           colors: [Palette.green.color, Palette.yellow.color, Palette.orange.color, Palette.pink.color],
                                           label: channel.name)
                            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Picker(t("Выход", "Output"), selection: Binding(get: { channel.deviceUID ?? "" },
                                                                         set: { mixer.setDevice(channel, $0.isEmpty ? nil : $0) })) {
                            Text(t("Как в системе", "System default")).tag("")
                            ForEach(mixer.devices) { Text($0.name).tag($0.uid) }
                        }
                        .font(.system(size: 11))
                    }
                    .modifier(ListRow())
                    .scrollFade()
                }
            }
        }
        .onAppear {
            mixer.refresh()
            let timer = Timer(timeInterval: 2, repeats: true) { _ in MainActor.assumeIsolated { mixer.refresh() } }
            RunLoop.main.add(timer, forMode: .common)
            refreshTimer = timer
        }
        .onDisappear { refreshTimer?.invalidate() }
    }
}

// MARK: - Command Bar

struct CommandBarPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var bar: CommandBar

    var body: some View {
        let t = model.t
        TabScroll {
            LumoCard {
                SettingToggle(symbol: "command.square.fill", colors: FeatureID.commandBar.colors,
                              title: t("Command Bar по ⌥Space", "Command Bar on ⌥Space"),
                              subtitle: t("Одна строка для всего", "One field for everything"), isOn: $bar.isEnabled)
                Button { bar.toggle() } label: {
                    Label(t("Открыть сейчас", "Open now"), systemImage: "sparkle.magnifyingglass").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            .appear(order: 0).scrollFade()

            SectionTitle(text: t("Что умеет", "What it does")).appear(order: 1)
            LumoCard {
                ForEach([("app.fill", t("Приложения и файлы", "Apps and files"), "Safari, report.pdf"),
                         ("equal.circle.fill", t("Калькулятор", "Calculator"), "(1200 + 300) * 15%"),
                         ("ruler.fill", t("Единицы", "Units"), "10 km to mi · 5 гб в мб"),
                         ("face.smiling.fill", t("Эмодзи", "Emoji"), "rocket, heart"),
                         ("doc.on.clipboard.fill", t("Буфер и сниппеты", "Clipboard & snippets"), t("найдёт и вставит", "finds and pastes")),
                         ("macwindow", t("Окна и команды меню", "Windows and menu commands"), t("название окна, «Экспорт…»", "window title, “Export…”")),
                         ("wand.and.stars", t("Команды Lumo", "Lumo commands"), t("оптимизация, скриншот, не спать…", "optimize, screenshot, stay awake…"))],
                        id: \.1) { symbol, title, example in
                    HStack(spacing: 12) {
                        IconBadge(symbol: symbol, colors: FeatureID.commandBar.colors, size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title).font(.system(size: 12, weight: .medium))
                            Text(example).font(.system(size: 10.5, design: .rounded)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .appear(order: 2).scrollFade()

            SectionTitle(text: t("Свои скрипты", "Your scripts")).appear(order: 3)
            ScriptsCard(bar: bar).appear(order: 4)
        }
    }
}

// MARK: - Dynamic Island

struct IslandPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var island: DynamicIsland

    var body: some View {
        let t = model.t
        TabScroll {
            LumoCard {
                SettingToggle(symbol: "capsule.portrait.fill", colors: FeatureID.island.colors,
                              title: "Dynamic Island",
                              subtitle: island.hasNotch ? t("Живёт вокруг выреза камеры", "Lives around the camera notch")
                                                        : t("Имитация выреза сверху по центру", "A simulated notch at the top center"),
                              isOn: $island.isEnabled)
                Divider().opacity(0.4)
                SettingToggle(symbol: "rectangle.split.3x1.fill", colors: [Palette.pink.color, Palette.purple.color],
                              title: t("Активности у выреза", "Live activities"),
                              subtitle: t("Музыка, таймер, запись и загрузки по бокам выреза", "Music, timer, recording and downloads beside the notch"),
                              isOn: $island.showActivities)
                Divider().opacity(0.4)
                HStack(spacing: 10) {
                    Text(t("Раскрывать через", "Open after")).font(.system(size: 12.5, weight: .medium))
                    Slider(value: $island.hoverDelay, in: 0...0.6, step: 0.05)
                    Text("\(Int(island.hoverDelay * 1000)) \(t("мс", "ms"))").font(.system(size: 11, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                }
                Divider().opacity(0.4)
                SettingToggle(symbol: "keyboard.fill", colors: [Palette.indigo.color, Palette.blue.color],
                              title: t("Открывать по ⌃⌥⌘N", "Toggle with ⌃⌥⌘N"), isOn: $island.hotKeyEnabled)
                Divider().opacity(0.4)
                SettingToggle(symbol: "hand.tap.fill", colors: [Palette.mint.color, Palette.green.color],
                              title: t("Отклик трекпада", "Haptic feedback"), isOn: $island.haptics)
            }
            .appear(order: 0).scrollFade()

            SectionTitle(text: t("Разделы", "Sections")).appear(order: 1)
            LumoCard {
                ForEach(IslandTab.allCases) { tab in
                    HStack(spacing: 10) {
                        IconBadge(symbol: tab.symbol, colors: FeatureID.island.colors, size: 24)
                        Text(tab.title(t)).font(.system(size: 12.5, weight: .medium))
                        Spacer()
                        Toggle(tab.title(t), isOn: Binding(get: { island.enabledTabs.contains(tab) }, set: { on in
                            island.enabledTabs = on ? island.enabledTabs.union([tab]) : island.enabledTabs.subtracting([tab])
                        }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        .disabled(tab == .home)
                    }
                }
                Text(t("Перетащите файл на вырез — он ляжет на полку. Камера и уведомления включаются только здесь.",
                       "Drag a file onto the notch to put it on the shelf. Camera and notifications only run when enabled here."))
                    .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .appear(order: 2).scrollFade()

            SectionTitle(text: t("Музыка и события", "Music & events")).appear(order: 3)
            LumoCard {
                SettingToggle(symbol: "waveform", colors: [Palette.green.color, Palette.cyan.color],
                              title: t("Живой эквалайзер", "Live equalizer"),
                              subtitle: t("Полосы следуют за настоящим звуком. Нужен доступ к записи звука; работает, только пока играет музыка.",
                                          "Bars follow the real sound. Needs audio recording access; runs only while music plays."),
                              isOn: $island.liveEqualizer)
                Divider().opacity(0.4)
                SettingToggle(symbol: "quote.bubble.fill", colors: [Palette.purple.color, Palette.pink.color],
                              title: t("Текст песни", "Lyrics"),
                              subtitle: t("Синхронный текст с lrclib.net — Lumo отправляет туда только название и исполнителя.",
                                          "Synced lyrics from lrclib.net — Lumo only sends the title and artist."),
                              isOn: $island.lyricsEnabled)
                Divider().opacity(0.4)
                SettingToggle(symbol: "arrow.down.circle.fill", colors: [Palette.blue.color, Palette.cyan.color],
                              title: t("Загрузки", "Downloads"),
                              subtitle: t("Прогресс из папки «Загрузки», готовый файл — на полку", "Progress from Downloads; finished files land on the shelf"),
                              isOn: $island.downloadsEnabled)
                Divider().opacity(0.4)
                SettingToggle(symbol: "calendar.badge.clock", colors: [Palette.red.color, Palette.orange.color],
                              title: t("Напоминать о встречах", "Meeting heads-up"),
                              subtitle: t("За 5 минут до начала, с кнопкой «Войти»", "Five minutes before, with a Join button"),
                              isOn: $island.eventAlerts)
                Divider().opacity(0.4)
                SettingToggle(symbol: "bell.badge.fill", colors: [Palette.yellow.color, Palette.orange.color],
                              title: t("Показывать новые уведомления", "Show new notifications"),
                              subtitle: t("Нужен раздел «Уведомления» и «Полный доступ к диску»", "Needs the Notifications section and Full Disk Access"),
                              isOn: $island.notificationPeeks)
            }
            .appear(order: 4).scrollFade()
        }
    }
}

// MARK: - Notes & AI

struct NotesPage: View {
    enum Section: String, CaseIterable, Identifiable {
        case notes, agents

        var id: Self { self }
    }

    @EnvironmentObject private var model: AppModel
    @ObservedObject var notes: NotesStore
    @ObservedObject var agents: AgentUsageStore
    @State private var section: Section = .notes
    @State private var preview = false

    var body: some View {
        let t = model.t
        VStack(spacing: 8) {
            PillPicker(options: Section.allCases, selection: $section) {
                $0 == .notes ? t("Заметки", "Notes") : t("AI-агенты", "AI agents")
            }
            .padding(.horizontal, 16)
            TabScroll(topInset: 2) {
                switch section {
                case .notes: notesSection(t)
                case .agents: agentsSection(t)
                }
            }
            .id(section)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.25), value: section)
        .onAppear { agents.refresh() }
    }

    @ViewBuilder
    private func notesSection(_ t: Localizer) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(notes.notes) { note in
                    Button { notes.selectedID = note.id } label: {
                        Text(note.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(note.id == notes.selectedID ? Palette.yellow.color.opacity(0.3) : Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
                Button { notes.add() } label: { Image(systemName: "plus").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(.plain).padding(6).background(Circle().fill(Color.primary.opacity(0.06)))
            }
        }
        .scrollIndicators(.never)

        if let note = notes.selected {
            LumoCard(padding: 10) {
                if preview {
                    Text((try? AttributedString(markdown: note.body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                         ?? AttributedString(note.body))
                        .font(.system(size: 12.5))
                        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                        .textSelection(.enabled)
                } else {
                    TextEditor(text: Binding(get: { note.body }, set: { notes.update(note.id, body: $0) }))
                        .font(.system(size: 12.5))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 220)
                }
                HStack(spacing: 8) {
                    Toggle(t("Просмотр", "Preview"), isOn: $preview).toggleStyle(.button).controlSize(.small)
                    Button { model.scratchpad.toggle() } label: { Image(systemName: "macwindow.on.rectangle") }
                        .help(t("Открыть в отдельном окне ", "Open in a floating window ") + (ShortcutStore.shared.binding(.scratchpad)?.display ?? ""))
                    Spacer()
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.body, forType: .string) } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    Button { _ = notes.exportToDesktop(note) } label: { Image(systemName: "square.and.arrow.up") }
                    Button(role: .destructive) { notes.delete(note.id) } label: { Image(systemName: "trash") }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
            }
        }
    }

    @ViewBuilder
    private func agentsSection(_ t: Localizer) -> some View {
        ForEach(AgentUsageStore.Agent.allCases) { agent in
            let summary = agents.summaries[agent] ?? AgentUsageStore.Summary()
            if summary.isInstalled || agent == .claude || agent == .codex {
                agentCard(agent, summary, t)
            }
        }
        LumoCard {
            SettingToggle(symbol: "gauge.with.needle.fill", colors: [Palette.orange.color, Palette.pink.color],
                          title: t("Лимиты тарифа Claude", "Claude plan limits"),
                          subtitle: t("Lumo возьмёт вход Claude Code из Связки ключей (macOS спросит разрешение) и спросит у Anthropic только проценты лимитов",
                                      "Lumo uses Claude Code's sign-in from the Keychain (macOS asks once) and asks Anthropic only for limit percentages"),
                          isOn: $agents.claudeLimitsEnabled)
            if let error = agents.claudeLimitError, agents.claudeLimitsEnabled {
                Text(error).font(.system(size: 10.5)).foregroundStyle(Palette.orange.color)
            }
            Divider().opacity(0.4)
            SettingToggle(symbol: "bell.badge.fill", colors: [Palette.green.color, Palette.mint.color],
                          title: t("Сообщать, когда долгая задача готова", "Tell me when a long task finishes"),
                          subtitle: t("Агент работал 2+ минуты и затих — уведомление и остров", "An agent worked 2+ minutes and went quiet — a notification and the island"),
                          isOn: $agents.finishNotices)
        }
        .scrollFade()
        HStack {
            if let updated = agents.updated {
                Text(t("Обновлено в \(updated.formatted(date: .omitted, time: .shortened))", "Updated at \(updated.formatted(date: .omitted, time: .shortened))"))
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { agents.refresh() } label: { Label(t("Обновить", "Refresh"), systemImage: "arrow.clockwise") }
                .buttonStyle(.borderless).font(.system(size: 11)).disabled(agents.isLoading)
        }
        Text(t("По локальным логам: только числа токенов, модели, папки проектов и время — без текста переписки. «Стоимость по API» — оценка по базовым ценам Anthropic; тариф Claude Pro/Max считается иначе. Для Codex сумма не считается.",
               "From local logs: token counts, models, project folders and times only — never message text. “API value” is an estimate at Anthropic's base rates; Pro/Max plans bill differently. No dollar value for Codex."))
            .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
    }

    private func agentCard(_ agent: AgentUsageStore.Agent, _ summary: AgentUsageStore.Summary, _ t: Localizer) -> some View {
        let colors: [Color] = {
            switch agent {
            case .claude: return [Palette.orange.color, Palette.pink.color]
            case .codex: return [Palette.green.color, Palette.cyan.color]
            case .opencode: return [Palette.indigo.color, Palette.purple.color]
            case .copilot: return [Palette.blue.color, Palette.indigo.color]
            }
        }()
        return LumoCard {
            HStack(spacing: 10) {
                IconBadge(symbol: "sparkles", colors: colors, size: 28)
                Text(agent.title).font(.system(size: 14, weight: .bold, design: .rounded))
                if summary.isWorking {
                    Label(t("работает", "working"), systemImage: "circle.fill")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.green.color)
                        .symbolEffect(.pulse)
                }
                Spacer()
                if !summary.isInstalled {
                    Text(t("не найден", "not found")).font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else if let plan = summary.limits?.plan {
                    Text(plan.capitalized).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            if let limits = summary.limits {
                ForEach(limits.windows, id: \.name) { window in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(t("Лимит ", "Limit ") + window.name).font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(Int(window.usedPercent.rounded()))%").font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                        }
                        CapsuleMeter(value: window.usedPercent / 100, colors: window.usedPercent > 80 ? [Palette.orange.color, Palette.red.color] : colors)
                        if let reset = window.resetsAt {
                            Text(t("Сброс ", "Resets ") + reset.formatted(.relative(presentation: .named)))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                }
                if let balance = limits.creditBalance {
                    Text(t("Кредиты: ", "Credits: ") + balance).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            if let block = summary.block {
                let remaining = max(block.end.timeIntervalSinceNow, 0)
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.compact(block.tokens)).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(t("токенов в 5-часовом окне", "tokens in the 5-hour window")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(t("Окно закончится через \(Format.duration(minutes: Int(remaining / 60), t)) · запросов: \(block.requests)",
                       "Window ends in \(Format.duration(minutes: Int(remaining / 60), t)) · \(block.requests) requests"))
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                ForEach(block.byModel.sorted { $0.value > $1.value }.prefix(3), id: \.key) { model, tokens in
                    HStack {
                        Text(model).font(.system(size: 10.5, design: .monospaced)).lineLimit(1)
                        Spacer()
                        Text(Self.compact(tokens)).font(.system(size: 10.5, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
            if summary.isInstalled {
                HStack {
                    Text(t("Сегодня: \(Self.compact(summary.today)) токенов", "Today: \(Self.compact(summary.today)) tokens"))
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    if let value = summary.valueToday {
                        Text(t("≈ $\(String(format: "%.2f", value)) по API", "≈ $\(String(format: "%.2f", value)) API value"))
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Palette.green.color)
                    }
                }
                if !summary.projects.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(summary.projects, id: \.name) { project in
                            Text("\(project.name) · \(Self.compact(project.tokens))")
                                .font(.system(size: 10, weight: .medium)).lineLimit(1)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                    }
                }
            }
        }
        .scrollFade()
    }

    private static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.1fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }
}
