import Foundation
import WidgetKit

/// Publishes a small snapshot of the user's servers to the shared App Group and
/// nudges WidgetKit to refresh, so the Home Screen widget stays current without
/// doing its own authenticated network calls.
enum WidgetBridge {
    static func publish(servers: [Server]) {
        let attention = servers.filter { $0.state.needsAttention }
        let worst = worstState(in: servers)
        let snapshot = ServerSnapshot(
            total: servers.count,
            attention: attention.count,
            worst: worst,
            updatedAt: Date())
        WidgetStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Severity order so the widget surfaces the most important status.
    private static func worstState(in servers: [Server]) -> String {
        guard !servers.isEmpty else { return "NONE" }
        let order: [ServerState] = [.crashed, .suspended, .pendingPayment, .offline,
                                    .installing, .reinstalling, .switchingGame,
                                    .starting, .stopping, .transferring, .running]
        for state in order where servers.contains(where: { $0.state == state }) {
            return state.rawValue
        }
        return servers.first?.state.rawValue ?? "OK"
    }
}
