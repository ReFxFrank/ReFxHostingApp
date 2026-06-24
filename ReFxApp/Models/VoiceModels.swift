import Foundation

/// `GET /servers/:id/voice` — TeamSpeak server info + admin credentials.
struct VoiceInfo: Decodable, Equatable {
    let address: String?
    let voicePort: Int?
    let slots: Int?
    let ready: Bool
    let queryAdmin: String?
    let queryPassword: String?
    let privilegeKey: String?
    let licenseAccepted: Bool
}

/// `GET /servers/:id/voice/status` — live monitoring snapshot.
struct VoiceStatus: Decodable, Equatable {
    let ready: Bool
    let online: Int
    let maxClients: Int?
    let channelCount: Int
    let uptimeSeconds: Int
    let serverName: String?
    let avgPingMs: Double?
    let updatedSecondsAgo: Double?
}
