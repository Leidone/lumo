import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusController: StatusItemController?
    private let notificationPresenter = NotificationPresenter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = notificationPresenter
        let model = AppModel()
        self.model = model
        statusController = StatusItemController(model: model)
        model.start()
    }

    /// ⌘Tab and other system shortcuts go back to macOS when Lumo quits.
    func applicationWillTerminate(_ notification: Notification) {
        model?.input.shutdown()
        model?.mixer.shutdown()
        model?.island.shutdown()
        model?.audio.shutdown()
        ShortcutStore.shared.restoreSystemShortcuts()
        model?.power.shutdown()
        model?.displayTools.shutdown()
    }
}
