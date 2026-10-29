import Foundation
import GrimoireAppKit
import GrimoireCore
import UserNotifications

/// One local notification per pending reminder, at 09:00 on its due day,
/// with Snooze 3 Days and Add Outcome buttons. Asks for permission once.
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderScheduler()
    static let category = "grimoire.reminder"
    static let snoozeAction = "snooze"
    static let outcomeAction = "outcome"

    /// Test and snapshot runs never touch Notification Center.
    private var enabled: Bool { !Store.isOverridden }

    func start() {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [
                UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 3 Days"),
                UNNotificationAction(identifier: Self.outcomeAction, title: "Add Outcome", options: [.foreground]),
            ], intentIdentifiers: []),
        ])
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            refresh()
        }
    }

    /// Replaces every scheduled reminder with the current pending ones.
    func refresh() {
        guard enabled else { return }
        let model = AppModel.shared
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for r in model.data.reminders where r.status != .done {
            let content = UNMutableNotificationContent()
            content.title = "Needs outcome"
            content.body = r.prompt ?? model.title(for: r.targetId)
            content.categoryIdentifier = Self.category
            content.userInfo = ["reminder": r.id.string, "target": r.targetId.string]
            let parts = r.dueOn.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { continue }
            var when = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 9)
            when.timeZone = .current
            // A reminder already past is shown now.
            let due = Calendar.current.date(from: when) ?? .now
            let trigger: UNNotificationTrigger = due > .now
                ? UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
                : UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            center.add(UNNotificationRequest(identifier: r.id.string, content: content, trigger: trigger))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let reminder = (info["reminder"] as? String).flatMap(ULID.init)
        let target = (info["target"] as? String).flatMap(ULID.init)
        let action = response.actionIdentifier
        await MainActor.run {
            let model = AppModel.shared
            switch action {
            case Self.snoozeAction:
                if let reminder { model.snooze(reminder) }
            case Self.outcomeAction:
                if let target { model.reveal(target); model.sheet = .addOutcome(target) }
            default:
                if let target { model.reveal(target) }
            }
        }
    }
}
