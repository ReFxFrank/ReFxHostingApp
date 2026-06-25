import SwiftUI
import UIKit

@MainActor
final class PlatformAlertsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[PlatformAlert]> = .idle
    @Published var actionError: String?
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.alerts()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func refresh() async { await load() }

    func create(severity: AlertSeverity, title: String, body: String) async -> Bool {
        guard let service else { return false }
        actionError = nil
        do { try await service.createAlert(severity: severity, title: title, body: body); await load(); return true }
        catch let error as APIError { actionError = error.userMessage; return false }
        catch { actionError = "Couldn't post the alert."; return false }
    }

    func setActive(_ alert: PlatformAlert, isActive: Bool) async {
        await run { try await $0.setAlertActive(alert.id, isActive: isActive) }
    }

    func delete(_ alert: PlatformAlert) async {
        await run { try await $0.deleteAlert(alert.id) }
    }

    private func run(_ work: (StaffService) async throws -> Void) async {
        guard let service else { return }
        actionError = nil
        do { try await work(service); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Action failed. Try again." }
    }
}

/// Manage platform-wide dashboard banners (GlobalAlert) — post, toggle, delete.
struct PlatformAlertsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = PlatformAlertsViewModel()
    @State private var showCompose = false

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No alerts",
                emptyMessage: "Post a platform-wide banner that customers see on their dashboard.",
                retry: { Task { await model.load() } },
                content: { list($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 96) } } })
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Platform alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCompose = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCompose) {
            ComposeAlertSheet { severity, title, body in await model.create(severity: severity, title: title, body: body) }
        }
        .refreshable { await model.refresh() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private func list(_ alerts: [PlatformAlert]) -> some View {
        VStack(spacing: 12) {
            if let actionError = model.actionError {
                Text(actionError).font(.footnote).foregroundStyle(.appDestructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(alerts) { alert in
                AlertCard(
                    alert: alert,
                    onToggle: { isActive in Task { await model.setActive(alert, isActive: isActive) } },
                    onDelete: { Task { await model.delete(alert) } })
            }
        }
    }
}

private struct AlertCard: View {
    let alert: PlatformAlert
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    @State private var confirmDelete = false
    private var severity: AlertSeverity { alert.severity ?? .info }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: severity.systemImage).foregroundStyle(severity.color)
                    Text(alert.title).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(get: { alert.isActive }, set: { onToggle($0) }))
                        .labelsHidden().tint(.appPrimary)
                        .accessibilityLabel("Alert active")
                }
                Text(alert.body).font(.caption).foregroundStyle(.appMuted).lineLimit(3)
                HStack(spacing: 8) {
                    StatusChip(text: severity.label, color: severity.color)
                    if !alert.isActive { StatusChip(text: "Inactive", color: .appMuted) }
                    Spacer()
                    if let created = alert.createdAt {
                        Text(created.formatted(.relative(presentation: .named)))
                            .font(.caption2).foregroundStyle(.appMuted)
                    }
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                confirmDelete = true
            } label: { Label("Delete", systemImage: "trash") }
        }
        .confirmationDialog("Delete this alert?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct ComposeAlertSheet: View {
    /// Returns true on success so the sheet can dismiss.
    let onPost: (AlertSeverity, String, String) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var severity: AlertSeverity = .info
    @State private var title = ""
    @State private var message = ""
    @State private var isPosting = false

    private var canPost: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !message.trimmingCharacters(in: .whitespaces).isEmpty && !isPosting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Severity", selection: $severity) {
                        ForEach([AlertSeverity.info, .warning, .critical], id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    TextField("Title", text: $title)
                    TextField("Message", text: $message, axis: .vertical).lineLimit(3...6)
                } header: {
                    Text("New platform alert")
                } footer: {
                    Text("Shown as a banner on every customer dashboard while active.")
                }
                .listRowBackground(Color.appCard)

                Section {
                    Button {
                        isPosting = true
                        Task {
                            let ok = await onPost(severity, title.trimmingCharacters(in: .whitespaces),
                                                  message.trimmingCharacters(in: .whitespaces))
                            isPosting = false
                            if ok { dismiss() }
                        }
                    } label: {
                        HStack { if isPosting { ProgressView() }; Text("Post alert") }
                    }
                    .buttonStyle(.refxPrimary)
                    .disabled(!canPost)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("New alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
