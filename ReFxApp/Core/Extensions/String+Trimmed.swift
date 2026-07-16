import Foundation

extension String {
    /// Whitespace/newline-trimmed copy. App-wide helper used across forms.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
