import AppKit
import Carbon
import Combine
import LumoCore
import SwiftUI

/// A Dynamic Island around the notch (or a simulated one on Macs without it).
///
/// The panel never moves or resizes: only the black shape inside it animates, so expansion is a
/// single smooth spring. While nothing happens the shape is exactly the notch — invisible, and
/// the panel ignores the mouse so the menu bar beside the notch stays clickable.
@MainActor
final class DynamicIsland: NSObject, ObservableObject {
    enum Mode: Equatable {
        case idle, compact, peek, expanded
    }

    struct Peek: Equatable {
        let symbol: String
        let title: String
        let subtitle: String
        let tint: Color
    }

    private enum Key {
        static let enabled = "island.enabled"
        static let hoverDelay = "island.hoverDelay"
        static let showActivities = "island.showActivities"
        static let haptics = "island.haptics"
        static let hotKey = "island.hotKey"
        static let tabs = "island.tabs"
        static let liveEqualizer = "island.liveEqualizer"
        static let lyrics = "island.lyrics"
        static let downloads = "island.downloads"
        static let eventAlerts = "island.eventAlerts"
        static let notificationPeeks = "island.notificationPeeks"
    }

    static let panelSize = CGSize(width: 640, height: 300)
    static let expandedWidth: CGFloat = 520
    static let expandedContentHeight: CGFloat = 184
    static let wingWidth: CGFloat = 38
    private static let collapseDelay = 0.3
    private static let peekDuration = 3.2

    @Published var isEnabled: Bool { didSet { store.set(isEnabled, forKey: Key.enabled); configure() } }
    @Published var hoverDelay: Double { didSet { store.set(hoverDelay, forKey: Key.hoverDelay) } }
    @Published var showActivities: Bool { didSet { store.set(showActivities, forKey: Key.showActivities) } }
    @Published var haptics: Bool { didSet { store.set(haptics, forKey: Key.haptics) } }
    @Published var hotKeyEnabled: Bool { didSet { store.set(hotKeyEnabled, forKey: Key.hotKey); registerHotKey() } }
    @Published var enabledTabs: Set<IslandTab> {
        didSet {
            store.set(enabledTabs.map(\.rawValue), forKey: Key.tabs)
            if !enabledTabs.contains(tab) { tab = .home }
            configureServices()
        }
    }
    @Published var liveEqualizer: Bool { didSet { store.set(liveEqualizer, forKey: Key.liveEqualizer); updateMeter() } }
    @Published var lyricsEnabled: Bool { didSet { store.set(lyricsEnabled, forKey: Key.lyrics); lyrics.load(for: lyricsEnabled ? nowPlaying.track : nil) } }
    @Published var downloadsEnabled: Bool { didSet { store.set(downloadsEnabled, forKey: Key.downloads); configureServices() } }
    @Published var eventAlerts: Bool { didSet { store.set(eventAlerts, forKey: Key.eventAlerts) } }
    @Published var notificationPeeks: Bool { didSet { store.set(notificationPeeks, forKey: Key.notificationPeeks) } }
    @Published var tab: IslandTab = .home

    @Published private(set) var isExpanded = false
    @Published private(set) var peek: Peek?
    @Published private(set) var timerEnd: Date?
    @Published private(set) var timerTotal: TimeInterval = 0
    @Published private(set) var notchSize = CGSize(width: 190, height: 32)
    @Published private(set) var hasNotch = false

    let nowPlaying = NowPlayingService()
    let calendar = CalendarFeed()
    let downloads = DownloadWatcher()
    let lyrics = LyricsService()
    let notifications = NotificationFeed()
    /// AudioLevelMeter on macOS 14.2+, kept untyped so the class stays available on 14.0.
    private var meter: AnyObject?
    private var meterActivity: AnyCancellable?
    private var wakeObservers: [NSObjectProtocol] = []
    /// False while the displays sleep or another user is active: nothing on screen to animate.
    private var screensAwake = true
    private var cancellables: Set<AnyCancellable> = []
    private var serviceTimer: Timer?
    private var announcedEvents: Set<String> = []
    weak var model: AppModel?

