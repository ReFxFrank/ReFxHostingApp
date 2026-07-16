import Foundation

/// Runtime configuration: API + Web base URLs. Seeded from the build-time
/// `.xcconfig` values baked into Info.plist, overridable at runtime from the
/// Settings screen (persisted in UserDefaults — these are non-secret origins,
/// never tokens or PII).
final class AppConfig: ObservableObject {
    static let shared = AppConfig()

    private enum Keys {
        static let apiOriginOverride = "refx.apiOriginOverride"
        static let webOriginOverride = "refx.webOriginOverride"
    }

    private let defaults: UserDefaults

    @Published private(set) var apiOrigin: URL
    @Published private(set) var webOrigin: URL

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Fallbacks are the LIVE platform so the app works out of the box even
        // if the .xcconfig -> Info.plist substitution doesn't reach the bundle
        // (it isn't reliable across Xcode/XcodeGen versions). Settings override
        // still wins; the Info.plist values, when present, win over these.
        self.apiOrigin = AppConfig.resolve(
            override: defaults.string(forKey: Keys.apiOriginOverride),
            schemeKey: "ReFxAPIScheme", hostKey: "ReFxAPIHost",
            fallback: "https://api.refx.gg")
        self.webOrigin = AppConfig.resolve(
            override: defaults.string(forKey: Keys.webOriginOverride),
            schemeKey: "ReFxWebScheme", hostKey: "ReFxWebHost",
            fallback: "https://refx.gg")
    }

    /// Base for all REST calls, e.g. `https://panel.refxhosting.com/api/v1`.
    var apiBaseURL: URL { apiOrigin.appendingPathComponent("api/v1") }

    /// Socket.IO origin (the namespace path `/ws/console` is added by the client).
    var socketOrigin: URL { apiOrigin }

    func setAPIOrigin(_ string: String) {
        guard let url = AppConfig.normalize(string) else { return }
        defaults.set(url.absoluteString, forKey: Keys.apiOriginOverride)
        apiOrigin = url
    }

    func setWebOrigin(_ string: String) {
        guard let url = AppConfig.normalize(string) else { return }
        defaults.set(url.absoluteString, forKey: Keys.webOriginOverride)
        webOrigin = url
    }

    func resetToDefaults() {
        defaults.removeObject(forKey: Keys.apiOriginOverride)
        defaults.removeObject(forKey: Keys.webOriginOverride)
        apiOrigin = AppConfig.resolve(
            override: nil, schemeKey: "ReFxAPIScheme", hostKey: "ReFxAPIHost",
            fallback: "https://panel.refxhosting.com")
        webOrigin = AppConfig.resolve(
            override: nil, schemeKey: "ReFxWebScheme", hostKey: "ReFxWebHost",
            fallback: "https://refxhosting.com")
    }

    // MARK: - Resolution

    private static func resolve(override: String?, schemeKey: String,
                                hostKey: String, fallback: String) -> URL {
        // Honor a persisted origin override in DEBUG only. There is no in-app UI
        // to set it in release, so reading it in production would only serve as a
        // redirect vector: anyone able to write the app's sandboxed UserDefaults
        // (jailbreak / manipulated backup restore) could point all token-bearing
        // API + socket traffic at an attacker host. Release always uses the
        // baked-in Info.plist origin (or the hardcoded fallback).
        #if DEBUG
        if let override, let url = normalize(override) { return url }
        #endif
        let info = Bundle.main.infoDictionary
        let scheme = (info?[schemeKey] as? String)?.trimmed ?? "https"
        let host = (info?[hostKey] as? String)?.trimmed ?? ""
        // Ignore empty or unexpanded ("$(API_HOST)") Info.plist values and use
        // the live-platform fallback instead of a broken URL.
        let usable = !host.isEmpty && !host.contains("$(") && !scheme.contains("$(")
        if usable, let url = URL(string: "\(scheme)://\(host)"), url.host != nil {
            return url
        }
        return URL(string: fallback)!
    }

    /// Accept bare hosts ("panel.refxhosting.com"), schemed URLs, and trailing
    /// slashes; default to https when no scheme is given.
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmed
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }
}
