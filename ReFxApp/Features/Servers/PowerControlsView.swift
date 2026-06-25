import SwiftUI
import UIKit

/// Start / Restart / Stop (+ Kill) — two taps from the home screen. Destructive
/// signals confirm first; all are debounced and disabled mid-transition. Power
/// gating is permissive (the API 403s defensively for restricted sub-users).
/// Actuation is confirmed with a haptic.
struct PowerControlsView: View {
    @ObservedObject var model: ServerDetailViewModel
    let state: ServerState

    @State private var confirm: PowerSignal?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                powerButton(.start, system: "play.fill", tint: .appSuccess,
                            disabled: state.isRunning)
                powerButton(.restart, system: "arrow.clockwise", tint: .appWarning,
                            disabled: !state.isRunning)
                powerButton(.stop, system: "stop.fill", tint: .appDestructive,
                            disabled: state == .offline)
            }
            Button {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                confirm = .kill
            } label: {
                Label("Force kill", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .foregroundStyle(.appDestructive.opacity(0.9))
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                .strokeBorder(Color.appDestructive.opacity(0.25), lineWidth: 1))
            .disabled(state == .offline || isBusy)
            .opacity(state == .offline || isBusy ? 0.4 : 1)
        }
        .padding(Theme.cardPadding)
        .cardSurface(glow: state.isRunning)
        .confirmationDialog(
            confirmTitle, isPresented: confirmBinding, titleVisibility: .visible) {
            if let confirm {
                Button(confirm.label, role: .destructive) {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    Task { await model.power(confirm) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var isBusy: Bool { model.powerInFlight != nil || state.isTransitional }

    @ViewBuilder
    private func powerButton(_ signal: PowerSignal, system: String,
                             tint: Color, disabled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
        Button {
            if signal.isDestructive {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                confirm = signal
            } else {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await model.power(signal) }
            }
        } label: {
            VStack(spacing: 7) {
                if model.powerInFlight == signal {
                    ProgressView().tint(tint)
                } else {
                    Image(systemName: system).font(.title3.weight(.semibold))
                }
                Text(signal.label).font(.caption2.weight(.bold)).tracking(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(tint)
            .background(shape.fill(tint.opacity(0.14)))
            .overlay(shape.fill(LinearGradient(
                colors: [Color.white.opacity(0.06), .clear], startPoint: .top, endPoint: .center)))
            .overlay(shape.strokeBorder(tint.opacity(disabled ? 0.15 : 0.40), lineWidth: 1))
            .clipShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(disabled || isBusy)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel("\(signal.label) server")
    }

    private var confirmBinding: Binding<Bool> {
        Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })
    }
    private var confirmTitle: String {
        confirm == .kill ? "Force kill server?" : "\(confirm?.label ?? "") server?"
    }
    private var confirmMessage: String {
        switch confirm {
        case .kill: return "This hard-stops the process immediately and may cause data loss."
        case .restart: return "The server will stop and start again."
        case .stop: return "Players will be disconnected."
        default: return ""
        }
    }
}
