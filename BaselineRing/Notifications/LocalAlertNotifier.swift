import Foundation
import UserNotifications
import BaselineCore

enum LocalAlertNotifier {
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func post(_ alerts: [AlertDraft]) async {
        let center = UNUserNotificationCenter.current()
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = "Baseline Ring"
            content.body = alert.message
            content.sound = .default
            let day = alert.day.timeIntervalSince1970
            let identifier = "baseline-\(alert.metric.rawValue)-\(day)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}
