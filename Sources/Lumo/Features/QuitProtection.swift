import AppKit
import LumoCore
import SwiftUI

/// Guards ⌘Q and ⌘W: hold the shortcut (or press it twice) to really quit / close.
@MainActor
final class QuitProtection {
    private static let keyQ: Int64 = 12
    private static let keyW: Int64 = 13

    var guardQuit = true
    var guardClose = false
    var mode: QuitGuard.Mode = .hold { didSet { guards = [:] } }
    var exceptions: Set<String> = []
    var t = Localizer(language: .english)

    private var guards: [Int64: QuitGuard] = [:]
    private var holdTimer: Timer?
    private let hud = HintPanel()

    var keyHandler: (mask: CGEventMask, handle: InputTap.Handler) {
        (InputTap.mask(.keyDown, .keyUp), { [weak self] type, event in self?.handle(type, event) ?? event })
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard (code == Self.keyQ && guardQuit) || (code == Self.keyW && guardClose) else { return event }
        let flags = event.flags
        guard flags.contains(.maskCommand), !flags.contains(.maskControl), !flags.contains(.maskAlternate),
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !exceptions.contains(app.bundleIdentifier ?? "")
        else { return event }

        var guardian = guards[code] ?? QuitGuard(mode: mode)
        defer { guards[code] = guardian }

        if type == .keyUp {
            guardian.keyUp()
            holdTimer?.invalidate()
            hud.hide(after: 0.4)
            return event
        }
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat { return nil }

        switch guardian.keyDown(isRepeat: false, at: ProcessInfo.processInfo.systemUptime) {
        case .allow:
            hud.hide(after: 0)
            return event
        case .block:
            showHint(code: code, appName: app.localizedName ?? "")
            if mode == .hold { scheduleHold(code: code, duration: guardian.holdDuration) }
            return nil
        }
    }

    /// When the hold time passes with the key still down, send one clean ⌘Q/⌘W of our own.
    private func scheduleHold(code: Int64, duration: TimeInterval) {
        holdTimer?.invalidate()
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, var guardian = self.guards[code],
                      guardian.keyDown(isRepeat: true, at: ProcessInfo.processInfo.systemUptime) == .allow
                else { return }
                self.guards[code] = guardian
                self.hud.hide(after: 0)
                Self.post(code: code)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func showHint(code: Int64, appName: String) {
        let key = code == Self.keyQ ? "⌘Q" : "⌘W"
        let verb = code == Self.keyQ ? t("выйти из \(appName)", "quit \(appName)") : t("закрыть окно", "close the window")
        let text = mode == .hold
            ? t("Удерживайте \(key), чтобы \(verb)", "Hold \(key) to \(verb)")
            : t("Нажмите \(key) ещё раз, чтобы \(verb)", "Press \(key) again to \(verb)")
        hud.show(HintView(symbol: "hand.raised.fill", text: text, holdDuration: mode == .hold ? 0.6 : nil))
    }

    private static func post(code: Int64) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: isDown) else { continue }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: InputTap.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Floating hint

/// Small glass capsule near the bottom of the screen; used by several input tools.
@MainActor
final class HintPanel {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show<Content: View>(_ content: Content) {
        hideTask?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        panel.contentView = host
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrame(CGRect(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.16,
                                  width: size.width, height: size.height), display: true)
        }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
    }

    func hide(after delay: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let panel = self?.panel else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 },
                                                 completionHandler: { panel.orderOut(nil) })
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        return panel
    }
}

struct HintView: View {
    let symbol: String
    let text: String
    var holdDuration: TimeInterval?
    @State private var progress = 0.0

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if holdDuration != nil {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 3)
                    Circle().trim(from: 0, to: progress)
                        .stroke(LinearGradient(colors: [Palette.blue.color, Palette.purple.color, Palette.pink.color],
                                               startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            Text(text).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
        .fixedSize()
        .padding(8)
        .onAppear {
            guard let holdDuration else { return }
            withAnimation(.linear(duration: holdDuration)) { progress = 1 }
        }
    }
}
