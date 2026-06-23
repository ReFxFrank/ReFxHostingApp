import SwiftUI

/// Color-coded server state indicator. One source of truth for state→color so
/// the list, detail header and widget all agree.
struct StatePill: View {
    let state: ServerState
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.7), radius: pulsing ? 4 : 0)
            if !compact {
                Text(state.label)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 6 : 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
        .accessibilityLabel("Status: \(state.label)")
    }

    private var pulsing: Bool { state == .running }

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
