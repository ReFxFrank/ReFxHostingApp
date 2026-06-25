import Foundation
import LocalAuthentication

/// Optional Face ID / Touch ID gate on cold start and foreground. This is a
/// *local* gate only — tokens are already persisted in Keychain; locking just
/// hides content behind biometrics. Toggle persisted in UserDefaults (non-secret).
final class AppLock {
    private enum Keys { static let enabled = "refx.appLock.enabled" }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) }
        set { defaults.set(newValue, forKey: Keys.enabled) }
    }

    /// True if the device can actually evaluate biometrics (else enabling the
    /// lock would soft-brick the app).
    var isBiometryAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    @MainActor
    func authenticate(reason: String = "Unlock ReFx") async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        // Allow passcode fallback so a user without working biometrics isn't
        // permanently locked out.
        let policy: LAPolicy = .deviceOwnerAuthentication
        // Fail CLOSED: if neither biometrics nor passcode can be evaluated we
        // cannot prove user presence, so stay locked rather than unlocking. The
        // lock screen always offers "Sign out", so this can't permanently brick
        // access. (Previously returned true, which unlocked on evaluation failure.)
        guard context.canEvaluatePolicy(policy, error: nil) else { return false }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
