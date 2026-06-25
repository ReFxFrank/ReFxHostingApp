import Foundation

/// `POST /auth/login` and `/auth/mfa/verify` and `/auth/refresh` all return this
/// `TokenResponseDto`. On a login that still needs a second factor, the tokens
/// are empty and `mfaRequired` / `mfaToken` / `methods` are populated instead.
struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let mfaRequired: Bool?
    let mfaToken: String?
    let methods: [MFAMethod]?

    var requiresMFA: Bool { mfaRequired == true && !(mfaToken ?? "").isEmpty }
}

enum MFAMethod: String, Decodable {
    case totp, recovery, webauthn, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MFAMethod(rawValue: raw) ?? .unknown
    }
}

// MARK: - Request bodies

struct LoginRequest: Encodable {
    let email: String
    let password: String
    var totp: String?
    var rememberMe: Bool?
}

struct MFAVerifyRequest: Encodable {
    let mfaToken: String
    let code: String
    let method: String // "totp" | "recovery"
}

struct RefreshRequest: Encodable {
    let refreshToken: String
}

/// Decoded (not verified) JWT access-token claims, used only to seed routing
/// before `/auth/me` confirms. The server remains the source of truth.
struct AccessTokenClaims {
    let subject: String
    let email: String?
    let role: UserRole
    let expiresAt: Date?

    init?(jwt: String) {
        let segments = jwt.split(separator: ".")
        guard segments.count == 3,
              let payload = AccessTokenClaims.base64URLDecode(String(segments[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return nil }
        guard let sub = json["sub"] as? String else { return nil }
        subject = sub
        email = json["email"] as? String
        role = UserRole(rawValue: (json["role"] as? String) ?? "") ?? .unknown
        if let exp = json["exp"] as? TimeInterval {
            expiresAt = Date(timeIntervalSince1970: exp)
        } else { expiresAt = nil }
    }

    private static func base64URLDecode(_ s: String) -> Data? {
        var str = s.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while str.count % 4 != 0 { str.append("=") }
        return Data(base64Encoded: str)
    }
}
