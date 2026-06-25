import SwiftUI

// MARK: - ReFx button styles
//
// Premium glass/hardware controls — never stock iOS. Use `.refxPrimary` for the
// single main action on a screen (power Start, Save), `.refxSecondary` for
// understated actions, `.refxDestructive` for Kill/Stop. All keep a ≥44pt hit
// area and confirm with a subtle press-in lift; pair actuation with haptics at
// the call site for power actions.

struct ReFxPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
        return configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 30)
            .padding(.vertical, 11).padding(.horizontal, 18)
            .background {
                shape.fill(Theme.primaryGradient)
                    .overlay(shape.fill(LinearGradient(
                        colors: [Color.white.opacity(0.22), .clear],
                        startPoint: .top, endPoint: .center)).blendMode(.plusLighter))
            }
            .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: Color.appPrimary.opacity(isEnabled ? 0.45 : 0), radius: 12, x: 0, y: 6)
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

struct ReFxSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
        return configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.appForeground)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 30)
            .padding(.vertical, 11).padding(.horizontal, 18)
            .background(shape.fill(Color.appCard))
            .overlay(shape.fill(Theme.glassOverlay).clipShape(shape))
            .overlay(shape.strokeBorder(configuration.isPressed ? Color.appBorderBlue : Color.appBorder, lineWidth: 1))
            .clipShape(shape)
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

struct ReFxDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
        return configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.appDestructive)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 30)
            .padding(.vertical, 11).padding(.horizontal, 18)
            .background(shape.fill(Color.appDestructive.opacity(0.14)))
            .overlay(shape.strokeBorder(Color.appDestructive.opacity(configuration.isPressed ? 0.6 : 0.35), lineWidth: 1))
            .clipShape(shape)
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == ReFxPrimaryButtonStyle {
    static var refxPrimary: ReFxPrimaryButtonStyle { .init() }
    static func refxPrimary(fullWidth: Bool) -> ReFxPrimaryButtonStyle { .init(fullWidth: fullWidth) }
}
extension ButtonStyle where Self == ReFxSecondaryButtonStyle {
    static var refxSecondary: ReFxSecondaryButtonStyle { .init() }
    static func refxSecondary(fullWidth: Bool) -> ReFxSecondaryButtonStyle { .init(fullWidth: fullWidth) }
}
extension ButtonStyle where Self == ReFxDestructiveButtonStyle {
    static var refxDestructive: ReFxDestructiveButtonStyle { .init() }
    static func refxDestructive(fullWidth: Bool) -> ReFxDestructiveButtonStyle { .init(fullWidth: fullWidth) }
}

// MARK: - Eyebrow & section header

/// Uppercase, high-tracking, muted-blue label used above sections and values.
struct Eyebrow: View {
    let text: String
    var systemImage: String?
    init(_ text: String, systemImage: String? = nil) { self.text = text; self.systemImage = systemImage }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .semibold)) }
            Text(text.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.4)
        }
        .foregroundStyle(Color.appLabel)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Section header: eyebrow on the left, optional trailing accessory.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, systemImage: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow(title, systemImage: systemImage)
            Spacer(minLength: 8)
            trailing
        }
    }
}

// MARK: - Glassy field

/// Inset dark-glass field chrome with a blue focus accent. Drive `focused`
/// from a `@FocusState` at the call site for the accent to react.
struct ReFxFieldBackground: ViewModifier {
    var focused = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
        content
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(shape.fill(Color.appPopover))
            .overlay(shape.strokeBorder(focused ? Color.appPrimary.opacity(0.7) : Color.appBorder, lineWidth: 1))
            .clipShape(shape)
            .shadow(color: focused ? Color.appPrimary.opacity(0.25) : .clear, radius: 8)
            .animation(.smooth(duration: 0.18), value: focused)
    }
}

extension View {
    func refxField(focused: Bool = false) -> some View { modifier(ReFxFieldBackground(focused: focused)) }
}
