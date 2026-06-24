import WidgetKit
import SwiftUI

// MARK: - Timeline

struct ServersEntry: TimelineEntry {
    let date: Date
    let snapshot: ServerSnapshot
}

struct ServersProvider: TimelineProvider {
    func placeholder(in context: Context) -> ServersEntry {
        ServersEntry(date: Date(), snapshot: ServerSnapshot(total: 3, attention: 1, worst: "OFFLINE", updatedAt: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (ServersEntry) -> Void) {
        completion(ServersEntry(date: Date(), snapshot: WidgetStore.load() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ServersEntry>) -> Void) {
        let entry = ServersEntry(date: Date(), snapshot: WidgetStore.load() ?? .empty)
        // Best-effort refresh; the app also reloads timelines after each fetch.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Presentation

private enum WidgetStatus {
    static func color(_ worst: String) -> Color {
        switch worst {
        case "RUNNING": return Color(red: 0.18, green: 0.70, blue: 0.45)
        case "OFFLINE", "NONE", "OK": return Color(red: 0.45, green: 0.55, blue: 0.68)
        case "CRASHED", "SUSPENDED", "PENDING_PAYMENT": return Color(red: 0.86, green: 0.30, blue: 0.30)
        default: return Color(red: 0.95, green: 0.70, blue: 0.20)
        }
    }
    static func label(_ worst: String) -> String {
        switch worst {
        case "RUNNING": return "All running"
        case "OFFLINE": return "Offline"
        case "CRASHED": return "Crashed"
        case "SUSPENDED": return "Suspended"
        case "PENDING_PAYMENT": return "Awaiting payment"
        case "OK", "NONE": return "No servers"
        default: return worst.capitalized
        }
    }
}

private let widgetBG = Color(red: 0.04, green: 0.06, blue: 0.10)
private let widgetFG = Color(red: 0.94, green: 0.97, blue: 1.0)
private let widgetMuted = Color(red: 0.55, green: 0.62, blue: 0.74)
private let brand = Color(red: 0.0, green: 0.45, blue: 1.0)

struct ReFxWidgetView: View {
    let entry: ServersEntry
    @Environment(\.widgetFamily) private var family

    private var s: ServerSnapshot { entry.snapshot }
    private var attention: Bool { s.attention > 0 }

    var body: some View {
        ZStack {
            widgetBG
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("ReFx").font(.caption.bold()).foregroundStyle(brand)
                    Spacer()
                    Circle().fill(WidgetStatus.color(s.worst)).frame(width: 9, height: 9)
                }
                Spacer()
                Text("\(s.total)").font(.system(size: family == .systemSmall ? 40 : 48, weight: .bold))
                    .foregroundStyle(widgetFG)
                Text(s.total == 1 ? "server" : "servers").font(.caption).foregroundStyle(widgetMuted)
                Spacer()
                if attention {
                    Label("\(s.attention) need attention", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetStatus.color(s.worst))
                        .lineLimit(1)
                } else {
                    Text(WidgetStatus.label(s.worst)).font(.caption2).foregroundStyle(widgetMuted)
                }
            }
            .padding(14)
        }
        .widgetURL(URL(string: "refxapp://servers"))
    }
}

struct ReFxServersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.kind, provider: ServersProvider()) { entry in
            if #available(iOS 17.0, *) {
                ReFxWidgetView(entry: entry).containerBackground(widgetBG, for: .widget)
            } else {
                ReFxWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Servers")
        .description("Your server count and worst status at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ReFxWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReFxServersWidget()
        if #available(iOS 16.1, *) {
            ServerOpLiveActivity()
        }
    }
}
