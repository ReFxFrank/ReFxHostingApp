import SwiftUI

/// SFTP connection details for a server. The panel never returns the existing
/// password (stored encrypted) — it's rotate-to-reveal: rotating generates a new
/// password shown exactly once. Auth is password-only (no SSH keys).
struct SftpDetailsView: View {
    let serverId: String
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var details: LoadState<SftpDetails> = .idle
    @State private var password: String?
    @State private var rotating = false
    @State private var errorMessage: String?
    @State private var confirmRotate = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AsyncStateView(
                        state: details,
                        isEmpty: { _ in false },
                        emptyTitle: "Unavailable",
                        retry: { Task { await load() } },
                        content: { detailCard($0) },
                        skeleton: { SkeletonBlock(height: 150) })
                    passwordCard
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.appDestructive)
                    }
                    Text("Connect with any SFTP client (FileZilla, Cyberduck, WinSCP…). Authentication is password-only — there are no SSH keys.")
                        .font(.caption).foregroundStyle(.appMuted)
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("SFTP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { if details.value == nil { await load() } }
        }
    }

    private func detailCard(_ d: SftpDetails) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Connection", systemImage: "network")
                CopyChip(label: "Host", value: d.host)
                CopyChip(label: "Port", value: "\(d.port)")
                CopyChip(label: "Username", value: d.username)
            }
        }
    }

    @ViewBuilder private var passwordCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Password", systemImage: "key")
                if let password {
                    CopyChip(label: "Password", value: password)
                    Text("Copy it now — for security it isn't shown again. Rotating replaces it.")
                        .font(.caption2).foregroundStyle(.appWarning)
                } else {
                    Text("The password is stored encrypted and can't be shown. Reset it to reveal a new one (this changes your SFTP password immediately).")
                        .font(.caption).foregroundStyle(.appMuted)
                }
                Button {
                    confirmRotate = true
                } label: {
                    HStack { if rotating { ProgressView() }
                        Text(password == nil ? "Reveal a new password" : "Rotate password") }
                }
                .buttonStyle(.refxSecondary).disabled(rotating)
            }
        }
        .confirmationDialog("Reset SFTP password?", isPresented: $confirmRotate, titleVisibility: .visible) {
            Button("Reset password") { Task { await rotate() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This generates a new password and immediately replaces the old one. Any saved SFTP logins will need updating.")
        }
    }

    private func load() async {
        details = .loading
        do { details = .loaded(try await session.files.sftpDetails(serverId)) }
        catch let e as APIError { details = .failed(e) }
        catch { details = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    private func rotate() async {
        rotating = true; errorMessage = nil
        defer { rotating = false }
        do {
            password = try await session.files.rotateSftpPassword(serverId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch let e as APIError { errorMessage = e.userMessage }
        catch { errorMessage = "Couldn't rotate the password. Try again." }
    }
}