    private let store: UserDefaults
    private let hotKeys = HotKeyCenter()
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var hoverWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var peekWork: DispatchWorkItem?
    private var countdown: Timer?
    private var screenObserver: NSObjectProtocol?

    init(store: UserDefaults) {
        store.register(defaults: [Key.hoverDelay: 0.12, Key.showActivities: true, Key.haptics: true])
        self.store = store
        isEnabled = store.bool(forKey: Key.enabled)
        hoverDelay = store.double(forKey: Key.hoverDelay)
        showActivities = store.bool(forKey: Key.showActivities)
        haptics = store.bool(forKey: Key.haptics)
        hotKeyEnabled = store.bool(forKey: Key.hotKey)
        let savedTabs = Set((store.stringArray(forKey: Key.tabs) ?? []).compactMap(IslandTab.init(rawValue:)))
        enabledTabs = savedTabs.isEmpty ? [.home, .calendar, .files, .notes, .agents] : savedTabs.union([.home])
        liveEqualizer = store.bool(forKey: Key.liveEqualizer)
        lyricsEnabled = store.bool(forKey: Key.lyrics)
        downloadsEnabled = store.object(forKey: Key.downloads) as? Bool ?? true
        eventAlerts = store.object(forKey: Key.eventAlerts) as? Bool ?? true
        notificationPeeks = store.bool(forKey: Key.notificationPeeks)
        super.init()
        nowPlaying.onNewTrack = { [weak self] track in
            self?.showPeek(Peek(symbol: "music.note", title: track.state.title, subtitle: track.state.artist, tint: Palette.pink.color))
        }
        nowPlaying.$track
            .removeDuplicates { $0?.id == $1?.id && $0?.state.isPlaying == $1?.state.isPlaying }
            .sink { [weak self] track in
                guard let self else { return }
                if self.lyricsEnabled { self.lyrics.load(for: track) }
                DispatchQueue.main.async { self.updateMeter() }
            }
            .store(in: &cancellables)
        downloads.onFinished = { [weak self] url in
            guard let self else { return }
            let t = self.model?.t ?? Localizer(language: .english)
            self.model?.shelf.add(.file, url.path)
            self.showPeek(Peek(symbol: "arrow.down.circle.fill", title: t("Загрузка завершена", "Download finished"),
                               subtitle: url.lastPathComponent, tint: Palette.blue.color))
        }
        // The compact island reacts to downloads starting and finishing.
        downloads.objectWillChange.merge(with: lyrics.objectWillChange)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        notifications.onNew = { [weak self] notice in
            guard let self, self.notificationPeeks else { return }
            self.showPeek(Peek(symbol: "bell.badge.fill", title: notice.payload.title,
                               subtitle: notice.payload.body, tint: Palette.yellow.color))
        }
    }

    func start() {
        configure()
        registerHotKey()
    }

    // MARK: State

    var mode: Mode {
        if isExpanded { return .expanded }
        if peek != nil { return .peek }
        return showActivities && hasActivity ? .compact : .idle
    }

    var hasActivity: Bool {
        timerEnd != nil || nowPlaying.track?.state.isPlaying == true || !downloads.active.isEmpty
            || model?.recorder.isRecording == true || model?.keepAwake.isOn == true
    }

