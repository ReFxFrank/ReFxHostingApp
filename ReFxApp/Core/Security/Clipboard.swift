import UIKit
import UniformTypeIdentifiers

/// Clipboard helpers. Secrets (API keys, DB passwords, TOTP setup keys) must NOT
/// go on the system-wide pasteboard as a plain string: that value is readable by
/// any other app while it sits there, is mirrored to the user's other Apple
/// devices via Universal Clipboard, and never expires. `copySecret` keeps the
/// value device-local (off Handoff/Universal Clipboard) and auto-purges it.
enum Clipboard {
    /// Copy a secret value, kept local-only and auto-expiring after `ttl` seconds.
    static func copySecret(_ value: String, ttl: TimeInterval = 60) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: value]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(ttl),
            ])
    }
}
