import Foundation
import IOKit.pwr_mgt
import LumoCore
import UserNotifications

enum KeepAwakeState: Equatable {
    case off
    /// `nil` means "until turned off".
    case on(until: Date?)

    var isOn: Bool { self != .off }
}

/// Holds one IOKit power assertion that stops idle sleep (optionally display sleep too).
@MainActor
final class KeepAwakeService {
    private var assertion: IOPMAssertionID?

    func activate(keepDisplayOn: Bool, reason: String) -> Bool {
        deactivate()
        let type = keepDisplayOn ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        var identifier: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason as CFString, &identifier)
        guard result == kIOReturnSuccess else { return false }
        assertion = identifier
        return true
    }

    func deactivate() {
        guard let assertion else { return }
        IOPMAssertionRelease(assertion)
        self.assertion = nil
    }
}

enum AlertKind: String, CaseIterable, Identifiable {
    case cpu, memory, disk, battery, temperature

    var id: Self { self }
}

/// Posts a notification when a condition holds for a while; each kind has its own cooldown.
@MainActor
final class AlertService {
    private var triggers: [AlertKind: AutoTrigger] = [
        .cpu: AutoTrigger(threshold: 0.9, requiredSamples: 8, cooldown: 15 * 60),
        .memory: AutoTrigger(threshold: 1, requiredSamples: 5, cooldown: 15 * 60),
        .disk: AutoTrigger(threshold: 0.9, requiredSamples: 1, cooldown: 6 * 3600),
        .battery: AutoTrigger(threshold: 1, requiredSamples: 1, cooldown: 3600),
        .temperature: AutoTrigger(threshold: 1, requiredSamples: 10, cooldown: 30 * 60),
    ]

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static let hotCelsius = 95.0

    func evaluate(_ snapshot: MonitorSnapshot, temperature: Double?, enabled: Set<AlertKind>, t: Localizer, now: Date) {
        for kind in AlertKind.allCases where enabled.contains(kind) {
            guard var trigger = triggers[kind] else { continue }
            let signal = kind == .temperature ? ((temperature ?? 0) >= Self.hotCelsius ? 1 : 0) : Self.signal(for: kind, in: snapshot)
            let fired = trigger.feed(load: signal, now: now)
            triggers[kind] = trigger
            if fired { post(kind, snapshot: snapshot, temperature: temperature, t: t) }
        }
    }

    private static func signal(for kind: AlertKind, in snapshot: MonitorSnapshot) -> Double {
        switch kind {
        case .cpu: return snapshot.cpuLoad
        case .memory: return snapshot.pressure >= .warning ? 1 : 0
        case .disk: return snapshot.disk.fraction
        case .battery:
            guard let battery = snapshot.battery, !battery.isPluggedIn else { return 0 }
            return battery.charge <= 0.15 ? 1 : 0
        case .temperature:
            return 0
        }
    }

    private func post(_ kind: AlertKind, snapshot: MonitorSnapshot, temperature: Double?, t: Localizer) {
        let content = UNMutableNotificationContent()
        switch kind {
        case .cpu:
            content.title = t("Процессор загружен", "CPU is busy")
            content.body = t("Нагрузка выше 90% уже больше 15 секунд. Откройте Lumo, чтобы найти виновника.",
                             "Load has stayed above 90% for over 15 seconds. Open Lumo to find the culprit.")
        case .memory:
            content.title = t("Не хватает памяти", "Memory pressure")
            content.body = t("macOS сообщает о нехватке оперативной памяти. Lumo поможет освободить её.",
                             "macOS reports memory pressure. Lumo can help free some up.")
        case .disk:
            content.title = t("Диск почти заполнен", "Disk almost full")
            content.body = t("Свободно меньше 10%. Очистите кэши или удалите ненужные файлы.",
                             "Less than 10% free. Clean caches or remove files you don't need.")
        case .battery:
            content.title = t("Низкий заряд", "Low battery")
            content.body = t("Осталось \(Format.percent(snapshot.battery?.charge ?? 0)). Подключите зарядку.",
                             "\(Format.percent(snapshot.battery?.charge ?? 0)) left. Plug in your charger.")
        case .temperature:
            let degrees = Int((temperature ?? Self.hotCelsius).rounded())
            content.title = t("Mac перегревается", "Your Mac is running hot")
            content.body = t("Чип нагрелся до \(degrees)° и держится так уже 20 секунд. Закройте тяжёлые задачи или дайте Mac остыть.",
                             "The chip has been at \(degrees)° for 20 seconds. Close heavy work or let your Mac cool down.")
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: "lumo.\(kind.rawValue)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Shows Lumo's banners even while its popover is open (the app is then "frontmost").
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
