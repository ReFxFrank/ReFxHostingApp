import SwiftUI

/// The ReFx brand mark — the official app-icon "R" presented in a rounded tile
/// with a hairline edge and a soft blue glow.
///
/// This is the single source of truth for the in-app logo. It replaced the old
/// `bolt.horizontal.circle.fill` SF Symbol, which read as the Facebook Messenger
/// glyph. Render this anywhere a brand mark is needed (login, privacy curtain)
/// so the logo can never drift from the app icon again.
struct BrandMark: View {
    var size: CGFloat = 84

    /// iOS app-icon "squircle" proportion, so the tile echoes the home-screen icon.
    private var cornerRadius: CGFloat { size * 0.225 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    var body: some View {
        Image("ReFxLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.borderGradient, lineWidth: 1))
            .shadow(color: Color.appPrimary.opacity(0.35), radius: size * 0.14, x: 0, y: 4)
            .accessibilityLabel("ReFx")
    }
}
