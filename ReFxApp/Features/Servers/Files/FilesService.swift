import Foundation

/// REST surface for the file manager. Confirmed against `files.controller.ts`:
/// list/contents/download are GET with a `path` query; mutations are POST with
/// the documented body shapes. Permissions: files.read / files.write /
/// files.delete (the API 403s defensively regardless of what the UI shows).
struct FilesService {
    let client: APIClient

    func list(_ serverId: String, path: String) async throws -> [FileEntry] {
        try await client.send(.get("servers/\(serverId)/files/list",
                                    query: [URLQueryItem(name: "path", value: path)]))
    }

    func read(_ serverId: String, path: String) async throws -> String {
        let result: FileContent = try await client.send(
            .get("servers/\(serverId)/files/contents",
                 query: [URLQueryItem(name: "path", value: path)]))
        return result.content
    }

    func write(_ serverId: String, path: String, content: String) async throws {
        try await client.sendVoid(
            .post("servers/\(serverId)/files/write",
                  body: WriteBody(path: path, content: content)))
    }

    func mkdir(_ serverId: String, path: String) async throws {
        try await client.sendVoid(
            .post("servers/\(serverId)/files/mkdir", body: PathBody(path: path)))
    }

    func rename(_ serverId: String, from: String, to: String) async throws {
        try await client.sendVoid(
            .post("servers/\(serverId)/files/rename", body: RenameBody(from: from, to: to)))
    }

    func delete(_ serverId: String, paths: [String]) async throws {
        try await client.sendVoid(
            .post("servers/\(serverId)/files/delete", body: PathsBody(paths: paths)))
    }

    func downloadURL(_ serverId: String, path: String) async throws -> URL? {
        let signed: SignedURL = try await client.send(
            .get("servers/\(serverId)/files/download-url",
                 query: [URLQueryItem(name: "path", value: path)]))
        return URL(string: signed.url)
    }

    private struct WriteBody: Encodable { let path: String; let content: String }
    private struct PathBody: Encodable { let path: String }
    private struct RenameBody: Encodable { let from: String; let to: String }
    private struct PathsBody: Encodable { let paths: [String] }
}