    /// Size of the black shape (including the concave "ears" at the top).
    func shapeSize(for mode: Mode) -> CGSize {
        let ears = NotchShape.earRadius * 2
        let notch = notchSize
        switch mode {
        case .idle: return CGSize(width: notch.width + ears, height: notch.height)
        case .compact: return CGSize(width: notch.width + ears + Self.wingWidth * 2, height: notch.height)
        case .peek: return CGSize(width: max(notch.width + 200, 380), height: notch.height + 44)
        case .expanded: return CGSize(width: max(Self.expandedWidth, notch.width + 240), height: notch.height + Self.expandedContentHeight)
        }
    }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        if expanded, haptics { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            isExpanded = expanded
            if expanded { peek = nil }
        }
        updateMouseHandling(at: NSEvent.mouseLocation)
    }

    func showPeek(_ next: Peek) {
        guard isEnabled, !isExpanded else { return }
        peekWork?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { peek = next }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { self?.peek = nil }
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.peekDuration, execute: work)
    }

    // MARK: Lifecycle

    private func configure() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        guard isEnabled else {
            panel?.orderOut(nil)
            nowPlaying.stop()
            configureServices()
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        placePanel()
        panel.orderFrontRegardless()
        nowPlaying.start()
        configureServices()
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            let dragging = event.type == .leftMouseDragged
            MainActor.assumeIsolated { self?.updateMouseHandling(at: NSEvent.mouseLocation, dragging: dragging) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updateMouseHandling(at: NSEvent.mouseLocation) }
            return event
        }) { monitors.append(local) }
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.placePanel() } }
        }
    }

    /// Starts only the feeds the user turned on; everything stops while the island is off.
    private func configureServices() {
        let on = isEnabled
        on && enabledTabs.contains(.calendar) ? calendar.start() : calendar.stop()
        on && downloadsEnabled ? downloads.start() : downloads.stop()
        on && enabledTabs.contains(.notifications) ? notifications.start() : notifications.stop()
        serviceTimer?.invalidate()
        serviceTimer = nil
        if on && eventAlerts && enabledTabs.contains(.calendar) {
            let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.checkUpcomingEvent() } }
            timer.tolerance = 5
            RunLoop.main.add(timer, forMode: .common)
            serviceTimer = timer
        }
        updateMeter()
    }

    private func checkUpcomingEvent() {
        guard let event = calendar.startingSoon(within: 5), !announcedEvents.contains(event.id) else { return }
        announcedEvents.insert(event.id)
        let t = model?.t ?? Localizer(language: .english)
        let minutes = max(Int(event.start.timeIntervalSinceNow / 60), 1)
        showPeek(Peek(symbol: "calendar", title: event.title, subtitle: t("Через \(minutes) мин", "In \(minutes) min"), tint: event.color))
    }

    /// The live equalizer listens to system audio only while something plays and the option is on.
    /// It also needs real output somewhere (a paused player can still claim to play) and awake screens.
    private func updateMeter() {
        let enabled = isEnabled && liveEqualizer
        watchAudioActivity(enabled)
        let wanted = enabled && screensAwake && nowPlaying.track?.state.isPlaying == true
            && AudioActivity.shared.isAnythingPlaying
        guard #available(macOS 14.2, *) else { return }
        if wanted, meter == nil {
            let fresh = AudioLevelMeter()
            guard fresh.start() else { return }
            meter = fresh
            objectWillChange.send()
        } else if !wanted, let current = meter as? AudioLevelMeter {
            current.stop()
            meter = nil
            objectWillChange.send()
        }
    }

    private func watchAudioActivity(_ on: Bool) {
        guard on != (meterActivity != nil) else { return }
        if on {
            AudioActivity.shared.retain()
            meterActivity = AudioActivity.shared.$playing.dropFirst().removeDuplicates()
                .sink { [weak self] _ in DispatchQueue.main.async { self?.updateMeter() } }
            observeScreenWake()
        } else {
            meterActivity = nil
            AudioActivity.shared.release()
        }
    }

    private func observeScreenWake() {
        guard wakeObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let changes: [(Notification.Name, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, false), (NSWorkspace.screensDidWakeNotification, true),
            (NSWorkspace.sessionDidResignActiveNotification, false), (NSWorkspace.sessionDidBecomeActiveNotification, true),
        ]
        wakeObservers = changes.map { name, awake in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.screensAwake = awake
                    self?.updateMeter()
                }
            }
        }
    }

    /// Current equalizer bands, or nil to use the built-in animation.
    var levelSource: (() -> [Float])? {
        guard #available(macOS 14.2, *), let current = meter as? AudioLevelMeter else { return nil }
        return { current.current }
    }

    func shutdown() {
        if #available(macOS 14.2, *) { (meter as? AudioLevelMeter)?.stop() }
        meter = nil
        watchAudioActivity(false)
        nowPlaying.stop()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.panelSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: IslandView(island: self))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func placePanel() {
        guard let panel, let screen else { return }
        hasNotch = screen.safeAreaInsets.top > 0
        if hasNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        } else {
            notchSize = CGSize(width: 170, height: max(screen.frame.maxY - screen.visibleFrame.maxY, 24))
        }
        let size = Self.panelSize
        panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    /// The island's current rectangle in screen coordinates.
    private func shapeRect(for mode: Mode) -> CGRect {
        guard let screen else { return .zero }
        let size = shapeSize(for: mode)
        return CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }

    private func updateMouseHandling(at point: CGPoint, dragging: Bool = false) {
        guard let panel else { return }
        // Most pointer movement happens far from the notch: skip it while nothing is pending.
        if !isExpanded, !dragging, hoverWork == nil, panel.ignoresMouseEvents, !panel.frame.contains(point) { return }
        // Dragging something onto the notch opens the shelf straight away.
        if dragging, !isExpanded, enabledTabs.contains(.files), shapeRect(for: mode).insetBy(dx: -10, dy: -6).contains(point) {
            tab = .files
            setExpanded(true)
        }
        let current = shapeRect(for: mode)
        panel.ignoresMouseEvents = !current.insetBy(dx: -2, dy: -2).contains(point)

        if isExpanded {
            hoverWork?.cancel()
            if current.insetBy(dx: -14, dy: -14).contains(point) {
                collapseWork?.cancel()
                collapseWork = nil
            } else if collapseWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    self?.collapseWork = nil
                    self?.setExpanded(false)
                }
                collapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapseDelay, execute: work)
            }
            return
        }
        // The hover zone is the notch itself plus the wings when they are showing.
        let zone = shapeRect(for: mode == .idle ? .idle : mode).insetBy(dx: -4, dy: 0)
        if zone.contains(point) {
            guard hoverWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.hoverWork = nil
                guard let self, self.shapeRect(for: self.mode).insetBy(dx: -4, dy: 0).contains(NSEvent.mouseLocation) else { return }
                self.setExpanded(true)
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(hoverDelay, 0.02), execute: work)
        } else {
            hoverWork?.cancel()
            hoverWork = nil
        }
    }

    private func registerHotKey() {
        hotKeys.unregisterAll()
        guard isEnabled, hotKeyEnabled else { return }
        hotKeys.register(.island) { [weak self] in
            guard let self else { return }
            self.setExpanded(!self.isExpanded)
        }
    }

    // MARK: Timer

    func startTimer(minutes: Int) {
        timerTotal = TimeInterval(minutes * 60)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { timerEnd = Date().addingTimeInterval(timerTotal) }
        countdown?.invalidate()
        let timer = Timer(timeInterval: timerTotal, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerFinished() }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdown = timer
    }

    func cancelTimer() {
        countdown?.invalidate()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { timerEnd = nil }
    }

    private func timerFinished() {
        withAnimation { timerEnd = nil }
        NSSound(named: "Glass")?.play()
        let t = model?.t ?? Localizer(language: .english)
        showPeek(Peek(symbol: "timer", title: t("Таймер завершён", "Timer done"),
                      subtitle: Format.duration(minutes: Int(timerTotal / 60), t), tint: Palette.orange.color))
    }
}
