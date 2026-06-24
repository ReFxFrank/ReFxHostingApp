import Foundation

/// `GET /servers/:id/workshop`.
struct WorkshopMod: Codable, Identifiable, Equatable {
    let id: String
    let workshopId: String
    let name: String?
    let kind: String?
    let enabled: Bool
    let sortOrder: Int?

    var displayName: String { name ?? "Item \(workshopId)" }
}
