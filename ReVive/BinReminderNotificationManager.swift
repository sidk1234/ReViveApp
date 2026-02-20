import Foundation
import UserNotifications

final class BinReminderNotificationManager {
    static let shared = BinReminderNotificationManager()

    static let reminderRequestID = "revive.bin.reminder.48h"
    static let reminderCategoryID = "revive.bin.reminder.category"

    private init() {}

    func syncPendingBinReminder(markedCount: Int) {
        Task {
            let center = UNUserNotificationCenter.current()

            guard markedCount > 0 else {
                center.removePendingNotificationRequests(withIdentifiers: [Self.reminderRequestID])
                return
            }

            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
                guard granted == true else {
                    center.removePendingNotificationRequests(withIdentifiers: [Self.reminderRequestID])
                    return
                }
            } else if settings.authorizationStatus != .authorized,
                      settings.authorizationStatus != .provisional {
                center.removePendingNotificationRequests(withIdentifiers: [Self.reminderRequestID])
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "ReVive Reminder"
            let itemWord = markedCount == 1 ? "item" : "items"
            content.body = "You have \(markedCount) \(itemWord) in your bin. Have you recycled them yet?"
            content.sound = .default
            content.categoryIdentifier = Self.reminderCategoryID

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 48 * 60 * 60, repeats: true)
            let request = UNNotificationRequest(
                identifier: Self.reminderRequestID,
                content: content,
                trigger: trigger
            )

            center.removePendingNotificationRequests(withIdentifiers: [Self.reminderRequestID])
            try? await center.add(request)
        }
    }
}

extension Notification.Name {
    static let reviveOpenBin = Notification.Name("revive.openBin")
}

