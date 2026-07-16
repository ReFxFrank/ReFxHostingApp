import SwiftUI

@MainActor
final class StatusIncidentsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[StatusIncident]> = .idle
    @Published var actionError: String?
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.incidents()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func create(_ body: CreateIncidentBody) async -> Bool { await mutate { try await $0.createIncident(body) } }
    func addUpdate(_ id: String, status: IncidentStatus, body: String) async -> Bool {
        await mutate { try await $0.addIncidentUpdate(id, .init(status: status.rawValue, body: body)) }
    }
    func delete(_ incident: StatusIncident) async { _ = await mutate { try await $0.deleteIncident(incident.id) } }

    @discardableResult
    private func mutate(_ work: (StaffService) async throws -> Void) async -> Bool {
        guard let service else { return false }
        actionError = nil
        do { try await work(service); await load(); return true }
        catch let error as APIError { actionError = error.userMessage; return false }
        catch { actionError = "Action failed. Try again."; return false }
    }
}

struct StatusIncidentsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = StatusIncidentsViewModel()
    @State private var showCreate = false
    @State private var detail: StatusIncident?

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No incidents",
                emptyMessage: "Publish a status incident to keep customers informed.",
                retry: { Task { await model.load() } },
                content: { list($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 90) } } })
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Status incidents")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showCreate = true } label: { Label("New incident", systemImage: "plus") }
                    NavigationLink { StatusWebhooksView() } label: { Label("Webhooks", systemImage: "bolt.horizontal") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showCreate) {
            IncidentCreateSheet { await model.create($0) }
        }
        .sheet(item: $detail) { incident in
            IncidentDetailSheet(incident: incident,
                                onAddUpdate: { status, body in await model.addUpdate(incident.id, status: status, body: body) },
                                onDelete: { Task { await model.delete(incident); detail = nil } })
        }
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private func list(_ incidents: [StatusIncident]) -> some View {
        VStack(spacing: 12) {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(incidents) { incident in
                Button { detail = incident } label: { IncidentCard(incident: incident) }.buttonStyle(.plain)
            }
        }
    }
}

private struct IncidentCard: View {
    let incident: StatusIncident
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    StatusChip(text: incident.status.label, color: incident.status.color)
                    StatusChip(text: incident.impact.label, color: incident.impact.color)
                    Spacer()
                    if let started = incident.startedAt {
                        Text(started.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.appMuted)
                    }
                }
                Text(incident.title).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                if !incident.components.isEmpty {
                    Text(incident.components.joined(separator: " · ")).font(.caption2).foregroundStyle(.appMuted)
                }
            }
        }
    }
}

private struct IncidentCreateSheet: View {
    let onCreate: (CreateIncidentBody) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var impact: IncidentImpact = .degraded
    @State private var status: IncidentStatus = .investigating
    @State private var components: Set<String> = []
    @State private var messageBody = ""
    @State private var notify = false
    @State private var isSaving = false

    private var canSave: Bool { !title.trimmed.isEmpty && !messageBody.trimmed.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Picker("Impact", selection: $impact) {
                        ForEach(IncidentImpact.allCases.filter { $0 != .unknown }) { Text($0.label).tag($0) }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(IncidentStatus.allCases.filter { $0 != .unknown }) { Text($0.label).tag($0) }
                    }
                }.listRowBackground(Color.appCard)
                Section("Components") {
                    ForEach(IncidentComponent.allCases) { c in
                        Toggle(c.label, isOn: Binding(
                            get: { components.contains(c.rawValue) },
                            set: { on in if on { components.insert(c.rawValue) } else { components.remove(c.rawValue) } }))
                        .tint(.appPrimary)
                    }
                }.listRowBackground(Color.appCard)
                Section("First update") {
                    TextField("What's happening?", text: $messageBody, axis: .vertical).lineLimit(2...6)
                    Toggle("Notify customers", isOn: $notify).tint(.appPrimary)
                }.listRowBackground(Color.appCard)
                Section {
                    Button {
                        isSaving = true
                        Task {
                            let ok = await onCreate(CreateIncidentBody(
                                title: title.trimmed, impact: impact.rawValue,
                                components: Array(components), body: messageBody.trimmed,
                                status: status.rawValue, notify: notify))
                            isSaving = false
                            if ok { dismiss() }
                        }
                    } label: { HStack { if isSaving { ProgressView() }; Text("Publish") } }
                    .buttonStyle(.refxPrimary).disabled(!canSave)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("New incident").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct IncidentDetailSheet: View {
    let incident: StatusIncident
    let onAddUpdate: (IncidentStatus, String) async -> Bool
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var status: IncidentStatus = .monitoring
    @State private var messageBody = ""
    @State private var isPosting = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { StatusChip(text: incident.status.label, color: incident.status.color)
                                StatusChip(text: incident.impact.label, color: incident.impact.color) }
                            Text(incident.title).font(.headline).foregroundStyle(.appForeground)
                        }
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Timeline", systemImage: "clock")
                            ForEach(incident.updates ?? []) { u in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack { StatusChip(text: u.status.label, color: u.status.color)
                                        Spacer()
                                        Text(u.createdAt.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.appMuted) }
                                    Text(u.body).font(.caption).foregroundStyle(.appMuted)
                                }
                                Divider()
                            }
                        }
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Post update", systemImage: "plus.bubble")
                            Picker("Status", selection: $status) {
                                ForEach(IncidentStatus.allCases.filter { $0 != .unknown }) { Text($0.label).tag($0) }
                            }
                            TextField("Update message", text: $messageBody, axis: .vertical).lineLimit(2...5)
                            Button { Task { let ok = await onAddUpdate(status, messageBody.trimmed); if ok { messageBody = "" } } } label: {
                                HStack { if isPosting { ProgressView() }; Text("Post update") }
                            }
                            .buttonStyle(.refxSecondary).disabled(messageBody.trimmed.isEmpty)
                        }
                    }
                    Button("Delete incident", role: .destructive) { confirmDelete = true }
                        .buttonStyle(.refxDestructive)
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Incident").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete this incident?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
