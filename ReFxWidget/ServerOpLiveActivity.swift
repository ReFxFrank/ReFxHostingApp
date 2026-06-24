import WidgetKit
import SwiftUI
import ActivityKit

/// Lock-screen + Dynamic Island presentation for a running server operation.
@available(iOS 16.1, *)
struct ServerOpLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ServerOpAttributes.self) { context in
            // Lock screen / banner.
            HStack(spacing: 12) {
                statusDot(context.state.state, finished: context.state.finished)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.serverName).font(.headline).foregroundStyle(opFG)
                    Text(context.state.detail).font(.caption).foregroundStyle(opMuted)
                }
                Spacer()
                if !context.state.finished {
                    ProgressView().tint(opBrand)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(opSuccess)
                }
            }
            .padding(16)
            .activityBackgroundTint(opBG)
            .activitySystemActionForegroundColor(opFG)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    statusDot(context.state.state, finished: context.state.finished)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.serverName).font(.caption.bold()).foregroundStyle(opFG)
                        Text(context.state.detail).font(.caption2).foregroundStyle(opMuted)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.finished {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(opSuccess)
                    } else {
                        ProgressView().tint(opBrand)
                    }
                }
            } compactLeading: {
                statusDot(context.state.state, finished: context.state.finished)
            } compactTrailing: {
                if context.state.finished {
                    Image(systemName: "checkmark").foregroundStyle(opSuccess)
                } else {
                    ProgressView().tint(opBrand)
                }
            } minimal: {
                statusDot(context.state.state, finished: context.state.finished)
            }
            .widgetURL(URL(string: "refxapp://servers"))
        }
    }

    private func statusDot(_ state: String, finished: Bool) -> some View {
        Circle()
            .fill(finished ? opSuccess : opBrand)
            .frame(width: 10, height: 10)
    }
}

// Local palette (the widget extension can't see the app's theme tokens).
private let opBG = Color(red: 0.04, green: 0.06, blue: 0.10)
private let opFG = Color(red: 0.94, green: 0.97, blue: 1.0)
private let opMuted = Color(red: 0.55, green: 0.62, blue: 0.74)
private let opBrand = Color(red: 0.0, green: 0.45, blue: 1.0)
private let opSuccess = Color(red: 0.18, green: 0.70, blue: 0.45)
