import SwiftUI
import UserNotifications
import UIKit

// Real-time push (APNs) client scaffolding. This compiles and runs without the
// `aps-environment` entitlement — registration simply fails silently until the
// App ID has Push enabled, the provisioning profile is regenerated with it, and
// the backend exposes the device-token endpoint. Once those are in place it
// activates with no further app changes.

/// Where a tapped notification should take the user.
enum PushRoute: Equatable {
    case server(String)
    case billing
    case support(String?)
}

/// Published target for a tapped push; observed by the tab tree to navigate.
@MainActor
final class PushRouter: ObservableObject {
    static let shared = PushRouter()
    @Published var pending: PushRoute?
    private init() {}

    func route(type rawType: String?, serverId: String?, ticketId: String?) {
        let type = (rawType ?? "").lowercased()
        if type.contains("server"), let serverId { pending = .server(serverId); return }
        if type.contains("invoice") || type.contains("billing") || type.contains("payment") {
            pending = .billing; return
        }
        if type.contains("ticket") || type.contains("support") { pending = .support(ticketId); return }
        if let serverId { pending = .server(serverId) }   // fall back to a server route if an id is present
    }
}

/// Owns the APNs lifecycle: authorization, remote registration, and handing the
/// device token to the backend.
@MainActor
final class PushManager: ObservableObject {
    static let shared = PushManager()
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String?
    /// Diagnostics surfaced in the Notifications settings screen.
    @Published private(set) var serverSynced = false
    @Published private(set) var lastError: String?

    private weak var session: AppSession?
    private init() {}

    func bind(_ session: AppSession) { self.session = session }

    /// Ask for permission (once) and, if granted, register for remote pushes.
    func requestAndRegister() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshStatus()
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Re-register on launch when already authorized (tokens can rotate).
    func registerIfAuthorized() async {
        await refreshStatus()
        if authorizationStatus == .authorized || authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func handle(deviceToken data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = hex
        lastError = nil
        Task {
            guard let account = session?.account else { lastError = "Not signed in"; return }
            do { try await account.registerPushToken(hex); serverSynced = true; lastError = nil }
            catch let error as APIError { serverSynced = false; lastError = error.userMessage }
            catch { serverSynced = false; lastError = "Upload failed: \(error.localizedDescription)" }
        }
    }

    /// Called when APNs registration fails — most often a missing entitlement at
    /// runtime. Surfaced in diagnostics.
    func registrationFailed(_ error: Error) {
        serverSynced = false
        lastError = "APNs registration failed: \(error.localizedDescription)"
    }

    func unregister() {
        guard let token = deviceToken else { return }
        Task { try? await session?.account.unregisterPushToken(token) }
    }
}

/// Minimal app delegate bridged into SwiftUI for the APNs callbacks SwiftUI
/// doesn't surface, plus foreground presentation and tap routing.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushManager.shared.handle(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushManager.shared.registrationFailed(error) }
    }

    // Show banners while the app is foregrounded.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // Route a tapped notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let type = info["type"] as? String
        let serverId = info["serverId"] as? String
        let ticketId = info["ticketId"] as? String
        Task { @MainActor in
            PushRouter.shared.route(type: type, serverId: serverId, ticketId: ticketId)
            completionHandler()
        }
    }
}
