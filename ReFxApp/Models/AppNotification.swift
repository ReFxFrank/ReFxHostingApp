import Foundation

/// `GET /account/notifications` (returns a plain array under the data envelope).
struct AppNotification: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let readAt: Date?
    let createdAt: Date

    var isUnread: Bool { readAt == nil }
}

/// `GET /account/notifications/unread-count` → `{ unread: Int }`.
struct UnreadCount: Codable, Equatable {
    let unread: Int
}
