import Foundation

/// `GET /servers/:id/switch-game/templates` — a game the server may switch to.
struct GameTemplate: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let slug: String?
    let author: String?
    let description: String?
}
