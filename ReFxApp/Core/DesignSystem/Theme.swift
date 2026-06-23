import SwiftUI

/// Color tokens mirrored from the web panel's dark theme
/// (`apps/web` CSS variables). The panel ships HSL tokens, so we build `Color`
/// from HSL directly to match the palette exactly. Primary brand = #0072FF.
///
/// Tokens live on `ShapeStyle where Self == Color` so the leading-dot shorthand
/// works in SwiftUI style contexts (`.foregroundStyle(.appMuted)`,
/// `.tint(.appPrimary)`, `.fill(.appCard)`) AND they remain reachable as
/// `Color.appBackground` for `View`/background uses.
extension Color {
    /// Build a Color from HSL degrees/percent (SwiftUI's initializer is HSB).
    init(h: Double, s: Double, l: Double, opacity: Double = 1) {
        let hue = h / 360
        let sat = s / 100
        let light = l / 100
        let c = (1 - abs(2 * light - 1)) * sat
        let x = c * (1 - abs((hue * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = light - c / 2
        let (r, g, b): (Double, Double, Double)
        switch hue * 6 {
        case 0..<1: (r, g, b) = (c, x, 0)
        case 1..<2: (r, g, b) = (x, c, 0)
        case 2..<3: (r, g, b) = (0, c, x)
        case 3..<4: (r, g, b) = (0, x, c)
        case 4..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        self.init(.sRGB, red: r + m, green: g + m, blue: b + m, opacity: opacity)
    }
}

extension ShapeStyle where Self == Color {
    // Dark-theme tokens (apps/web globals.css `.dark`).
    static var appBackground: Color { Color(h: 218, s: 47, l: 5) }
    static var appCard: Color { Color(h: 217, s: 47, l: 11) }          // #101a2b
    static var appCardElevated: Color { Color(h: 217, s: 44, l: 14) }
    static var appPopover: Color { Color(h: 217, s: 49, l: 9) }
    static var appForeground: Color { Color(h: 213, s: 100, l: 97) }
    static var appMuted: Color { Color(h: 213, s: 45, l: 72) }         // muted-foreground
    static var appBorder: Color { Color(h: 217, s: 40, l: 20) }
    static var appPrimary: Color { Color(h: 213, s: 100, l: 50) }      // #0072ff
    static var appAccent: Color { Color(h: 215, s: 40, l: 17) }
    static var appSuccess: Color { Color(h: 152, s: 58, l: 45) }
    static var appWarning: Color { Color(h: 38, s: 92, l: 52) }
    static var appDestructive: Color { Color(h: 0, s: 72, l: 55) }
}

enum Theme {
    static let cornerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let spacing: CGFloat = 12
}

/// shadcn-style card surface: muted fill, subtle border, rounded corners.
struct CardBackground: ViewModifier {
    var elevated = false
    func body(content: Content) -> some View {
        content
            .background(elevated ? Color.appCardElevated : Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Color.appBorder, lineWidth: 1))
    }
}

extension View {
    func cardSurface(elevated: Bool = false) -> some View {
        modifier(CardBackground(elevated: elevated))
    }
}
