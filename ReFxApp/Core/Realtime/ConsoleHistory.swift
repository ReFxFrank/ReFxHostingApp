import Foundation

/// In-memory, per-server console backlog that outlives a single
/// `ServerDetailViewModel` / `ConsoleSocket`.
///
/// The panel gateway sends **no history** when you subscribe — you only receive
/// lines produced after that moment. So when a customer leaves a server and comes
/// back, a fresh `ConsoleSocket` would otherwise start blank. This store lets the
/// new socket seed itself with what the previous session already captured, so the
/// console shows its history instead of an empty screen (mirroring the web panel's
/// client-side buffer).
///
/// All access is on the main thread (the socket's `handleQueue` is main and the
/// owning view-model is `@MainActor`), so a plain dictionary is safe without locks.
/// Lifetime is the app session; it is intentionally not persisted to disk (the
/// lines would be stale and it would leak potentially sensitive output).
final class ConsoleHistory {
    static let shared = ConsoleHistory()
    private init() {}

    private var buffers: [String: [ConsoleSocket.ConsoleLine]] = [:]
    /// Matches `ConsoleSocket.bufferLimit` so seeded history can't exceed the cap.
    private let limit = 2000

    func lines(for serverId: String) -> [ConsoleSocket.ConsoleLine] {
        buffers[serverId] ?? []
    }

    func store(_ lines: [ConsoleSocket.ConsoleLine], for serverId: String) {
        buffers[serverId] = lines.count > limit ? Array(lines.suffix(limit)) : lines
    }

    func clear(_ serverId: String) { buffers[serverId] = nil }
}
