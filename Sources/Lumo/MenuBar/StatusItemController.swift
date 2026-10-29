import AppKit
import Combine
import SwiftUI

/// Owns the menu bar item: animated icon, optional % text, popover and right-click menu.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private static let figureSpace = "\u{2007}"

    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let iconView = StatusIconView(frame: .zero)
    private var subscriptions = Set<AnyCancellable>()
    private var seenRuns = 0
    private weak var anchor: NSStatusBarButton?
    private lazy var readoutController = ReadoutController { [weak self] button in self?.togglePopover(button) }

    init(model: AppModel) {
        self.model = model
        super.init()
        configurePopover()
        configureButton()
        observe()
        modelChanged()
        showOnFirstLaunch()
    }

    // MARK: Setup

    private func configurePopover() {
        let hosting = NSHostingController(rootView: PopoverView().environmentObject(model))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.animates = true
        popover.delegate = self
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Lumo")
        iconView.frame = button.bounds
        button.addSubview(iconView)
    }

    private func observe() {
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.modelChanged() }
            .store(in: &subscriptions)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    /// First launch: open the popover so the welcome tour is impossible to miss.
    private func showOnFirstLaunch() {
        guard !model.onboardingDone else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, let button = self.statusItem.button, !self.popover.isShown else { return }
            self.togglePopover(button)
        }
    }

    // MARK: Events

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuickMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        model.setPopoverVisible(true)
        NSApp.activate()
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        anchor = sender
        sender.highlight(true)
    }

    func popoverDidClose(_ notification: Notification) {
        model.setPopoverVisible(false)
        anchor?.highlight(false)
        anchor = nil
    }

    private func showQuickMenu() {
        let t = model.t
        let menu = NSMenu()
        let optimize = menu.addItem(withTitle: t("Оптимизировать сейчас", "Optimize now"),
                                    action: #selector(optimizeFromMenu), keyEquivalent: "")
        optimize.target = self
        optimize.isEnabled = !model.isOptimizing
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: t("Выйти из Lumo", "Quit Lumo"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func optimizeFromMenu() { model.optimize() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func accessibilityChanged() { modelChanged() }

    // MARK: Rendering

    private func modelChanged() {
        iconView.setAnimated(model.animateIcon && !model.isSavingPower && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        iconView.setBusy(model.isOptimizing)
        iconView.setValues(cpu: model.cpuLoad, memory: model.memory.fraction)
        iconView.setHealth(Palette.health(model.healthLoad))
        if model.completedRuns != seenRuns {
            seenRuns = model.completedRuns
            iconView.flash()
        }
        iconView.setText(menuBarText)
        statusItem.button?.toolTip = model.t("Lumo — оптимизация Mac", "Lumo — Mac optimizer")
        statusItem.length = iconView.preferredWidth
        readoutController.update(from: model)
    }

    private var menuBarText: String {
        let cpu = Self.percent(model.cpuLoad)
        let memory = Self.percent(model.memory.fraction)
        switch model.menuBarText {
        case .none: return ""
        case .cpu: return cpu
        case .memory: return memory
        case .both: return "\(cpu) · \(memory)"
        case .network: return "↓" + Format.compactRate(model.snapshot.network.downRate)
        }
    }

    /// Fixed-width "  7%" / " 42%" so the menu bar item does not jitter.
    private static func percent(_ value: Double) -> String {
        let number = String(Int((value * 100).rounded()))
        return String(repeating: figureSpace, count: max(0, 3 - number.count)) + number + "%"
    }
}
