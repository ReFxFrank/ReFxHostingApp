import Foundation

/// The auth network surface `AuthStore` depends on. A protocol so the
/// auth/refresh state machine can be unit-tested against a mock that simulates
/// rotation, MFA challenges and refresh failures without a live server.
protocol AuthAPI: Sendable {
    func login(_ request: LoginRequest) async throws -> TokenResponse
    func verifyMFA(_ request: MFAVerifyRequest) async throws -> TokenResponse
    func refresh(refreshToken: String) async throws -> TokenResponse
    func logout(refreshToken: String) async throws
    func me() async throws -> CurrentUser
    func webauthnLoginOptions(mfaToken: String) async throws -> PasskeyOptions
    func webauthnLoginVerify(mfaToken: String, response: WebAuthnAssertionResponse) async throws -> TokenResponse
}

/// Concrete `AuthAPI` over `APIClient`. All these routes are `@Public()` except
/// `me`, so the token endpoints never trigger the 401→refresh interceptor.
struct AuthService: AuthAPI {
    let client: APIClient

    func login(_ request: LoginRequest) async throws -> TokenResponse {
        try await client.send(.post("auth/login", body: request, authenticated: false))
    }

    func verifyMFA(_ request: MFAVerifyRequest) async throws -> TokenResponse {
        try await client.send(.post("auth/mfa/verify", body: request, authenticated: false))
    }

    func refresh(refreshToken: String) async throws -> TokenResponse {
        try await client.send(
            .post("auth/refresh", body: RefreshRequest(refreshToken: refreshToken),
                  authenticated: false))
    }

    func logout(refreshToken: String) async throws {
        try await client.sendVoid(
            .post("auth/logout", body: RefreshRequest(refreshToken: refreshToken),
                  authenticated: false))
    }

    func me() async throws -> CurrentUser {
        try await client.send(.get("auth/me"))
    }

    func webauthnLoginOptions(mfaToken: String) async throws -> PasskeyOptions {
        try await client.send(.post("auth/mfa/webauthn/login/options",
                                     body: MFATokenBody(mfaToken: mfaToken), authenticated: false))
    }

    func webauthnLoginVerify(mfaToken: String, response: WebAuthnAssertionResponse) async throws -> TokenResponse {
        try await client.send(.post("auth/mfa/webauthn/login/verify",
                                     body: WebAuthnLoginVerifyBody(mfaToken: mfaToken, response: response),
                                     authenticated: false))
    }
}

private struct MFATokenBody: Encodable { let mfaToken: String }
private struct WebAuthnLoginVerifyBody: Encodable {
    let mfaToken: String
    let response: WebAuthnAssertionResponse
}
