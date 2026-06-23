import SwiftUI

struct ChangePasswordView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        Form {
            Section {
                SecureField("Current password", text: $current).textContentType(.password)
            }
            Section {
                SecureField("New password", text: $new).textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirm).textContentType(.newPassword)
            } footer: {
                Text("10–128 characters with a lowercase, uppercase, number and symbol.")
            }
            if let message {
                Text(message).foregroundStyle(isError ? .appDestructive : .appSuccess)
            }
            Section {
                Button { Task { await submit() } } label: {
                    HStack {
                        if isSubmitting { ProgressView() }
                        Text("Update password")
                    }
                }
                .disabled(!isValid || isSubmitting)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Change password")
    }

    private var isValid: Bool {
        !current.isEmpty && new.count >= 10 && new == confirm
    }

    private func submit() async {
        message = nil
        guard new == confirm else { isError = true; message = "Passwords don't match."; return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await session.account.changePassword(current: current, new: new)
            isError = false
            message = "Password updated."
            current = ""; new = ""; confirm = ""
        } catch let error as APIError {
            isError = true
            message = error.userMessage
        } catch {
            isError = true
            message = "Couldn't update password."
        }
    }
}
