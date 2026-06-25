import Foundation

/// One entry from `GET /servers/:id/files/list` (agent `FileEntry`).
/// `modifiedAt` is decoded as a raw string (the agent's timestamp format isn't
/// guaranteed ISO-8601, and a strict Date decode would fail the whole list).
struct FileEntry: Codable, Identifiable, Equatable {
    let name: String
    let path: String
    let isDir: Bool
    let size: Int
    let mode: String?
    let modifiedAt: String?

    var id: String { path }

    /// Heuristic: treat well-known text/config extensions as editable.
    var isLikelyText: Bool {
        if isDir { return false }
        let lower = name.lowercased()
        let textExtensions = [
            ".txt", ".log", ".cfg", ".conf", ".config", ".ini", ".properties",
            ".yml", ".yaml", ".json", ".json5", ".toml", ".xml", ".html", ".md",
            ".sh", ".bash", ".env", ".lua", ".js", ".ts", ".py", ".rb", ".pl",
            ".sql", ".csv", ".gitignore", ".dockerfile", ".lang", ".mcmeta",
        ]
        if textExtensions.contains(where: { lower.hasSuffix($0) }) { return true }
        // Common extensionless config files.
        let bareNames = ["dockerfile", "makefile", "readme", "license", "eula.txt"]
        return bareNames.contains(lower)
    }

    var sizeDescription: String { Format.bytes(Double(size)) }
}

/// `GET /servers/:id/files/contents` → `{ content }`.
struct FileContent: Decodable {
    let content: String
}

/// `GET /servers/:id/files/download-url` → `{ url }` (signed, short-lived).
struct SignedURL: Decodable {
    let url: String
}
