import Foundation
import SwiftUI
import UIKit

@MainActor
final class ServerDetailViewModel: ObservableObject {
    @Published private(set) var detail: LoadState<Server>
    @Published private(set) var snapshot: ResourceSnapshot?
    @Published private(set) var powerInFlight: PowerSignal?
    @Published var actionError: String?

    /// The live state always wins over the last-loaded REST state once the
    /// socket starts pushing `power`/`stats` frames. Changes drive the Live
    /// Activity (install/restart/game-switch progress on the lock screen).
    @Published var liveState: ServerState? {
        didSet {
            guard let state = liveState, state != oldValue, let server = server else { return }
            LiveActivityManager.sync(serverId: serverId, name: server.name,
                                     game: server.gameName, state: state)
        }
    }

    let serverId: String
    private(set) var socket: ConsoleSocket?

    private var service: ServersService?
    private var session: AppSession?
    private var lastPowerTap = Date.distantPast

    init(serverId: String, preview: Server?) {
        self.serverId = serverId
        self.detail = preview.map { .loaded($0) } ?? .idle
        self.liveState = preview?.state
    }

    var server: Server? { detail.value }

    /// Effective state for the header: socket truth if present, else REST.
    var effectiveState: ServerState {
        liveState ?? server?.state ?? .unknown
    }

    func bind(_ session: AppSession) {
        guard service == nil else { return }
        self.session = session
        self.service = session.servers
        let auth = session.authStore
        socket = ConsoleSocket(
            serverId: serverId,
            origin: session.config.socketOrigin,
            tokenProvider: { await auth.currentAccessToken() },
            // AuthStore is the single source of truth the REST client reads from
            // too, so a successful refresh here also re-tokens REST calls.
            refreshHandler: { await auth.refreshIfPossible() })
    }

    // MARK: - Loading

    func loadDetail() async {
        guard let service else { return }
        if detail.value == nil { detail = .loading }
        do {
            let server = try await service.detail(serverId)
            detail = .loaded(server)
            if liveState == nil { liveState = server.state }
            await loadStats(cpuCores: server.cpuCores, diskTotalMb: server.diskMb.map(Double.init))
        } catch let error as APIError {
            if detail.value == nil { detail = .failed(error) }
        } catch {
            if detail.value == nil {
                detail = .failed(.network(isOffline: false, underlying: error.localizedDescription))
            }
        }
    }

    private func loadStats(cpuCores: Double?, diskTotalMb: Double?) async {
        guard let service else { return }
        if let live = try? await service.stats(serverId) {
            snapshot = ResourceSnapshot(live: live, cpuCores: cpuCores, diskTotalMb: diskTotalMb)
            // The live stats carry the agent's current state — use it so the
            // pill is accurate on open instead of showing the stale REST state
            // until the first socket frame arrives.
            if let raw = live.state, let state = ServerState(rawValue: raw) {
                liveState = state
            }
        }
    }

    func startStreaming() {
        socket?.connect()
    }

    func stopStreaming() {
        socket?.disconnect()
        // We can't update a Live Activity once we leave (no push), so tear it
        // down rather than leave a frozen op pill on the Dynamic Island.
        LiveActivityManager.end(serverId: serverId)
    }

    /// Fold socket stats frames into the gauge snapshot.
    func ingest(frame: StatsFrame) {
        let diskTotal = server?.diskMb.map(Double.init)
        let memTotal = snapshot?.memTotalMb
        snapshot = ResourceSnapshot(frame: frame, previous: snapshot,
                                    cpuCores: server?.cpuCores,
                                    memTotalMb: memTotal, diskTotalMb: diskTotal)
    }

    // MARK: - Power

    func power(_ signal: PowerSignal) async {
        guard let service else { return }
        // Debounce rapid taps (e.g. double-tap restart).
        guard Date().timeIntervalSince(lastPowerTap) > 0.8 else { return }
        lastPowerTap = Date()

        actionError = nil
        powerInFlight = signal
        defer { powerInFlight = nil }

        // Optimistic transitional state; reconciled by the socket `power` frame.
        applyOptimisticState(for: signal)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        do {
            try await service.power(serverId, signal: signal)
        } catch let error as APIError {
            actionError = error.userMessage
            // Roll back optimism on failure; refresh from server truth.
            await loadDetail()
        } catch {
            actionError = "Action failed. Try again."
        }
    }

    private func applyOptimisticState(for signal: PowerSignal) {
        switch signal {
        case .start: liveState = .starting
        case .restart: liveState = .stopping
        case .stop, .kill: liveState = .stopping
        }
    }
}
