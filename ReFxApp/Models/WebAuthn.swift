import Foundation

/// `POST /auth/mfa/webauthn/login/options` → @simplewebauthn
/// `generateAuthenticationOptions` result. We only need the challenge, rpId and
/// the allowed credential ids for the iOS assertion.
struct PasskeyOptions: Decodable {
    let challenge: String        // base64url
    let rpId: String
    let allowCredentials: [Credential]?
    let userVerification: String?

    struct Credential: Decodable { let id: String }   // base64url credentialId

    var challengeData: Data? { Base64URL.decode(challenge) }
    var allowedCredentialIDs: [Data] {
        (allowCredentials ?? []).compactMap { Base64URL.decode($0.id) }
    }
}

/// Standard WebAuthn `AuthenticationResponseJSON` the server verifies.
struct WebAuthnAssertionResponse: Encodable {
    let id: String
    let rawId: String
    let type = "public-key"
    let response: AssertionPayload
    let clientExtensionResults = ClientExtensionResults()

    struct AssertionPayload: Encodable {
        let clientDataJSON: String
        let authenticatorData: String
        let signature: String
        let userHandle: String?
    }
    struct ClientExtensionResults: Encodable {}

    init(credentialID: Data, clientDataJSON: Data, authenticatorData: Data,
         signature: Data, userID: Data?) {
        let credId = Base64URL.encode(credentialID)
        self.id = credId
        self.rawId = credId
        self.response = AssertionPayload(
            clientDataJSON: Base64URL.encode(clientDataJSON),
            authenticatorData: Base64URL.encode(authenticatorData),
            signature: Base64URL.encode(signature),
            userHandle: userID.map(Base64URL.encode))
    }
}

/// base64url (no padding) <-> Data, as WebAuthn uses throughout.
enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    static func decode(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }
}
