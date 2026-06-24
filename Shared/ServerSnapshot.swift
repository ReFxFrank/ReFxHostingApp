import Foundation

/// A tiny, self-contained snapshot the app writes to a shared App Group so the
/// Home Screen widget can render without doing its own authenticated network
/// calls. Kept dependency-free (no app types) so it compiles in both targets.
struct ServerSnapshot: Codable, Equatable {
    let total: Int
    let attention: Int
    /// Worst server state raw value (e.g. "RUNNING", "OFFLINE"), or "OK"/"NONE".
    let worst: String
    let updatedAt: Date

    static let empty = ServerSnapshot(total: 0, attention: 0, worst: "NONE", updatedAt: .distantPast)
}

/// Read/write the widget snapshot via the shared App Group.
enum WidgetStore {
    static let appGroup = "group.com.refx.app"
    static let snapshotKey = "refx.widget.snapshot"
    static let kind = "ReFxServersWidget"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func save(_ snapshot: ServerSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    static func load() -> ServerSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(ServerSnapshot.self, from: data)
    }
}
