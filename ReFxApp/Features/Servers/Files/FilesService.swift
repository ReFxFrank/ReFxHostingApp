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

    /// Compress files/folders into an archive; returns the new archive's path.
    /// `POST files/compress { paths: [String] } → { path }`.
    @discardableResult
    func compress(_ serverId: String, paths: [String]) async throws -> String {
        let result: PathResult = try await client.send(
            .post("servers/\(serverId)/files/compress", body: PathsBody(paths: paths)))
        return result.path
    }

    /// Extract an archive in place. `POST files/decompress { path } → void`.
    func decompress(_ serverId: String, path: String) async throws {
        try await client.sendVoid(
            .post("servers/\(serverId)/files/decompress", body: PathBody(path: path)))
    }

    /// The server's direct-upload cap; larger files must go over SFTP.
    static let maxUploadBytes = 32 * 1024 * 1024

    /// Upload raw bytes to `destination` (absolute path incl. filename). The whole
    /// request body is the file's bytes (`POST files/upload?path=…`, ≤ 32 MiB).
    @discardableResult
    func upload(_ serverId: String, to destination: String, data: Data) async throws -> UploadResult {
        guard !data.isEmpty else { throw APIError.validation(["The file is empty."]) }
        guard data.count <= FilesService.maxUploadBytes else {
            throw APIError.validation(["File is over the 32 MiB upload limit — use SFTP for larger files."])
        }
        return try await client.send(.upload(
            "servers/\(serverId)/files/upload",
            query: [URLQueryItem(name: "path", value: destination)],
            data: data))
    }

    /// SFTP connection details (never a password). `GET servers/:id/sftp`.
    func sftpDetails(_ serverId: String) async throws -> SftpDetails {
        try await client.send(.get("servers/\(serverId)/sftp"))
    }

    /// Rotate the SFTP password and return the new one (shown once).
    /// `POST servers/:id/sftp/rotate → { password }`.
    func rotateSftpPassword(_ serverId: String) async throws -> String {
        let result: SftpPassword = try await client.send(.post("servers/\(serverId)/sftp/rotate"))
        return result.password
    }

    private struct WriteBody: Encodable { let path: String; let content: String }
    private struct PathResult: Decodable { let path: String }
    private struct SftpPassword: Decodable { let password: String }
    private struct PathBody: Encodable { let path: String }
    private struct RenameBody: Encodable { let from: String; let to: String }
    private struct PathsBody: Encodable { let paths: [String] }
}

struct UploadResult: Decodable { let status: String; let path: String; let bytes: Int }

struct SftpDetails: Decodable, Equatable {
    let host: String
    let port: Int
    let username: String
}
