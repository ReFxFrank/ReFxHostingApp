import Foundation
import SocketIO

/// Live console + resource stream for one server, over Socket.IO namespace
/// `/ws/console` (NOT a raw WebSocket — the server speaks the Socket.IO
/// protocol). Owned by `ServerDetailViewModel` so the console buffer survives
/// switching between the Console/Monitor sub-tabs.
///
/// Handshake auth: the access token is sent as the CONNECT-packet auth payload
/// (`{ token }`), matching the gateway's `client.handshake.auth.token`. On token
/// expiry the server disconnects with `error { message: "unauthorized" }`; we
/// refresh and reconnect with the new token. `SocketManager` handles
/// network-drop reconnection with backoff.
///
/// Concurrency: `handleQueue` is the main queue, so all Socket.IO callbacks fire
/// on main and mutate `@Published` state safely. Anything after an `await` hops
/// back to the main actor before touching state.
final class ConsoleSocket: ObservableObject {
    enum ConnectionState: Equatable {
        case idle, connecting, connected, reconnecting, forbidden, failed(String)
    }

    struct ConsoleLine: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let stream: String
        /// Per-server monotonic sequence from the gateway (>= 1); nil for local
        /// echoes / injected lines and for degraded frames (`seq: 0`). Used to
        /// dedup backlog against live output.
        var seq: Int? = nil
        var isError: Bool { stream == "stderr" }
    }

    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var lines: [ConsoleLine] = []
    @Published private(set) var latestStats: StatsFrame?
    @Published private(set) var liveState: ServerState?

    private let serverId: String
    private let origin: URL
    private let tokenProvider: () async -> String?
    private let refreshHandler: () async -> Bool

    private var manager: SocketManager?
    private var socket: SocketIOClient?

    /// Cap the in-memory console buffer so a chatty server can't grow unbounded.
    private let bufferLimit = 2000
    /// Line seqs already rendered, so the `console_history` backlog is deduped
    /// against live frames (and the subscribe-overlap / reconnect overlap).
    private var seenSeqs: Set<Int> = []
    private var didRefreshForAuth = false
    /// Only surface one connection-error line per connect attempt (reconnect loops
    /// would otherwise spam the buffer).
    private var didLogConnectError = false

    init(serverId: String,
         origin: URL,
         tokenProvider: @escaping () async -> String?,
         refreshHandler: @escaping () async -> Bool) {
        self.serverId = serverId
        self.origin = origin
        self.tokenProvider = tokenProvider
        self.refreshHandler = refreshHandler
        // Seed from this session's per-server backlog so re-opening a server's
        // console shows its history instantly (before the socket resubscribes).
        self.lines = ConsoleHistory.shared.lines(for: serverId)
        // Prime dedup so the server's `console_history` replay merges cleanly with
        // what we already have and only fills the gap produced while we were away.
        self.seenSeqs = Set(self.lines.compactMap { $0.seq })
    }

    // MARK: - Lifecycle (called on main from the view)

    func connect() {
        guard connectionState == .idle || isFailed else { return }
        connectionState = .connecting
        Task { await establish() }
    }

    func disconnect() {
        socket?.disconnect()
        manager?.disconnect()
        socket = nil
        manager = nil
        connectionState = .idle
    }

    func sendCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, connectionState == .connected else { return }
        socket?.emit("command", ["command": trimmed])
        append(ConsoleLine(text: "> \(trimmed)", stream: "input")) // local echo
    }

    func clearBuffer() {
        lines.removeAll()
        ConsoleHistory.shared.clear(serverId)
    }

    // MARK: - Connection

    private func establish() async {
        let token = await tokenProvider()
        await MainActor.run {
            guard let token else {
                self.connectionState = .failed("Not signed in")
                return
            }
            self.buildAndConnect(token: token)
        }
    }

    @MainActor
    private func buildAndConnect(token: String) {
        // Mirror the web client: allow BOTH transports so a blocked websocket
        // upgrade falls back to long-polling instead of silently never
        // connecting. (Forcing websockets was the bug behind "console doesn't
        // live-update".)
        let manager = SocketManager(socketURL: origin, config: [
            // The panel gateway is Socket.IO v4 (EIO4). The client MUST speak v3/v4
            // or the CONNECT-packet auth (`handshake.auth.token`) is never delivered
            // — the connection then fails auth and nothing streams. This was the bug
            // behind "console connects but shows nothing / commands do nothing".
            .version(.three),
            .log(false),
            .compress,
            .reconnects(true),
            .reconnectWait(2),
            .reconnectWaitMax(15),
            .reconnectAttempts(-1),
            .handleQueue(DispatchQueue.main),
            .extraHeaders(["Authorization": "Bearer \(token)"]),
        ])
        let socket = manager.socket(forNamespace: "/ws/console")
        self.manager = manager
        self.socket = socket
        registerHandlers(on: socket)
        // Send the token as the CONNECT auth payload (handshake.auth.token).
        socket.connect(withPayload: ["token": token])
    }

    private func registerHandlers(on socket: SocketIOClient) {
        #if DEBUG
        // Log EVERY event the server sends, so a name/shape mismatch is visible in
        // the Xcode console (event name + payload). Invaluable for diagnosing the
        // live gateway contract without guessing.
        socket.onAny { event in
            print("🖥️ console event: \(event.event)  \(event.items ?? [])")
        }
        #endif

        // Transport / handshake failures fire the client-level `.error` event (NOT
        // the server's app-level `"error"` event). Without this handler they were
        // silent — a failed connect looked like an empty console. Surface it.
        socket.on(clientEvent: .error) { [weak self] data, _ in
            guard let self else { return }
            let reason = (data.first as? String) ?? String(describing: data.first ?? "connection error")
            #if DEBUG
            print("🖥️ console connect_error: \(data)")
            #endif
            guard self.connectionState != .forbidden, !self.didLogConnectError else { return }
            self.didLogConnectError = true
            self.append(ConsoleLine(text: "Console connection error: \(reason)", stream: "stderr"))
        }

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self else { return }
            self.connectionState = .connected
            self.didRefreshForAuth = false
            self.didLogConnectError = false
            socket.emit("subscribe", ["serverId": self.serverId])
        }

        socket.on(clientEvent: .reconnect) { [weak self] _, _ in
            guard let self, self.connectionState != .forbidden else { return }
            self.connectionState = .reconnecting
        }

        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            guard let self, self.connectionState == .connected else { return }
            self.connectionState = .reconnecting
        }

        socket.on("subscribed") { [weak self] _, _ in
            self?.connectionState = .connected
        }

        socket.on("error") { [weak self] data, _ in
            guard let self else { return }
            let message = (data.first as? [String: Any])?["message"] as? String ?? "error"
            if message == "unauthorized" {
                self.handleUnauthorized()
            } else if message == "forbidden" {
                self.connectionState = .forbidden
                self.append(ConsoleLine(text: "You don't have console access to this server.",
                                        stream: "stderr"))
            }
        }

        socket.on("console") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            self?.ingest(frame: dict)
        }

        // Recent backlog replayed once on subscribe: `{ serverId, lines: [frame] }`,
        // oldest → newest, each frame byte-identical to a live `console` frame.
        // Merged/deduped by `seq`, so it fills the gap since we last watched and
        // drops the small subscribe/reconnect overlap.
        socket.on("console_history") { [weak self] data, _ in
            guard let self, let dict = data.first as? [String: Any],
                  let frames = dict["lines"] as? [[String: Any]] else { return }
            for frame in frames { self.ingest(frame: frame) }
        }

        socket.on("stats") { [weak self] data, _ in
            guard let self, let dict = data.first as? [String: Any],
                  let frame: StatsFrame = Decode.from(dict) else { return }
            self.latestStats = frame
            if let raw = frame.state, let state = ServerState(rawValue: raw) {
                self.liveState = state
            }
        }

        socket.on("power") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let raw = dict["state"] as? String,
                  let state = ServerState(rawValue: raw) else { return }
            self?.liveState = state
        }
    }

    /// Token expired mid-stream: refresh once, then reconnect with the new token.
    private func handleUnauthorized() {
        guard !didRefreshForAuth else {
            connectionState = .failed("Session expired")
            return
        }
        didRefreshForAuth = true
        connectionState = .reconnecting
        Task {
            let ok = await refreshHandler()
            await MainActor.run {
                self.disconnect()
                if ok {
                    self.connectionState = .connecting
                    Task { await self.establish() }
                } else {
                    self.connectionState = .failed("Session expired")
                }
            }
        }
    }

    // MARK: - Helpers

    /// Decode a `console` / `console_history` frame and append it, deduped by the
    /// gateway `seq` (a real seq is >= 1; `seq: 0`/absent means degraded/no id, so
    /// it's always kept — no replay is sent in that mode, so there's nothing to
    /// duplicate against). Frames arrive oldest → newest, so appending preserves
    /// order (the socket delivers `console_history` before any live frame).
    private func ingest(frame dict: [String: Any]) {
        let rawSeq = (dict["seq"] as? Int) ?? (dict["seq"] as? NSNumber)?.intValue
        let seq: Int? = (rawSeq ?? 0) >= 1 ? rawSeq : nil
        if let seq {
            guard !seenSeqs.contains(seq) else { return }
            seenSeqs.insert(seq)
        }
        let line = dict["line"] as? String ?? ""
        let stream = dict["stream"] as? String ?? "stdout"
        append(ConsoleLine(text: line, stream: stream, seq: seq))
    }

    private func append(_ line: ConsoleLine) {
        lines.append(line)
        if lines.count > bufferLimit {
            let overflow = lines.count - bufferLimit
            // Keep seenSeqs bounded to the live buffer: dropped lines can't
            // reappear (the server's backlog is far smaller than our cap).
            for trimmed in lines.prefix(overflow) {
                if let s = trimmed.seq { seenSeqs.remove(s) }
            }
            lines.removeFirst(overflow)
        }
        // Persist so the backlog survives leaving/re-opening this server.
        ConsoleHistory.shared.store(lines, for: serverId)
    }

    private var isFailed: Bool {
        if case .failed = connectionState { return true }
        return false
    }
}

/// Decode a `[String: Any]` socket payload into a Decodable struct.
private enum Decode {
    static func from<T: Decodable>(_ dict: [String: Any]) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
