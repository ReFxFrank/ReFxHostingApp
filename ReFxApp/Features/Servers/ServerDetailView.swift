import SwiftUI

/// The server screen: a scrollable overview (status, power, live gauges,
/// connection) followed by the full **section menu** mirroring the web client
/// area's sidebar. Sections push native screens where built (Console, Files) and
/// otherwise offer an "open on web" fallback so every feature is reachable.
struct ServerDetailView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: ServerDetailViewModel

    init(serverId: String, preview: Server?) {
        _model = StateObject(wrappedValue:
            ServerDetailViewModel(serverId: serverId, preview: preview))
    }

    var body: some View {
        Group {
            if let socket = model.socket {
                ServerDetailContent(model: model, socket: socket)
            } else {
                LaunchView()
            }
        }
        .navigationTitle(model.server?.name ?? "Server")
        .navigationBarTitleDisplayMode(.inline)
        .screenBackground()
        .task {
            model.bind(session)
            await model.loadDetail()
            model.startStreaming()
        }
        .onDisappear { model.stopStreaming() }
    }
}

private struct ServerDetailContent: View {
    @ObservedObject var model: ServerDetailViewModel
    @ObservedObject var socket: ConsoleSocket
    @EnvironmentObject private var config: AppConfig

    /// Socket truth wins for the header pill.
    private var state: ServerState { socket.liveState ?? model.effectiveState }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                PowerControlsView(model: model, state: state)

                if let connection = model.server?.connectionString {
                    CopyChip(label: "Address", value: connection)
                }

                if let snapshot = model.snapshot {
                    GaugeRow(snapshot: snapshot)
                }

                if let error = model.actionError {
                    Text(error).font(.footnote).foregroundStyle(.appDestructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                sectionMenu
            }
            .padding(16)
        }
        .onChange(of: socket.latestStats) { frame in
            if let frame { model.ingest(frame: frame) }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.server?.gameName ?? "—")
                    .font(.subheadline).foregroundStyle(.appMuted)
                StatePill(state: state)
            }
            Spacer()
            ConnectionIndicator(state: socket.connectionState)
        }
    }

    @ViewBuilder
    private var sectionMenu: some View {
        if let server = model.server {
            VStack(alignment: .leading, spacing: 8) {
                Text("Manage").font(.caption.weight(.semibold)).foregroundStyle(.appMuted)
                    .padding(.leading, 4)
                VStack(spacing: 10) {
                    if server.state == .pendingPayment {
                        Button {
                            WebLink.open(config.webOrigin, path: "billing")
                        } label: {
                            ManageRow(icon: "creditcard", title: "Pay now",
                                      subtitle: "Activate this server", accent: .appWarning)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(ServerSection.sections(for: server)) { section in
                        sectionRow(section, server: server)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionRow(_ section: ServerSection, server: Server) -> some View {
        let label = ManageRow(icon: section.icon, title: section.label, subtitle: section.subtitle)
        switch section {
        case .console:
            NavigationLink { ConsoleScreen(socket: socket) } label: { label }
                .buttonStyle(.plain)
        case .files:
            NavigationLink { FilesBrowserView(serverId: model.serverId) } label: { label }
                .buttonStyle(.plain)
        case .backups:
            NavigationLink { BackupsView(serverId: model.serverId) } label: { label }
                .buttonStyle(.plain)
        case .settings:
            NavigationLink { ServerSettingsView(serverId: model.serverId) } label: { label }
                .buttonStyle(.plain)
        case .schedules:
            NavigationLink { SchedulesView(serverId: model.serverId) } label: { label }
                .buttonStyle(.plain)
        case .databases:
            NavigationLink { DatabasesView(serverId: model.serverId) } label: { label }
                .buttonStyle(.plain)
        case .switchGame:
            NavigationLink { SwitchGameView(serverId: model.serverId) } label: { label }
                .buttonStyle(.plain)
        case .workshop:
            NavigationLink { WorkshopView(serverId: model.serverId) } label: { label }
                .buttonStyle(.plain)
        case .minecraft:
            NavigationLink { MinecraftView(serverId: model.serverId) } label: { label }
                .buttonStyle(.plain)
        case .mods:
            NavigationLink { ModsView(serverId: model.serverId) } label: { label }
                .buttonStyle(.plain)
        case .modpacks:
            NavigationLink { ModpacksView(serverId: model.serverId) } label: { label }
                .buttonStyle(.plain)
        case .voice:
            NavigationLink { VoiceView(serverId: model.serverId) } label: { label }
                .buttonStyle(.plain)
        default:
            if section.isWebLinkOut {
                Button {
                    WebLink.open(config.webOrigin, path: "servers/\(model.serverId)/\(section.webPath)")
                } label: { label }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    SectionStubView(section: section, serverId: model.serverId)
                } label: { label }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Console as its own pushed screen. The socket (and its buffer) lives on the
/// detail view model, so it stays connected and the scrollback survives push/pop.
struct ConsoleScreen: View {
    @ObservedObject var socket: ConsoleSocket
    var body: some View {
        ConsoleView(socket: socket)
            .navigationTitle("Console")
            .navigationBarTitleDisplayMode(.inline)
            .screenBackground()
    }
}

/// Placeholder for a section whose native screen isn't built yet. Offers an
/// "open on web" fallback so the feature is still reachable.
struct SectionStubView: View {
    let section: ServerSection
    let serverId: String
    @EnvironmentObject private var config: AppConfig

    var body: some View {
        ComingSoonView(
            icon: section.icon,
            title: section.label,
            message: "A native \(section.label) screen is on the way. For now you can manage this on the web.",
            actionTitle: "Open on web",
            action: { WebLink.open(config.webOrigin, path: "servers/\(serverId)/\(section.webPath)") })
        .navigationTitle(section.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ConnectionIndicator: View {
    let state: ConsoleSocket.ConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(.appMuted)
        }
    }

    private var label: String {
        switch state {
        case .idle: return "Idle"
        case .connecting: return "Connecting…"
        case .connected: return "Live"
        case .reconnecting: return "Reconnecting…"
        case .forbidden: return "No access"
        case .failed: return "Offline"
        }
    }
    private var color: Color {
        switch state {
        case .connected: return .appSuccess
        case .connecting, .reconnecting: return .appWarning
        default: return .appMuted
        }
    }
}

/// A tappable management row used in the server section menu.
struct ManageRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var accent: Color = .appPrimary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.appForeground)
                Text(subtitle).font(.caption).foregroundStyle(.appMuted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.appMuted)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
