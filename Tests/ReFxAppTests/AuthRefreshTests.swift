import XCTest
@testable import ReFxApp

/// Exercises the auth/refresh state machine — the part the spec calls out for
/// unit testing. The single-flight guarantee matters because refresh ROTATES:
/// two concurrent refreshes would reuse a token and revoke the session family.
final class AuthRefreshTests: XCTestCase {

    func testLoginPersistsTokens() async throws {
        let api = MockAuthAPI()
        let store = InMemoryTokenStore()
        let auth = AuthStore(api: api, keychain: store)

        let outcome = try await auth.login(
            email: "user@example.com", password: "pw", totp: nil, rememberMe: true)

        XCTAssertEqual(outcome, .signedIn)
        let access = await auth.currentAccessToken()
        XCTAssertEqual(access, "login-access-1")
        XCTAssertEqual(store.get(.refreshToken), "login-refresh-1")
    }

    func testLoginReturnsMFAChallengeWithoutPersistingTokens() async throws {
        let api = MockAuthAPI()
        let store = InMemoryTokenStore()
        let auth = AuthStore(api: api, keychain: store)

        let outcome = try await auth.login(
            email: "user@example.com", password: "needs-mfa", totp: nil, rememberMe: false)

        guard case .mfaRequired(let token, let methods) = outcome else {
            return XCTFail("Expected MFA challenge")
        }
        XCTAssertEqual(token, "challenge-123")
        XCTAssertEqual(methods, [.totp])
        let access = await auth.currentAccessToken()
        XCTAssertNil(access, "Tokens must not be stored until MFA completes")
    }

    func testConcurrent401sTriggerExactlyOneRefresh() async throws {
        let api = MockAuthAPI()
        let store = InMemoryTokenStore(access: "old-access", refresh: "old-refresh")
        let auth = AuthStore(api: api, keychain: store)

        // Fire 20 concurrent refresh requests, as 20 in-flight 401s would.
        let results = await withTaskGroup(of: Bool.self) { group -> [Bool] in
            for _ in 0..<20 { group.addTask { await auth.refreshIfPossible() } }
            var out: [Bool] = []
            for await r in group { out.append(r) }
            return out
        }

        XCTAssertTrue(results.allSatisfy { $0 }, "All callers should observe success")
        let count = await api.refreshCallCount
        XCTAssertEqual(count, 1, "Single-flight: exactly one refresh call")

        let access = await auth.currentAccessToken()
        XCTAssertEqual(access, "refreshed-access-1", "Rotated token is applied")
    }

    func testRefreshFailureClearsSession() async throws {
        let api = MockAuthAPI()
        await api.configure(refreshShouldFail: true)
        let store = InMemoryTokenStore(access: "old-access", refresh: "old-refresh")
        let auth = AuthStore(api: api, keychain: store)

        let ok = await auth.refreshIfPossible()

        XCTAssertFalse(ok)
        let hasSession = await auth.hasSession
        XCTAssertFalse(hasSession, "A failed refresh must clear the session")
        XCTAssertNil(store.get(.refreshToken))
    }

    func testRefreshWithNoTokenReturnsFalse() async {
        let api = MockAuthAPI()
        let auth = AuthStore(api: api, keychain: InMemoryTokenStore())

        let ok = await auth.refreshIfPossible()

        XCTAssertFalse(ok)
        let count = await api.refreshCallCount
        XCTAssertEqual(count, 0, "No refresh attempt without a refresh token")
    }

    func testSequentialRefreshesEachRotate() async throws {
        let api = MockAuthAPI()
        let store = InMemoryTokenStore(access: "a0", refresh: "r0")
        let auth = AuthStore(api: api, keychain: store)

        _ = await auth.refreshIfPossible()
        let first = await auth.currentAccessToken()
        _ = await auth.refreshIfPossible()
        let second = await auth.currentAccessToken()

        XCTAssertNotEqual(first, second, "Each completed refresh rotates the token")
        let count = await api.refreshCallCount
        XCTAssertEqual(count, 2)
    }
}
