// SPDX-License-Identifier: GPL-3.0-or-later
//
// Freescale – lokale Körperwaagen-App

import Foundation
import UserNotifications

/// Plant/entfernt die tägliche Wiege-Erinnerung als lokale Benachrichtigung.
enum ReminderManager {
    static let identifier = "freescale.daily.reminder"

    static func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
    }

    static func schedule(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Zeit zum Wiegen"
        content.body = "Stell dich morgens auf die Waage – am besten immer zur gleichen Zeit für vergleichbare Werte."
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
