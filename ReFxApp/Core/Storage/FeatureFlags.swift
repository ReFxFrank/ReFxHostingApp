import Foundation

/// Runtime feature gates.
enum FeatureFlags {
    /// In-app purchasing (the new-server checkout / "Place order" flow).
    ///
    /// Game-server hosting is a service consumed *outside* the app, so charging
    /// by card is permitted by App Store Review Guideline 3.1.3(e) and must NOT
    /// use Apple IAP. To stay clear of reviewer subjectivity on public builds,
    /// the in-app buy UI is auto-enabled on dev & TestFlight and auto-disabled
    /// on public App Store builds (where purchasing stays on the web). Flip
    /// `productionOverride` to deliberately enable it for the public App Store.
    static let productionOverride = false

    static var purchasingEnabled: Bool {
        #if DEBUG
        return true
        #else
        if productionOverride { return true }
        // TestFlight receipts are named "sandboxReceipt"; the public App Store
        // production receipt is "receipt" (or absent before first launch).
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
