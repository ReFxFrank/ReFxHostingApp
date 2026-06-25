import UIKit

/// Opens the web panel for the things the app deliberately doesn't do in-app —
/// signup, checkout, paying invoices (Decision #2: no IAP / no card entry).
enum WebLink {
    static func open(_ url: URL, path: String? = nil) {
        var target = url
        if let path { target = url.appendingPathComponent(path) }
        // Some targets are server-controlled (e.g. signed file-download URLs).
        // Only ever hand a web URL to the system opener so a malicious/compromised
        // backend can't make us launch another app via a custom scheme (tel:,
        // a deep link, etc.). http is allowed in DEBUG for local panels.
        guard let scheme = target.scheme?.lowercased() else { return }
        #if DEBUG
        let allowed: Set<String> = ["https", "http"]
        #else
        let allowed: Set<String> = ["https"]
        #endif
        guard allowed.contains(scheme) else { return }
        UIApplication.shared.open(target)
    }
}
