import SwiftUI

/// Color-coded server state indicator — ReFx glassy status chip. One source of
/// truth for state→color so the list, detail header and widget all agree.
/// Uppercase, thin-bordered, softly tinted; running and transitional states
/// pulse a soft glow (honoring Reduce Motion).
struct StatePill: View {
    let state: ServerState
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.9), radius: glowing && pulse ? 5 : 1)
                .opacity(glowing && pulse ? 0.55 : 1)
            if !compact {
                Text(state.label.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
        .clipShape(Capsule())
        .onAppear {
            guard glowing, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel("Status: \(state.label)")
    }

    /// Running (live) and transitional states pulse.
    private var glowing: Bool {
        switch state {
        case .running, .starting, .stopping, .installing,
             .reinstalling, .switchingGame, .transferring: return true
        default: return false
        }
    }

    private var color: Color {
        switch state {
        case .running: return .appSuccess
        case .starting, .stopping, .installing, .reinstalling,
             .switchingGame, .transferring: return .appWarning
        case .offline: return .appMuted
        case .crashed, .suspended, .pendingPayment: return .appDestructive
        case .unknown: return .appMuted
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        StatePill(state: .running)
        StatePill(state: .starting)
        StatePill(state: .offline)
        StatePill(state: .crashed)
        StatePill(state: .suspended)
    }
    .padding()
    .background(Color.appBackground)
}
