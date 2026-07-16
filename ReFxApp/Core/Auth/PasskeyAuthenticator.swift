import Foundation
import AuthenticationServices
import UIKit

/// Drives a passkey (WebAuthn) assertion via `AuthenticationServices`. The OS
/// shows the system passkey sheet; the result is serialized into the standard
/// WebAuthn response the panel verifies.
///
/// Requires the app's Associated Domains entitlement (`webcredentials:<rpId>`)
/// AND the RP to host `/.well-known/apple-app-site-association` — see the
/// passkey section of the README. Without those the OS rejects the assertion.
@MainActor
final class PasskeyAuthenticator: NSObject {
    struct Assertion {
        let credentialID: Data
        let clientDataJSON: Data
        let authenticatorData: Data
        let signature: Data
        let userID: Data?
    }

    struct Registration {
        let credentialID: Data
        let clientDataJSON: Data
        let attestationObject: Data
    }

    enum PasskeyError: Error { case cancelled, failed(String) }

    private var assertionContinuation: CheckedContinuation<Assertion, Error>?
    private var registrationContinuation: CheckedContinuation<Registration, Error>?

    func assert(rpId: String, challenge: Data, allowedCredentialIDs: [Data]) async throws -> Assertion {
        #if DEBUG
        // The rpId MUST match the app's `webcredentials:` Associated Domain
        // (and the domain that hosts apple-app-site-association). A mismatch here
        // is the usual cause of a passkey that "works on web but not in the app".
        print("🔑 Passkey assert — rpId=\(rpId), challenge=\(challenge.count)B, allowedCreds=\(allowedCredentialIDs.count)")
        #endif
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        if !allowedCredentialIDs.isEmpty {
            request.allowedCredentials = allowedCredentialIDs.map {
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
            }
        }
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.assertionContinuation = continuation
            controller.performRequests()
        }
    }

    /// Register a new platform passkey. The OS creates the credential in iCloud
    /// Keychain and returns the attestation the panel verifies. `rpId` MUST match
    /// the app's `webcredentials:` Associated Domain.
    func register(rpId: String, userName: String, userID: Data, challenge: Data) async throws -> Registration {
        #if DEBUG
        print("🔑 Passkey register — rpId=\(rpId), user=\(userName), userID=\(userID.count)B, challenge=\(challenge.count)B")
        #endif
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge, name: userName, userID: userID)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.registrationContinuation = continuation
            controller.performRequests()
        }
    }
}

extension PasskeyAuthenticator: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential
            as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            defer { registrationContinuation = nil }
            registrationContinuation?.resume(returning: Registration(
                credentialID: credential.credentialID,
                clientDataJSON: credential.rawClientDataJSON,
                attestationObject: credential.rawAttestationObject ?? Data()))
            return
        }
        defer { assertionContinuation = nil }
        guard let credential = authorization.credential
            as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            assertionContinuation?.resume(throwing: PasskeyError.failed("Unexpected credential type"))
            return
        }
        assertionContinuation?.resume(returning: Assertion(
            credentialID: credential.credentialID,
            clientDataJSON: credential.rawClientDataJSON,
            authenticatorData: credential.rawAuthenticatorData,
            signature: credential.signature,
            userID: credential.userID))
    }

    func authorizationController(controller: ASAuthorizationController,
                                didCompleteWithError error: Error) {
        let ns = error as NSError
        #if DEBUG
        print("🔑 Passkey error — domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription)\n   userInfo=\(ns.userInfo)")
        #endif
        let resolved: Error
        if let asError = error as? ASAuthorizationError, asError.code == .canceled {
            resolved = PasskeyError.cancelled
        } else {
            // Include domain+code so the surfaced message is actionable
            // (e.g. ASAuthorizationError 1004 = no credential / not associated).
            resolved = PasskeyError.failed("\(ns.localizedDescription) (\(ns.domain) \(ns.code))")
        }
        // Only one continuation is ever pending at a time.
        registrationContinuation?.resume(throwing: resolved); registrationContinuation = nil
        assertionContinuation?.resume(throwing: resolved); assertionContinuation = nil
    }
}

extension PasskeyAuthenticator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let window = scenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }
}
