import SwiftUI
import UIKit

/// Start / Restart / Stop (+ Kill) — two taps from the home screen. Destructive
/// signals confirm first; all are debounced and disabled mid-transition. Power
/// gating is permissive (the API 403s defensively for restricted sub-users).
struct PowerControlsView: View {
    @ObservedObject var model: ServerDetailViewModel
    let state: ServerState

    @State private var confirm: PowerSignal?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                powerButton(.start, system: "play.fill", tint: .appSuccess,
                            disabled: state.isRunning)
                powerButton(.restart, system: "arrow.clockwise", tint: .appWarning,
                            disabled: !state.isRunning)
                powerButton(.stop, system: "stop.fill", tint: .appDestructive,
                            disabled: state == .offline)
            }
            Button {
                confirm = .kill
            } label: {
                Label("Force kill", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.appMuted)
            .disabled(state == .offline || isBusy)
        }
        .padding(Theme.cardPadding)
        .cardSurface()
        .confirmationDialog(
            confirmTitle, isPresented: confirmBinding, titleVisibility: .visible) {
            if let confirm {
                Button(confirm.label, role: .destructive) {
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
        Button {
            if signal.isDestructive { confirm = signal }
            else { Task { await model.power(signal) } }
        } label: {
            VStack(spacing: 6) {
                if model.powerInFlight == signal {
                    ProgressView().tint(tint)
                } else {
                    Image(systemName: system).font(.title3)
                }
                Text(signal.label).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(disabled || isBusy)
        .opacity(disabled ? 0.45 : 1)
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
