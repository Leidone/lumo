import AppKit
import AVFoundation
import CoreBluetooth
import EventKit
import UserNotifications

/// Every macOS permission Lumo can use, what it is for, and which of the user's features need it now.
enum AppPermission: String, CaseIterable, Identifiable {
    case accessibility, screenRecording, microphone, camera, calendar, fullDiskAccess, notifications, bluetooth, automation

    var id: Self { self }

    enum Status {
        case granted, missing, unknown
    }

    var symbol: String {
        switch self {
        case .accessibility: return "hand.raised.square.fill"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .microphone: return "mic.fill"
        case .camera: return "camera.fill"
        case .calendar: return "calendar"
        case .fullDiskAccess: return "internaldrive.fill"
        case .notifications: return "bell.badge.fill"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .automation: return "gearshape.2.fill"
        }
    }

    func title(_ t: Localizer) -> String {
        switch self {
        case .accessibility: return t("Универсальный доступ", "Accessibility")
        case .screenRecording: return t("Запись экрана и системного звука", "Screen & system audio recording")
        case .microphone: return t("Микрофон", "Microphone")
        case .camera: return t("Камера", "Camera")
        case .calendar: return t("Календари", "Calendars")
        case .fullDiskAccess: return t("Полный доступ к диску", "Full Disk Access")
        case .notifications: return t("Уведомления", "Notifications")
        case .bluetooth: return "Bluetooth"
        case .automation: return t("Автоматизация", "Automation")
        }
    }

    func purpose(_ t: Localizer) -> String {
        switch self {
        case .accessibility: return t("Видеть клавиши и мышь, двигать окна, вставлять текст за вас", "See keys and the mouse, move windows, paste for you")
        case .screenRecording: return t("Снимки и запись экрана, превью окон, живой эквалайзер, микшер", "Screenshots, recording, window previews, live equalizer, mixer")
        case .microphone: return t("Дорожка микрофона в записи экрана", "The microphone track in recordings")
        case .camera: return t("Камера-зеркало", "The camera mirror")
        case .calendar: return t("Встречи в Dynamic Island", "Meetings in the Dynamic Island")
        case .fullDiskAccess: return t("Чтение уведомлений для Dynamic Island", "Reading notifications for the Dynamic Island")
        case .notifications: return t("Тревоги, готовые задачи агентов", "Alerts, finished agent tasks")
        case .bluetooth: return t("Выключение Bluetooth во сне", "Turning Bluetooth off during sleep")
        case .automation: return t("Тёмная тема, Корзина, Music/Spotify, папка Finder", "Dark Mode, Trash, Music/Spotify, the Finder folder")
        }
    }

    var settingsURL: URL {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .microphone: anchor = "Privacy_Microphone"
        case .camera: anchor = "Privacy_Camera"
        case .calendar: anchor = "Privacy_Calendars"
        case .fullDiskAccess: anchor = "Privacy_AllFiles"
        case .bluetooth: anchor = "Privacy_Bluetooth"
        case .automation: anchor = "Privacy_Automation"
        case .notifications: return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    @MainActor
    var status: Status {
        switch self {
        case .accessibility: return AXIsProcessTrusted() ? .granted : .missing
        case .screenRecording: return CGPreflightScreenCaptureAccess() ? .granted : .missing
        case .microphone: return Self.capture(.audio)
        case .camera: return Self.capture(.video)
        case .calendar: return EKEventStore.authorizationStatus(for: .event) == .fullAccess ? .granted : .missing
        case .fullDiskAccess:
            let probe = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
            return FileManager.default.isReadableFile(atPath: probe.path) ? .granted : .missing
        case .bluetooth: return CBManager.authorization == .allowedAlways ? .granted : (CBManager.authorization == .notDetermined ? .unknown : .missing)
        case .notifications, .automation: return .unknown
        }
    }

    private static func capture(_ type: AVMediaType) -> Status {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: return .granted
        case .notDetermined: return .unknown
        default: return .missing
        }
    }

    /// Features the user has switched on that rely on this permission.
    @MainActor
    func usedBy(_ model: AppModel) -> [FeatureID] {
        let input = model.input
        var features: [FeatureID] = []
        func add(_ feature: FeatureID, _ condition: Bool) { if condition { features.append(feature) } }
        switch self {
        case .accessibility:
            add(.windowLayout, input.windowShortcuts || input.snapByDragging || input.modifierDrag)
            add(.appSwitcher, input.switcherEnabled)
            add(.dock, input.dock.usesAccessibility)
            add(.quitProtection, input.guardQuit || input.guardClose)
            add(.mouse, input.smoothScroll || input.reverseMouse || input.sideButtons || input.linearScroll || input.gestures
                || input.threeFingerMiddleClick || input.focusFollowsMouse || input.clickFilter)
            add(.keyboard, input.keyboard.usesTap)
            add(.clipboard, model.clipboard.isEnabled && model.clipboard.panelHotkey)
            add(.snippets, model.snippets.isEnabled)
            add(.fileTools, model.clipExtras.usesTap)
            add(.audio, model.audio.musicBlocker)
            add(.displays, model.displayTools.usesTap)
        case .screenRecording:
            add(.screenshot, model.capture.useSelector)
            add(.recorder, !model.recorder.recordings.isEmpty)
            add(.appSwitcher, input.switcherEnabled && input.switcherPreviews)
            add(.dock, input.dock.previewEnabled)
            add(.island, model.island.isEnabled && model.island.liveEqualizer)
            add(.mixer, model.mixer.isEnabled)
        case .microphone: add(.recorder, model.recorder.microphone)
        case .camera: add(.island, model.island.isEnabled && model.island.enabledTabs.contains(.camera))
        case .calendar: add(.island, model.island.isEnabled && model.island.enabledTabs.contains(.calendar))
        case .fullDiskAccess: add(.island, model.island.isEnabled && model.island.enabledTabs.contains(.notifications))
        case .notifications: add(.notes, model.agents.finishNotices); add(.optimizer, !model.enabledAlerts.isEmpty)
        case .bluetooth: add(.keepAwake, model.power.bluetoothOnSleep)
        case .automation: add(.fileTools, model.clipExtras.finderPasteImage)
        }
        return features
    }
}
