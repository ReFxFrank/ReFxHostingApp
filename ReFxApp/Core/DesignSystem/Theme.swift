import SwiftUI

// MARK: - ReFx Glassy Design — color tokens
//
// A premium dark, tactical, blue control-surface palette. Values come straight
// from the ReFx brand spec (hex + rgba). Tokens live on
// `ShapeStyle where Self == Color` so the leading-dot shorthand works in style
// contexts (`.foregroundStyle(.appMuted)`, `.tint(.appPrimary)`) AND they stay
// reachable as `Color.appBackground` for `View`/background uses.
//
// Never scatter raw hex across views — add a token here and reference it.

extension Color {
    /// Build a Color from a 6- or 8-digit hex string (#RRGGBB / #RRGGBBAA).
    init(hex: String, opacity: Double? = nil) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 6 { s += "FF" }
        let v = UInt64(s, radix: 16) ?? 0xFFFF_FFFF
        let r = Double((v & 0xFF00_0000) >> 24) / 255
        let g = Double((v & 0x00FF_0000) >> 16) / 255
        let b = Double((v & 0x0000_FF00) >> 8) / 255
        let a = Double(v & 0x0000_00FF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity ?? a)
    }
}

extension ShapeStyle where Self == Color {
    // Dark bases (deepest → panel)
    static var appBackground: Color { Color(hex: "0a111d") }     // screen base
    static var appBackgroundDeep: Color { Color(hex: "070b12") } // gradient floor
    static var appPanel: Color { Color(hex: "0f1828") }          // glass card base
    static var appCard: Color { Color(hex: "101a2b") }           // elevated base
    static var appCardElevated: Color { Color(hex: "13203a") }
    static var appPopover: Color { Color(hex: "0c1422") }

    // Brand + accents (brand stays ReFx blue everywhere)
    static var appPrimary: Color { Color(hex: "0072ff") }
    static var appPrimaryDeep: Color { Color(hex: "0052cc") }
    static var appSecondary: Color { Color(hex: "58a7d3") }
    static var appAccent: Color { Color(hex: "13203a") }

    // Text
    static var appForeground: Color { Color(hex: "eef6ff") }       // bright text
    static var appForegroundStrong: Color { Color(hex: "f3f8ff") }
    static var appAccentText: Color { Color(hex: "7db7ff") }       // light accent
    static var appHighlight: Color { Color(hex: "9dccff") }        // pale highlight
    static var appTextSecondary: Color { Color(red: 216/255, green: 234/255, blue: 1, opacity: 0.72) }
    static var appMuted: Color { Color(red: 188/255, green: 216/255, blue: 1, opacity: 0.56) }
    static var appLabel: Color { Color(red: 140/255, green: 196/255, blue: 1, opacity: 0.70) }

    // Hairline borders (blue-tinted glass edges)
    static var appBorder: Color { Color.white.opacity(0.08) }
    static var appBorderSoft: Color { Color.white.opacity(0.05) }
    static var appBorderBlue: Color { Color(red: 0, green: 114/255, blue: 1, opacity: 0.22) }

    // Semantic status (status only — never the app's brand color)
    static var appSuccess: Color { Color(hex: "3fb9a6") }     // desaturated teal-green
    static var appWarning: Color { Color(hex: "f5a623") }     // amber
    static var appDestructive: Color { Color(hex: "e5565b") } // warning red
}

// MARK: - Gradients & shared geometry

enum Theme {
    static let cornerRadius: CGFloat = 16
    static let cornerRadiusSmall: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let spacing: CGFloat = 12
    static let screenMargin: CGFloat = 16

    /// Deep navy screen backdrop.
    static var screenGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "0a111d"), Color(hex: "070b12")],
            startPoint: .top, endPoint: .bottom)
    }

    /// Faint white inner-glass overlay laid over a dark panel base.
    static var glassOverlay: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.05), Color.white.opacity(0.012)],
            startPoint: .top, endPoint: .bottom)
    }

    /// Hairline border that catches light at the top edge and fades to blue.
    static var borderGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.14), Color.white.opacity(0.04),
                     Color(red: 0, green: 114/255, blue: 1, opacity: 0.10)],
            startPoint: .top, endPoint: .bottom)
    }

    /// Blue glass fill for primary controls.
    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "1a86ff"), Color(hex: "0059d6")],
            startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Glass surfaces
//
// Gradient-based (no blur) so it stays cheap on scrolling lists/console. Static
// chrome can layer Material separately. Honors Reduce Transparency by falling
// back to a solid navy fill.

struct GlassSurface: ViewModifier {
    var radius: CGFloat = Theme.cornerRadius
    var elevated = false
    /// Active state (running server, focused field) adds a soft blue glow.
    var glow = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    shape.fill(elevated ? Color.appCard : Color.appPanel)
                } else {
                    shape
                        .fill(elevated ? Color.appCard : Color.appPanel)
                        .overlay(shape.fill(Theme.glassOverlay))
                        .overlay(alignment: .top) {
                            shape
                                .fill(LinearGradient(
                                    colors: [Color.white.opacity(0.10), .clear],
                                    startPoint: .top, endPoint: .center))
                                .blendMode(.plusLighter)
                                .opacity(0.6)
                        }
                }
            }
            .overlay(shape.strokeBorder(
                reduceTransparency ? AnyShapeStyle(Color.appBorder) : AnyShapeStyle(Theme.borderGradient),
                lineWidth: 1))
            .clipShape(shape)
            .shadow(color: .black.opacity(reduceTransparency ? 0 : 0.45), radius: 14, x: 0, y: 8)
            .overlay {
                if glow && !reduceTransparency {
                    shape.strokeBorder(Color.appPrimary.opacity(0.35), lineWidth: 1)
                        .shadow(color: Color.appPrimary.opacity(0.35), radius: 10)
                }
            }
    }
}

extension View {
    /// Primary glass card/panel surface.
    func cardSurface(elevated: Bool = false, glow: Bool = false) -> some View {
        modifier(GlassSurface(elevated: elevated, glow: glow))
    }

    /// Smaller-radius glass (chips, inset rows).
    func glassInset(glow: Bool = false) -> some View {
        modifier(GlassSurface(radius: Theme.cornerRadiusSmall, glow: glow))
    }
}

// MARK: - Screen background

struct ScreenBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.background {
            ZStack {
                Theme.screenGradient
                if !reduceTransparency {
                    // faint blue accent glow, top-trailing — depth only
                    RadialGradient(
                        colors: [Color.appPrimary.opacity(0.16), .clear],
                        center: .init(x: 0.85, y: 0.05), startRadius: 0, endRadius: 420)
                    .blendMode(.plusLighter)
                }
            }
            .ignoresSafeArea()
        }
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}

// MARK: - Readable content width (iPad)

/// Constrains content to a comfortable reading column and centers it. On iPhone
/// the screen is narrower than `maxWidth`, so this is a no-op; on iPad (and other
/// regular-width contexts) it stops content from stretching edge-to-edge.
struct ReadableWidth: ViewModifier {
    var maxWidth: CGFloat = 720
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)   // center the capped column in the full width
    }
}

extension View {
    func readableWidth(_ maxWidth: CGFloat = 720) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }
}
