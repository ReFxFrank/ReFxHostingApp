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
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 56)
                brand
                form
                footer
            }
            .padding(24)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $model.mfaChallenge) { challenge in
            MFAView(token: challenge.token, methods: challenge.methods)
                .environmentObject(session)
        }
    }

    private var brand: some View {
        VStack(spacing: 12) {
            BrandMark(size: 84)
            VStack(spacing: 4) {
                Text("ReFx Hosting").font(.title.bold()).foregroundStyle(.appForegroundStrong)
                Eyebrow("Server Manager")
            }
        }
    }

    private var form: some View {
        VStack(spacing: 14) {
            LabeledField(title: "Email", focused: focus == .email) {
                TextField("you@example.com", text: $model.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }
            LabeledField(title: "Password", focused: focus == .password) {
                SecureField("••••••••", text: $model.password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await model.submit(session: session) } }
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.appDestructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                focus = nil
                Task { await model.submit(session: session) }
            } label: {
                HStack(spacing: 8) {
                    if model.isSubmitting { ProgressView().tint(.white) }
                    Text(model.isSubmitting ? "Signing in…" : "Sign in")
                }
            }
            .buttonStyle(.refxPrimary)
            .disabled(model.isSubmitting)
        }
        .padding(18)
        .cardSurface()
    }

    private var footer: some View {
        // Sign-up is web-only (no in-app account creation). On public App Store
        // builds in-app purchasing is disabled, so the footer drops the
        // "pay an invoice" call-to-action and offers account creation only.
        Button(FeatureFlags.purchasingEnabled
               ? "Create an account or pay an invoice on the web"
               : "Create an account on the web") {
            WebLink.open(config.webOrigin)
        }
        .font(.footnote.weight(.medium))
        .tint(.appAccentText)
    }
}

/// A titled field wrapper with the app's ReFx glass input styling. Pass
/// `focused` from a `@FocusState` to drive the blue focus accent.
struct LabeledField<Content: View>: View {
    let title: String
    var focused: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(title)
            content
                .foregroundStyle(.appForeground)
                .tint(.appPrimary)
                .refxField(focused: focused)
        }
    }
}
