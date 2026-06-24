import Foundation

/// A Modrinth search hit (`GET /servers/:id/mods/search`).
struct ModSearchResult: Decodable, Identifiable, Equatable {
    let projectId: String
    let slug: String?
    let title: String
    let description: String?
    let author: String?
    let downloads: Int
    let iconUrl: String?
    let categories: [String]?

    var id: String { projectId }
    var downloadsDescription: String {
        if downloads >= 1_000_000 { return String(format: "%.1fM", Double(downloads) / 1_000_000) }
        if downloads >= 1_000 { return String(format: "%.0fK", Double(downloads) / 1_000) }
        return "\(downloads)"
    }
}

/// `GET /servers/:id/mods/context`.
struct ModContext: Decodable, Equatable {
    let loader: String?
    let kind: String?
    let gameVersion: String?
}

struct InstalledMod: Decodable, Identifiable, Equatable {
    let name: String
    let size: Int
    var id: String { name }
    var sizeDescription: String { Format.bytes(Double(size)) }
}

/// `GET /servers/:id/mods/installed` → `{ directory, files: [{name,size}] }`.
struct InstalledModsResponse: Decodable, Equatable {
    let directory: String?
    let files: [InstalledMod]
}
