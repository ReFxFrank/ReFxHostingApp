import Foundation

/// REST surface for servers: list (paginated), detail, power, command, stats.
/// Path params confirmed against `servers.controller.ts` (note the power body is
/// `{ signal }`, not `{ action }`).
struct ServersService {
    let client: APIClient

    func list(page: Int = 1, pageSize: Int = 25, query: String? = nil) async throws -> Page<Server> {
        var items = [URLQueryItem(name: "page", value: String(page)),
                     URLQueryItem(name: "pageSize", value: String(pageSize))]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        return try await client.sendPaginated(.get("servers", query: items))
    }

    func detail(_ id: String) async throws -> Server {
        try await client.send(.get("servers/\(id)"))
    }

    /// `POST /servers/:id/power { signal }`. Signal ∈ start|stop|restart|kill.
    func power(_ id: String, signal: PowerSignal) async throws {
        try await client.sendVoid(.post("servers/\(id)/power", body: PowerBody(signal: signal.rawValue)))
    }

    /// One-shot console command (fallback when the socket isn't connected).
    func sendCommand(_ id: String, command: String) async throws {
        try await client.sendVoid(.post("servers/\(id)/command", body: CommandBody(command: command)))
    }

    /// Live snapshot (`LiveStats`) — used to seed gauges before the socket
    /// delivers its first frame.
    func stats(_ id: String) async throws -> LiveStats {
        try await client.send(.get("servers/\(id)/stats"))
    }

    private struct PowerBody: Encodable { let signal: String }
    private struct CommandBody: Encodable { let command: String }
}

enum PowerSignal: String, CaseIterable {
    case start, stop, restart, kill

    var label: String { rawValue.capitalized }
    var isDestructive: Bool { self == .stop || self == .kill || self == .restart }
    /// Per-server permission required (server owners / admins always pass).
    var requiredPermission: String {
        switch self {
        case .start: return Permission.controlStart
        case .stop: return Permission.controlStop
        case .restart: return Permission.controlRestart
        case .kill: return Permission.controlPower
        }
    }
}
