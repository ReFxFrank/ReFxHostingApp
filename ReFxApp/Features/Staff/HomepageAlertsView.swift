import SwiftUI

@MainActor
final class HomepageAlertsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[HomepageAlert]> = .idle
    @Published var actionError: String?
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.homepageAlerts()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func create(_ body: HomepageAlertBody) async -> Bool { await mutate { try await $0.createHomepageAlert(body) } }
    func update(_ id: String, _ body: HomepageAlertBody) async -> Bool { await mutate { try await $0.updateHomepageAlert(id, body) } }
    func delete(_ a: HomepageAlert) async { _ = await mutate { try await $0.deleteHomepageAlert(a.id) } }

    @discardableResult
    private func mutate(_ work: (StaffService) async throws -> Void) async -> Bool {
        guard let service else { return false }
        actionError = nil
        do { try await work(service); await load(); return true }
        catch let error as APIError { actionError = error.userMessage; return false }
        catch { actionError = "Action failed. Try again."; return false }
    }
}

struct HomepageAlertsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = HomepageAlertsViewModel()
    @State private var showCreate = false
    @State private var editing: HomepageAlert?

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No homepage alerts",
                emptyMessage: "Post a banner on the public storefront homepage.",
                retry: { Task { await model.load() } },
                content: { list($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 84) } } })
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Homepage alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add alert")
            }
        }
        .sheet(isPresented: $showCreate) {
            HomepageAlertEditSheet(title: "New alert") { await model.create($0) }
        }
        .sheet(item: $editing) { a in
            HomepageAlertEditSheet(title: "Edit alert", alert: a) { await model.update(a.id, $0) }
        }
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private func list(_ alerts: [HomepageAlert]) -> some View {
        VStack(spacing: 12) {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(alerts) { a in
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            StatusChip(text: a.type.label, color: a.type.color)
                            if !a.isActive { StatusChip(text: "Inactive", color: .appMuted) }
                            Spacer()
                            Text("priority \(a.priority)").font(.caption2).foregroundStyle(.appMuted)
                        }
                        Text(a.title).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                        Text(a.body).font(.caption).foregroundStyle(.appMuted).lineLimit(2)
                    }
                }
                .contextMenu {
                    Button { editing = a } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { Task { await model.delete(a) } } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }
}

private struct HomepageAlertEditSheet: View {
    let title: String
    var alert: HomepageAlert?
    let onSave: (HomepageAlertBody) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var type: HomepageAlertType = .info
    @State private var alertTitle = ""
    @State private var messageBody = ""
    @State private var ctaLabel = ""
    @State private var ctaUrl = ""
    @State private var priority = "0"
    @State private var isActive = true
    @State private var dismissible = true
    @State private var isSaving = false

    private var canSave: Bool { !alertTitle.trimmed.isEmpty && !messageBody.trimmed.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(HomepageAlertType.allCases.filter { $0 != .unknown }) { Text($0.label).tag($0) }
                    }
                    TextField("Title", text: $alertTitle)
                    TextField("Body", text: $messageBody, axis: .vertical).lineLimit(2...6)
                }.listRowBackground(Color.appCard)
                Section("Call to action (optional)") {
                    TextField("Button label", text: $ctaLabel)
                    TextField("Button URL", text: $ctaUrl)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }.listRowBackground(Color.appCard)
                Section {
                    TextField("Priority (higher first)", text: $priority).keyboardType(.numberPad)
                    Toggle("Active", isOn: $isActive).tint(.appPrimary)
                    Toggle("Dismissible", isOn: $dismissible).tint(.appPrimary)
                }.listRowBackground(Color.appCard)
                Section {
                    Button {
                        isSaving = true
                        Task {
                            let ok = await onSave(HomepageAlertBody(
                                type: type.rawValue, title: alertTitle.trimmed, body: messageBody.trimmed,
                                isActive: isActive,
                                ctaLabel: ctaLabel.trimmed.isEmpty ? nil : ctaLabel.trimmed,
                                ctaUrl: ctaUrl.trimmed.isEmpty ? nil : ctaUrl.trimmed,
                                dismissible: dismissible, priority: Int(priority) ?? 0))
                            isSaving = false
                            if ok { dismiss() }
                        }
                    } label: { HStack { if isSaving { ProgressView() }; Text("Save") } }
                    .buttonStyle(.refxPrimary).disabled(!canSave)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                if let alert {
                    type = alert.type == .unknown ? .info : alert.type
                    alertTitle = alert.title; messageBody = alert.body
                    ctaLabel = alert.ctaLabel ?? ""; ctaUrl = alert.ctaUrl ?? ""
                    priority = String(alert.priority); isActive = alert.isActive; dismissible = alert.dismissible
                }
            }
        }
    }
}
