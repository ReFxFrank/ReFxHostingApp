import Foundation
import UserNotifications

/// Schedules *local* notifications for server-health changes and ticket replies.
///
/// NOTE: This is NOT real-time. iOS decides when (and whether) a
/// `BGAppRefreshTask` runs, so these alerts are best-effort. True instant alerts
/// need APNs server push — a backend TODO (device-token registration +
/// send-on-event). This layer is deliberately the only place that builds alerts
/// so swapping in an APNs-driven path later is a localized change.
enum LocalNotifications {
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func notify(title: String, body: String, identifier: String = UUID().uuidString,
                       serverId: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let serverId { content.userInfo = ["serverId": serverId] }
        // nil trigger = deliver as soon as possible.
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static func setBadge(_ count: Int) {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }
}
