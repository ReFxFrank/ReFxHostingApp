import Foundation

/// A game name that may arrive as a bare string or a nested `{ name / slug }`
/// object — decodes tolerantly to whichever is present.
private struct FlexibleGameName: Decodable {
    let value: String?
    init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            value = s
            return
        }
        if let c = try? decoder.container(keyedBy: Keys.self) {
            value = (try? c.decode(String.self, forKey: .name))
                ?? (try? c.decode(String.self, forKey: .slug))
        } else {
            value = nil
        }
    }
    private enum Keys: String, CodingKey { case name, slug }
}

/// `GET /servers/:id/game-history` — one past game switch.
///
/// The exact server DTO isn't pinned, so this decodes tolerantly: it accepts the
/// common field spellings for the previous/next game and the timestamp, and
/// treats every field as optional so an unexpected shape degrades gracefully
/// (renders what it can) rather than failing the whole list.
struct GameHistoryEntry: Decodable, Identifiable, Equatable {
    let id: String
    let fromGame: String?
    let toGame: String?
    let at: Date?

    private enum CodingKeys: String, CodingKey {
        case id, uuid
        case from, fromTemplate, fromGame, previousGame, previousTemplate
        case to, toTemplate, toGame, newGame, game, template
        case at, createdAt, switchedAt, timestamp, changedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        func name(_ keys: [CodingKeys]) -> String? {
            for k in keys {
                if let flex = try? c.decode(FlexibleGameName.self, forKey: k), let v = flex.value {
                    return v
                }
            }
            return nil
        }
        func date(_ keys: [CodingKeys]) -> Date? {
            for k in keys {
                if let d = try? c.decode(Date.self, forKey: k) { return d }
            }
            return nil
        }

        fromGame = name([.from, .fromTemplate, .fromGame, .previousGame, .previousTemplate])
        toGame = name([.to, .toTemplate, .toGame, .newGame, .game, .template])
        at = date([.at, .createdAt, .switchedAt, .timestamp, .changedAt])

        let explicitID = (try? c.decode(String.self, forKey: .id))
            ?? (try? c.decode(String.self, forKey: .uuid))
        // Stable synthetic id when the row carries none, so SwiftUI diffing works.
        id = explicitID
            ?? "\(fromGame ?? "?")→\(toGame ?? "?")@\(at?.timeIntervalSince1970.rounded() ?? 0)"
    }
}
