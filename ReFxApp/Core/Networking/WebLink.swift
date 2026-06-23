import UIKit

/// Opens the web panel for the things the app deliberately doesn't do in-app —
/// signup, checkout, paying invoices (Decision #2: no IAP / no card entry).
enum WebLink {
    static func open(_ url: URL, path: String? = nil) {
        var target = url
        if let path { target = url.appendingPathComponent(path) }
        UIApplication.shared.open(target)
    }
}
