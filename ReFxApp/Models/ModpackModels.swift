import Foundation

/// A Modrinth project version (`GET /servers/:id/modpacks/versions`).
struct ModpackVersion: Decodable, Identifiable, Equatable {
    let id: String
    let name: String?
    let versionNumber: String?
    let gameVersions: [String]?
    let loaders: [String]?
    let downloads: Int?

    var displayName: String { name ?? versionNumber ?? id }
    var subtitle: String {
        let mc = (gameVersions ?? []).first.map { "MC \($0)" } ?? ""
        let loader = (loaders ?? []).first?.capitalized ?? ""
        return [loader, mc].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// `GET /servers/:id/modpacks/installed` → `{ installed: InstalledModpack? }`.
struct InstalledModpackResponse: Decodable, Equatable {
    let installed: InstalledModpack?
}

struct InstalledModpack: Decodable, Equatable {
    let title: String?
    let versionNumber: String?
    let mcVersion: String?
    let loader: String?
    let filesInstalled: Int?
}
