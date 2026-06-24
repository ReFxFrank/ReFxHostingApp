import Foundation

/// `GET /servers/:id/startup` → `{ startupCommand, dockerImage }`.
struct StartupConfig: Codable, Equatable {
    let startupCommand: String?
    let dockerImage: String?
}

/// `GET /servers/:id/variables` → `ServerVariable[]` ({ id, envName, value }).
struct ServerVariable: Codable, Identifiable, Equatable {
    let id: String
    let envName: String
    let value: String
}
