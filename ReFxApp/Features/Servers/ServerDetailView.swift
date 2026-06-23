import SwiftUI

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
    @State private var tab: Section = .overview

    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview", console = "Console", monitor = "Monitor"
        var id: String { rawValue }
    }

    /// Socket truth wins for the header pill.
    private var state: ServerState { socket.liveState ?? model.effectiveState }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("Section", selection: $tab) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 10)

            switch tab {
            case .overview:
                OverviewTab(model: model, state: state)
            case .console:
                ConsoleView(socket: socket)
            case .monitor:
                MonitorView(model: model, socket: socket)
            }
        }
        .onChange(of: socket.latestStats) { frame in
            if let frame { model.ingest(frame: frame) }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.server?.gameName ?? "—")
                    .font(.subheadline).foregroundStyle(.appMuted)
                StatePill(state: state)
            }
            Spacer()
            ConnectionIndicator(state: socket.connectionState)
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }
}

private struct OverviewTab: View {
    @ObservedObject var model: ServerDetailViewModel
    let state: ServerState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PowerControlsView(model: model, state: state)

                if let connection = model.server?.connectionString {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connection").font(.caption.weight(.semibold))
                            .foregroundStyle(.appMuted)
                        CopyChip(label: "Address", value: connection)
                    }
                }

                if let snapshot = model.snapshot {
                    GaugeRow(snapshot: snapshot)
                }

                if let error = model.actionError {
                    Text(error).font(.footnote).foregroundStyle(.appDestructive)
                }
            }
            .padding(16)
        }
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
