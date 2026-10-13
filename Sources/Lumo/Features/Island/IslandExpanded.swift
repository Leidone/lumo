import AppKit
import LumoCore
import SwiftUI

/// The open island: now playing with a scrubber, timers, live stats and quick controls.
struct IslandExpanded: View {
    @ObservedObject var island: DynamicIsland
    @ObservedObject var nowPlaying: NowPlayingService

    private var t: Localizer { island.model?.t ?? Localizer(language: .english) }

    var body: some View {
        VStack(spacing: 10) {
            band
            Group {
                switch island.tab {
                case .home: home
                case .calendar: IslandCalendarTab(calendar: island.calendar, t: t)
                case .files: island.model.map { IslandFilesTab(shelf: $0.shelf, t: t) }
                case .notes: island.model.map { IslandNotesTab(notes: $0.notes, t: t) }
                case .agents: island.model.map { IslandAgentsTab(agents: $0.agents, t: t) }
                case .notifications: IslandNotificationsTab(feed: island.notifications, t: t)
                case .camera: IslandCameraTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity.combined(with: .offset(y: 6)))
            .id(island.tab)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: island.tab)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .background(alignment: .topLeading) {
            // Soft glow tinted by the album art.
            if nowPlaying.track != nil, island.tab == .home {
                Circle().fill(nowPlaying.accent.opacity(0.35)).frame(width: 220, height: 220).blur(radius: 60).offset(x: -40, y: -20)
                    .allowsHitTesting(false)
            }
        }
    }

    private var home: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                media.frame(maxWidth: .infinity, alignment: .leading)
                timer.frame(width: 120)
            }
            footer
        }
    }

    // Top band beside the notch: section tabs on the left, battery on the right.
    private var band: some View {
        HStack(spacing: 4) {
            ForEach(IslandTab.allCases.filter(island.enabledTabs.contains)) { tab in
                Button { island.tab = tab } label: {
                    Image(systemName: tab.symbol).font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                        .background(Capsule().fill(Color.white.opacity(island.tab == tab ? 0.18 : 0)))
                        .foregroundStyle(island.tab == tab ? .white : .white.opacity(0.55))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title(t))
            }
            Spacer(minLength: island.notchSize.width)
            if let battery = island.model?.snapshot.battery {
                Label(Format.percent(battery.charge), systemImage: battery.isCharging ? "battery.100.bolt" : "battery.75percent")
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                    .labelStyle(.titleAndIcon)
            }
        }
        .frame(height: island.notchSize.height)
        .padding(.horizontal, 4)
    }

    // MARK: Media

    @ViewBuilder private var media: some View {
        if let track = nowPlaying.track {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ArtworkView(image: nowPlaying.artwork, bundleID: track.bundleID, size: 54, radius: 12)
                        .shadow(color: nowPlaying.accent.opacity(0.6), radius: 10)
                        .onTapGesture { activate(track.bundleID) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.state.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                        Text(track.state.artist.isEmpty ? track.state.album : track.state.artist)
                            .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if track.state.isPlaying {
                        EqualizerBars(color: nowPlaying.accent, levels: island.levelSource).frame(width: 16, height: 14)
                    }
                }
                if track.state.duration > 0 { Scrubber(track: track, tint: nowPlaying.accent) { nowPlaying.seek(to: $0) } }
                if island.lyricsEnabled, !island.lyrics.lines.isEmpty {
                    LyricLineView(lyrics: island.lyrics, track: track, tint: nowPlaying.accent)
                }
                HStack(spacing: 26) {
                    control("backward.fill", .previous)
                    control(track.state.isPlaying ? "pause.fill" : "play.fill", .toggle, size: 20)
                    control("forward.fill", .next)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.white.opacity(0.4))
                Text(t("Ничего не играет", "Nothing playing")).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                Text(t("Музыка, подкасты и видео из любого приложения появятся здесь",
                       "Music, podcasts and video from any app show up here"))
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
    }

    private func control(_ symbol: String, _ command: NowPlayingService.Command, size: CGFloat = 15) -> some View {
        Button { nowPlaying.send(command) } label: {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }

    private func activate(_ bundleID: String?) {
        guard let bundleID, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        app.activate()
    }

    // MARK: Timer

    private var timer: some View {
        VStack(spacing: 8) {
            if let end = island.timerEnd {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(end.timeIntervalSince(context.date), 0)
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 5)
                        Circle().trim(from: 0, to: island.timerTotal > 0 ? remaining / island.timerTotal : 0)
                            .stroke(LinearGradient(colors: [Palette.orange.color, Palette.pink.color], startPoint: .top, endPoint: .bottom),
                                    style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: remaining)
                        Text(end, style: .timer).font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                    }
                }
                .frame(width: 64, height: 64)
                Button(t("Отменить", "Cancel")) { island.cancelTimer() }
                    .buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            } else {
                Label(t("Таймер", "Timer"), systemImage: "timer").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                LazyVGrid(columns: [GridItem(.fixed(30)), GridItem(.fixed(30)), GridItem(.fixed(30))], spacing: 6) {
                    ForEach([1, 5, 10, 15, 25, 50], id: \.self) { minutes in
                        Button("\(minutes)") { island.startTimer(minutes: minutes) }
                            .buttonStyle(PressScaleStyle())
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                }
            }
        }
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        if let model = island.model {
            HStack(spacing: 8) {
                stat("cpu", Format.percent(model.snapshot.cpuLoad), Palette.purple.color)
                stat("memorychip", Format.percent(model.snapshot.memory.fraction), Palette.mint.color)
                if let temperature = model.sensors.socTemperature {
                    stat("thermometer.medium", "\(Int(temperature.rounded()))°", Palette.orange.color)
                }
                Spacer(minLength: 0)
                quick(model.darkMode ? "sun.max.fill" : "moon.fill", active: model.darkMode) { model.toggleDarkMode() }
                quick("cup.and.saucer.fill", active: model.keepAwake.isOn) {
                    model.keepAwake.isOn ? model.stopKeepAwake() : model.startKeepAwake(minutes: 60)
                }
                quick("camera.viewfinder", active: false) {
                    island.setExpanded(false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { model.capture.screenshot(.area) }
                }
                quick("lock.fill", active: false) { model.lockScreen() }
            }
        }
    }

    private func stat(_ symbol: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(tint)
            Text(value).font(.system(size: 10.5, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private func quick(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(active ? Palette.orange.color.opacity(0.85) : Color.white.opacity(0.12)))
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// The line being sung right now, updated twice a second while visible.
private struct LyricLineView: View {
    @ObservedObject var lyrics: LyricsService
    let track: NowPlayingService.Track
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let line = lyrics.line(at: track.state.elapsed(at: context.date)) ?? "♪"
            Text(line)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: line)
        }
    }
}

/// Track progress that ticks once a second only while visible; drag to seek.
private struct Scrubber: View {
    let track: NowPlayingService.Track
    let tint: Color
    let seek: (Double) -> Void
    @State private var dragProgress: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = dragProgress ?? track.state.progress(at: context.date)
            VStack(spacing: 3) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(tint).frame(width: max(geometry.size.width * progress, 4))
                    }
                    .frame(height: dragProgress == nil ? 4 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { dragProgress = min(max($0.location.x / geometry.size.width, 0), 1) }
                        .onEnded { _ in
                            if let dragProgress { seek(dragProgress * track.state.duration) }
                            dragProgress = nil
                        })
                    .animation(.spring(response: 0.25), value: dragProgress == nil)
                }
                .frame(height: 10)
                HStack {
                    Text(Self.time(progress * track.state.duration))
                    Spacer()
                    Text("-" + Self.time(track.state.duration * (1 - progress)))
                }
                .font(.system(size: 9.5, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private static func time(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0).rounded())
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
                             : String(format: "%d:%02d", total / 60, total % 60)
    }
}
