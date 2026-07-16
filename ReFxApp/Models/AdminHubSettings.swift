import Foundation

/// `GET/PATCH /admin/settings/vanity` — custom-address settings (no secrets).
struct VanitySettings: Decodable, Equatable {
    let enabled: Bool
    let feeMinor: Int
    let reservedWords: [String]
}
struct SetVanitySettingsBody: Encodable {
    var enabled: Bool?
    var feeMinor: Int?
    var reservedWords: [String]?
}

/// `GET/PATCH /admin/settings/referrals`.
struct ReferralSettings: Decodable, Equatable {
    let enabled: Bool
    let rewardMinor: Int
}
struct SetReferralSettingsBody: Encodable {
    var enabled: Bool?
    var rewardMinor: Int?
}

/// `GET/PATCH /admin/settings/express-backups`.
struct ExpressBackupSettings: Decodable, Equatable {
    let enabled: Bool
    let monthlyMinor: Int
}
struct SetExpressBackupSettingsBody: Encodable {
    var enabled: Bool?
    var monthlyMinor: Int?
}

/// `GET /admin/settings/backup-storage` — S3/R2 (secrets are boolean flags).
struct BackupStorageConfigMasked: Decodable, Equatable {
    let configured: Bool
    let endpoint: String
    let region: String
    let bucket: String
    let accessKeySet: Bool
    let secretKeySet: Bool
    let usePathStyle: Bool
}
/// `PATCH /admin/settings/backup-storage`. `bucket:""` clears the whole config;
/// `accessKey`/`secretKey` are kept if omitted or empty.
struct SetBackupStorageBody: Encodable {
    var endpoint: String?
    var region: String?
    var bucket: String?
    var accessKey: String?
    var secretKey: String?
    var usePathStyle: Bool?
}
