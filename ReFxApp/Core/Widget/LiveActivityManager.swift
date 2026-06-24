import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Starts/updates/ends a Live Activity for a long-running server operation so
/// progress shows on the lock screen and Dynamic Island. iOS 16.1+; a no-op on
/// older systems or when Live Activities are disabled by the user.
enum LiveActivityManager {

    private static let transitional: Set<ServerState> = [
        .installing, .starting, .stopping, .reinstalling, .switchingGame, .transferring,
    ]

    static func sync(serverId: String, name: String, game: String, state: ServerState) {
        guard #available(iOS 16.1, *) else { return }
        Task { await syncImpl(serverId: serverId, name: name, game: game, state: state) }
    }

    @available(iOS 16.1, *)
    private static func syncImpl(serverId: String, name: String, game: String, state: ServerState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let isOp = transitional.contains(state)
        let content = ServerOpAttributes.ContentState(
            state: state.rawValue, detail: detail(for: state), finished: !isOp)
        let existing = Activity<ServerOpAttributes>.activities.first { $0.attributes.serverId == serverId }

        if isOp {
            if let existing {
                await existing.update(using: content)
            } else {
                let attributes = ServerOpAttributes(serverId: serverId, serverName: name, game: game)
                _ = try? Activity.request(attributes: attributes, contentState: content, pushType: nil)
            }
        } else if let existing {
            // Reached a terminal state — show the result briefly, then dismiss.
            await existing.update(using: content)
            await existing.end(dismissalPolicy: .after(.now + 4))
        }
    }

    private static func detail(for state: ServerState) -> String {
        switch state {
        case .installing: return "Installing…"
        case .reinstalling: return "Reinstalling…"
        case .switchingGame: return "Switching game…"
        case .starting: return "Starting up…"
        case .stopping: return "Stopping…"
        case .transferring: return "Transferring…"
        case .running: return "Now running"
        case .offline: return "Stopped"
        case .crashed: return "Crashed"
        case .suspended: return "Suspended"
        default: return state.label
        }
    }
}
