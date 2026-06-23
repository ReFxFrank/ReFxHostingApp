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
    private var didRefreshForAuth = false

    init(serverId: String,
         origin: URL,
         tokenProvider: @escaping () async -> String?,
         refreshHandler: @escaping () async -> Bool) {
        self.serverId = serverId
        self.origin = origin
        self.tokenProvider = tokenProvider
        self.refreshHandler = refreshHandler
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

    func clearBuffer() { lines.removeAll() }

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
        let manager = SocketManager(socketURL: origin, config: [
            .log(false),
            .compress,
            .forceWebsockets(true),
            .reconnects(true),
            .reconnectWait(2),
            .reconnectWaitMax(30),
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
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self else { return }
            self.connectionState = .connected
            self.didRefreshForAuth = false
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
            let line = dict["line"] as? String ?? ""
            let stream = dict["stream"] as? String ?? "stdout"
            self?.append(ConsoleLine(text: line, stream: stream))
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

    private func append(_ line: ConsoleLine) {
        lines.append(line)
        if lines.count > bufferLimit {
            lines.removeFirst(lines.count - bufferLimit)
        }
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
