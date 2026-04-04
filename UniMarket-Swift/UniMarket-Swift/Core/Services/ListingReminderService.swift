import Foundation
import UserNotifications

actor ListingReminderService {
    static let shared = ListingReminderService()

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let reminderInterval: TimeInterval = 60 * 60 * 24 * 7

    private init() {}

    func recordListing(for userID: String, at date: Date) async {
        defaults.set(date, forKey: lastListingDateKey(for: userID))
        await scheduleReminder(for: userID, lastListingDate: date)
    }

    func syncReminder(for userID: String, lastListingDate: Date?) async {
        guard let lastListingDate else {
            defaults.removeObject(forKey: lastListingDateKey(for: userID))
            center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier(for: userID)])
            return
        }

        defaults.set(lastListingDate, forKey: lastListingDateKey(for: userID))
        await scheduleReminder(for: userID, lastListingDate: lastListingDate)
    }

    func clearReminder(for userID: String) {
        defaults.removeObject(forKey: lastListingDateKey(for: userID))
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier(for: userID)])
    }

    private func scheduleReminder(for userID: String, lastListingDate: Date) async {
        let granted = await requestAuthorizationIfNeeded()
        guard granted else { return }

        let fireDate = max(lastListingDate.addingTimeInterval(reminderInterval), .now.addingTimeInterval(5))
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to post a new item"
        content.body = "It has been 7 days since your last listing. Add a new clothing item to keep your closet moving."
        content.sound = .default

        let identifier = notificationIdentifier(for: userID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )

        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule reminder: \(error.localizedDescription)")
        }
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                print("Failed to request notification authorization: \(error.localizedDescription)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func notificationIdentifier(for userID: String) -> String {
        "listing-reminder-\(userID)"
    }

    private func lastListingDateKey(for userID: String) -> String {
        "listing-reminder.last-listing.\(userID)"
    }
}
