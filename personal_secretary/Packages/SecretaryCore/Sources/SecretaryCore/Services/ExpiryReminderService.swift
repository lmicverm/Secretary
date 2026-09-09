import Foundation
import UserNotifications

public enum ExpiryReminderService {
    public static let categoryID = "DOCUMENT_EXPIRY"

    public static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    public static func schedule(for record: DocumentRecord, daysBefore: Int = 30) {
        guard let expiry = record.expiryDate else {
            cancel(documentID: record.id)
            return
        }
        let fireDate = Calendar.current.date(byAdding: .day, value: -daysBefore, to: expiry) ?? expiry
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Document expiring soon"
        content.body = "\(record.displayTitle) expires on \(Self.formatted(expiry))."
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = ["documentID": record.id]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationID(for: record.id),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    public static func cancel(documentID: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID(for: documentID)])
    }

    public static func rescheduleAll(from records: [DocumentRecord], daysBefore: Int = 30) {
        for record in records where record.expiryDate != nil {
            schedule(for: record, daysBefore: daysBefore)
        }
    }

    private static func notificationID(for documentID: String) -> String {
        "expiry.\(documentID)"
    }

    private static func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}
