import SwiftUI

/// Edit the signed-in user's profile (`PATCH /account`). Only the name is
/// editable from the app for now; email/role are managed server-side.
struct EditProfileView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var saving = false
    @State private var errorText: String?
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("First name", text: $firstName)
                    .textContentType(.givenName)
                TextField("Last name", text: $lastName)
                    .textContentType(.familyName)
            } header: {
                Text("Name")
            } footer: {
                Text("This is how you appear across ReFx. Your email and role are managed by support.")
            }
            .listRowBackground(Color.appCard)

            if let email = session.currentUser?.email {
                Section("Email") {
                    Text(email).foregroundStyle(.appMuted)
                }
                .listRowBackground(Color.appCard)
            }

            if let errorText {
                Section {
                    Text(errorText).font(.footnote).foregroundStyle(.appDestructive)
                }
                .listRowBackground(Color.appCard)
            }
        }
        .scrollContentBackground(.hidden).screenBackground()
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(saving || !hasChanges)
            }
        }
        .overlay { if saving { ProgressView().tint(.appPrimary) } }
        .task {
            guard !loaded else { return }
            loaded = true
            firstName = session.currentUser?.firstName ?? ""
            lastName = session.currentUser?.lastName ?? ""
        }
    }

    private var hasChanges: Bool {
        firstName.trimmingCharacters(in: .whitespaces) != (session.currentUser?.firstName ?? "") ||
        lastName.trimmingCharacters(in: .whitespaces) != (session.currentUser?.lastName ?? "")
    }

    private func save() async {
        saving = true; errorText = nil
        defer { saving = false }
        do {
            _ = try await session.account.updateProfile(
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces))
            await session.reloadUser()
            dismiss()
        } catch let error as APIError { errorText = error.userMessage }
        catch { errorText = "Couldn't save your profile. Try again." }
    }
}
