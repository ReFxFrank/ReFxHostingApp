import SwiftUI

/// Second-factor step shown after a password login that returned `mfaRequired`.
/// Accepts a 6-digit TOTP code or a recovery code (toggle). WebAuthn/passkey
/// login is a Phase 3 stretch goal — the `methods` list is surfaced so a passkey
/// option can be added here later.
struct MFAView: View {
    let token: String
    let methods: [MFAMethod]

    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var useRecovery = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44)).foregroundStyle(.appPrimary)
                    Text(useRecovery ? "Enter a recovery code" : "Two-factor authentication")
                        .font(.title3.bold()).foregroundStyle(.appForeground)
                    Text(useRecovery
                         ? "Enter one of your saved recovery codes."
                         : "Enter the 6-digit code from your authenticator app.")
                        .font(.subheadline).foregroundStyle(.appMuted)
                        .multilineTextAlignment(.center)

                    LabeledField(title: useRecovery ? "Recovery code" : "Authentication code") {
                        TextField(useRecovery ? "xxxx-xxxx" : "123456", text: $code)
                            .keyboardType(useRecovery ? .default : .numberPad)
                            .textContentType(.oneTimeCode)
                            .autocorrectionDisabled()
                            .font(.title3.monospaced())
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.appDestructive)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView().tint(.white) }
                            Text("Verify")
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(.appPrimary)
                    .disabled(isSubmitting || code.isEmpty)

                    Button(useRecovery ? "Use authenticator code" : "Use a recovery code instead") {
                        useRecovery.toggle()
                        code = ""
                    }
                    .font(.footnote)
                }
                .padding(24)
                .frame(maxWidth: 440)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await session.completeMFA(
                token: token,
                code: code.trimmingCharacters(in: .whitespaces),
                method: useRecovery ? .recovery : .totp)
            dismiss()
        } catch let error as APIError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = "Verification failed. Try again."
        }
    }
}
