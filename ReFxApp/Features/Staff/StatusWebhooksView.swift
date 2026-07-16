import SwiftUI

@MainActor
final class StatusWebhooksViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[StatusWebhook]> = .idle
    @Published var actionError: String?
    @Published var revealedSecret: String?
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.statusWebhooks()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func create(_ body: CreateWebhookBody) async -> Bool {
        guard let service else { return false }
        actionError = nil
        do {
            let created = try await service.createStatusWebhook(body)
            revealedSecret = created.secret
            await load()
            return true
        } catch let error as APIError { actionError = error.userMessage; return false }
        catch { actionError = "Couldn't create the webhook."; return false }
    }

    func toggleActive(_ hook: StatusWebhook) async {
        _ = await mutate { try await $0.updateStatusWebhook(hook.id, UpdateWebhookBody(isActive: !hook.isActive)) }
    }
    func delete(_ hook: StatusWebhook) async { _ = await mutate { try await $0.deleteStatusWebhook(hook.id) } }

    @discardableResult
    private func mutate(_ work: (StaffService) async throws -> Void) async -> Bool {
        guard let service else { return false }
        actionError = nil
        do { try await work(service); await load(); return true }
        catch let error as APIError { actionError = error.userMessage; return false }
        catch { actionError = "Action failed. Try again."; return false }
    }
}

struct StatusWebhooksView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = StatusWebhooksViewModel()
    @State private var showCreate = false

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No webhooks",
                emptyMessage: "Send status incident events to an external endpoint.",
                retry: { Task { await model.load() } },
                content: { list($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<2, id: \.self) { _ in SkeletonBlock(height: 80) } } })
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Webhooks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add webhook")
            }
        }
        .sheet(isPresented: $showCreate) {
            WebhookCreateSheet { await model.create($0) }
        }
        .alert("Signing secret", isPresented: Binding(
            get: { model.revealedSecret != nil }, set: { if !$0 { model.revealedSecret = nil } })) {
            Button("Copy") { if let s = model.revealedSecret { Clipboard.copySecret(s) } }
            Button("Done", role: .cancel) {}
        } message: {
            if let secret = model.revealedSecret {
                Text("\(secret)\n\nCopy it now — it's shown once and used to verify webhook signatures.")
            }
        }
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private func list(_ hooks: [StatusWebhook]) -> some View {
        VStack(spacing: 12) {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(hooks) { hook in
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(hook.description ?? hook.url).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground).lineLimit(1)
                            Spacer()
                            StatusChip(text: hook.isActive ? "Active" : "Off", color: hook.isActive ? .appSuccess : .appMuted)
                        }
                        Text(hook.url).font(.caption2.monospaced()).foregroundStyle(.appMuted).lineLimit(1)
                        if !hook.events.isEmpty {
                            Text(hook.events.joined(separator: ", ")).font(.caption2).foregroundStyle(.appMuted)
                        }
                        if let status = hook.lastStatus {
                            Text("Last delivery: HTTP \(status)").font(.caption2)
                                .foregroundStyle(status < 300 ? .appSuccess : .appDestructive)
                        }
                    }
                }
                .contextMenu {
                    Button { Task { await model.toggleActive(hook) } } label: {
                        Label(hook.isActive ? "Disable" : "Enable", systemImage: hook.isActive ? "pause" : "play")
                    }
                    Button(role: .destructive) { Task { await model.delete(hook) } } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }
}

private struct WebhookCreateSheet: View {
    let onCreate: (CreateWebhookBody) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var description = ""
    @State private var events: Set<String> = []
    @State private var isSaving = false

    private var canSave: Bool { !url.trimmed.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section("Endpoint") {
                    TextField("https://…", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Description (optional)", text: $description)
                }.listRowBackground(Color.appCard)
                Section {
                    ForEach(StatusWebhookEvent.allCases) { e in
                        Toggle(e.label, isOn: Binding(
                            get: { events.contains(e.rawValue) },
                            set: { on in if on { events.insert(e.rawValue) } else { events.remove(e.rawValue) } }))
                        .tint(.appPrimary)
                    }
                } header: { Text("Events") } footer: { Text("Leave all off to receive every event.") }
                .listRowBackground(Color.appCard)
                Section {
                    Button {
                        isSaving = true
                        Task {
                            let ok = await onCreate(CreateWebhookBody(
                                url: url.trimmed,
                                events: events.isEmpty ? nil : Array(events),
                                description: description.trimmed.isEmpty ? nil : description.trimmed))
                            isSaving = false
                            if ok { dismiss() }
                        }
                    } label: { HStack { if isSaving { ProgressView() }; Text("Create") } }
                    .buttonStyle(.refxPrimary).disabled(!canSave)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("New webhook").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
