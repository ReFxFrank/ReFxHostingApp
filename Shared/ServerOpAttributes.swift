import Foundation
import ActivityKit

/// Live Activity attributes for a long-running server operation (install,
/// reinstall, game switch, restart). Shared between the app (which starts /
/// updates / ends the activity) and the widget extension (which renders it).
/// Live Activities are iOS 16.1+.
@available(iOS 16.1, *)
struct ServerOpAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Server state raw value driving the label/colour (e.g. "INSTALLING").
        var state: String
        /// Short human detail line.
        var detail: String
        /// True once the op reached a terminal state.
        var finished: Bool
    }

    var serverId: String
    var serverName: String
    var game: String
}
