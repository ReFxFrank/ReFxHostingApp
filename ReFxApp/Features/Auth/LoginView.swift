import SwiftUI

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var mfaChallenge: MFAChallenge?

    struct MFAChallenge: Identifiable, Equatable {
        let id = UUID()
        let token: String
        let methods: [MFAMethod]
    }

    func submit(session: AppSession) async {
        errorMessage = nil
        guard email.contains("@"), !password.isEmpty else {
            errorMessage = "Enter your email and password."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let outcome = try await session.login(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password, totp: nil, rememberMe: true)
            switch outcome {
            case .signedIn:
                break // RootView reacts to phase change.
            case .mfaRequired(let token, let methods):
                mfaChallenge = MFAChallenge(token: token, methods: methods)
            }
        } catch let error as APIError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = "Couldn't sign in. Try again."
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var config: AppConfig
    @StateObject private var model = LoginViewModel()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 60)
                    brand
                    form
                    footer
                }
                .padding(24)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showSettings) {
            ConnectionSettingsView().environmentObject(config)
        }
        .sheet(item: $model.mfaChallenge) { challenge in
            MFAView(token: challenge.token, methods: challenge.methods)
                .environmentObject(session)
        }
    }

    private var brand: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 52)).foregroundStyle(.appPrimary)
            Text("ReFx Hosting").font(.title.bold()).foregroundStyle(.appForeground)
            Text("Server manager").font(.subheadline).foregroundStyle(.appMuted)
        }
    }

    private var form: some View {
        VStack(spacing: 14) {
            LabeledField(title: "Email") {
                TextField("you@example.com", text: $model.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            LabeledField(title: "Password") {
                SecureField("••••••••", text: $model.password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit { Task { await model.submit(session: session) } }
            }
            if let error = model.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.appDestructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Task { await model.submit(session: session) }
            } label: {
                HStack {
                    if model.isSubmitting { ProgressView().tint(.white) }
                    Text(model.isSubmitting ? "Signing in…" : "Sign in")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.appPrimary)
            .disabled(model.isSubmitting)
        }
        .padding(20)
        .cardSurface()
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button("Create an account or pay an invoice on the web") {
                WebLink.open(config.webOrigin)
            }
            .font(.footnote)

            Button {
                showSettings = true
            } label: {
                Label("Connection settings", systemImage: "gearshape")
                    .font(.footnote)
            }
            .foregroundStyle(.appMuted)
        }
    }
}

/// A titled field wrapper with the app's input styling.
struct LabeledField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.appMuted)
            content
                .padding(12)
                .background(Color.appBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.appBorder))
                .foregroundStyle(.appForeground)
        }
    }
}
