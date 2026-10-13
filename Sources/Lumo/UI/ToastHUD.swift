import AppKit
import SwiftUI

/// A short confirmation for shortcut-driven actions ("Output: AirPods", "Microphones muted").
/// Uses the Dynamic Island when it is on, otherwise a small glass capsule near the bottom of the screen.
@MainActor
enum Toast {
    weak static var island: DynamicIsland?
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?
    private static let duration = 1.8

    static func show(_ symbol: String, _ title: String, subtitle: String = "", tint: Color = Palette.blue.color) {
        if let island, island.isEnabled {
            island.showPeek(DynamicIsland.Peek(symbol: symbol, title: title, subtitle: subtitle, tint: tint))
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: ToastView(symbol: symbol, title: title, subtitle: subtitle, tint: tint))
        let size = host.fittingSize
        panel.contentView = host
        if let screen = NSScreen.main {
            panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.minY + 90,
                                  width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 },
                                                 completionHandler: { panel.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        return panel
    }
}

private struct ToastView: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if !subtitle.isEmpty { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .navyGlass(in: Capsule())
        .padding(20)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .fixedSize()
    }
}
