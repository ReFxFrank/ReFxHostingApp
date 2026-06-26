import SwiftUI
import UIKit

// MARK: - View model

@MainActor
final class AdminCreateServerViewModel: ObservableObject {
    // Loaded options
    @Published var templates: [AdminGameTemplate] = []
    @Published var nodes: [NodeAdmin] = []
    @Published var optionsState: LoadState<Bool> = .idle

    // Selection
    @Published var owner: AdminUser?
    @Published var nodeId: String?
    @Published var templateId: String? { didSet { if templateId != oldValue { onTemplateChange() } } }
    @Published var name = ""
    @Published var sizeBySlots = false
    @Published var slots = 16
    @Published var cpuText = ""
    @Published var memoryText = ""
    @Published var diskText = ""
    @Published var env: [String: String] = [:]

    @Published var submitting = false
    @Published var message: String?
    @Published var createdServerId: String?

    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    var selectedTemplate: AdminGameTemplate? { templates.first { $0.id == templateId } }
    var editableVariables: [TemplateVariable] {
        (selectedTemplate?.variables ?? []).filter { $0.userEditable }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func loadOptions() async {
        guard let service else { return }
        if optionsState.value == nil { optionsState = .loading }
        do {
            async let t = service.templates()
            async let n = service.nodes()
            let (temps, nds) = try await (t, n)
            templates = temps.sorted { ($0.sortOrder, $0.name.lowercased()) < ($1.sortOrder, $1.name.lowercased()) }
            nodes = nds
            if nodeId == nil { nodeId = nodes.first?.id }
            if templateId == nil { templateId = templates.first?.id }   // triggers onTemplateChange
            optionsState = .loaded(true)
        }
        catch let error as APIError { optionsState = .failed(error) }
        catch { optionsState = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    private func onTemplateChange() {
        guard let t = selectedTemplate else { env = [:]; return }
        // Prefill resources from the template's recommended spec.
        cpuText = numberString(t.recCpuCores)
        memoryText = String(t.recMemoryMb)
        diskText = String(t.recDiskMb)
        // Seed editable env vars, preserving anything already typed.
        var next: [String: String] = [:]
        for v in (t.variables ?? []) where v.userEditable {
            next[v.envName] = env[v.envName] ?? (v.defaultValue ?? "")
        }
        env = next
    }

    private func numberString(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }

    var canSubmit: Bool {
        guard owner != nil, nodeId != nil, templateId != nil,
              !name.trimmingCharacters(in: .whitespaces).isEmpty, !submitting else { return false }
        if sizeBySlots { return slots > 0 }
        return Double(cpuText) != nil && Int(memoryText) != nil && Int(diskText) != nil
    }

    func nodeName(_ id: String?) -> String {
        nodes.first { $0.id == id }?.name ?? "the node"
    }

    func submit() async {
        guard let service, let owner, let nodeId, let templateId else { return }
        submitting = true; message = nil
        defer { submitting = false }
        var body = AdminCreateServerBody(name: name.trimmingCharacters(in: .whitespaces),
                                         ownerId: owner.id, nodeId: nodeId, templateId: templateId)
        if sizeBySlots {
            body.slots = slots
        } else {
            body.cpuCores = Double(cpuText)
            body.memoryMb = Int(memoryText)
            body.diskMb = Int(diskText)
        }
        let filled = env.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        if !filled.isEmpty { body.environment = filled }
        do {
            let server = try await service.createServer(body)
            createdServerId = server.id
            message = "Server created — provisioning on \(nodeName(nodeId))."
        }
        catch let error as APIError { message = error.userMessage }
        catch { message = "Couldn't create the server. Check the resources and try again." }
    }
}

// MARK: - Create server wizard

/// Admin → Servers → Create, native. Pick an owner, a node, and a game
/// template, size by resources or slots, set any template variables, and
/// provision directly. Presented as a sheet from the staff server list.
struct AdminCreateServerView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AdminCreateServerViewModel()
    @State private var showOwnerPicker = false
    @State private var goToServer = false
    let onCreated: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let message = model.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(model.createdServerId == nil ? .appDestructive : .appSuccess)
                        .listRowBackground(Color.appCard)
                }

                if model.createdServerId != nil {
                    successSection
                } else {
                    identitySection
                    placementSection
                    gameSection
                    sizingSection
                    configurationSection
                    createSection
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Create server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.createdServerId == nil ? "Cancel" : "Done") {
                        if model.createdServerId != nil { onCreated() }
                        dismiss()
                    }
                }
            }
            .task { model.bind(session); if model.optionsState.value == nil { await model.loadOptions() } }
            .sheet(isPresented: $showOwnerPicker) {
                OwnerPickerView { model.owner = $0 }
            }
            .navigationDestination(isPresented: $goToServer) {
                if let id = model.createdServerId { ServerDetailView(serverId: id, preview: nil) }
            }
        }
    }

    // MARK: Sections

    private var identitySection: some View {
        Section("Server") {
            TextField("Server name", text: $model.name)
            Button { showOwnerPicker = true } label: {
                HStack {
                    Text("Owner").foregroundStyle(.appForeground)
                    Spacer()
                    Text(model.owner?.displayName ?? "Select…")
                        .foregroundStyle(model.owner == nil ? .appMuted : .appAccentText)
                        .lineLimit(1)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.appMuted)
                }
            }
        }
        .listRowBackground(Color.appCard)
    }

    @ViewBuilder private var placementSection: some View {
        Section("Node") {
            if model.nodes.isEmpty {
                Text("No nodes available.").font(.caption).foregroundStyle(.appMuted)
            } else {
                Picker("Node", selection: $model.nodeId) {
                    ForEach(model.nodes) { node in
                        Text(nodeLabel(node)).tag(String?.some(node.id))
                    }
                }
                .tint(.appPrimary)
            }
        }
        .listRowBackground(Color.appCard)
    }

    @ViewBuilder private var gameSection: some View {
        Section("Game") {
            if model.templates.isEmpty {
                Text("No game templates available.").font(.caption).foregroundStyle(.appMuted)
            } else {
                Picker("Template", selection: $model.templateId) {
                    ForEach(model.templates) { template in
                        Text(templateLabel(template)).tag(String?.some(template.id))
                    }
                }
                .tint(.appPrimary)
                if let t = model.selectedTemplate {
                    Text(recommendedLabel(t))
                        .font(.caption2).foregroundStyle(.appMuted)
                }
            }
        }
        .listRowBackground(Color.appCard)
    }

    @ViewBuilder private var sizingSection: some View {
        Section {
            Toggle("Size by slots (voice)", isOn: $model.sizeBySlots).tint(.appPrimary)
            if model.sizeBySlots {
                Stepper(value: $model.slots, in: 1...1024) {
                    HStack { Text("Slots"); Spacer()
                        Text("\(model.slots)").font(.body.monospacedDigit()).foregroundStyle(.appAccentText) }
                }
            } else {
                resourceField("CPU cores", text: $model.cpuText, keyboard: .decimalPad, suffix: "vCPU")
                resourceField("Memory", text: $model.memoryText, keyboard: .numberPad, suffix: "MB")
                resourceField("Disk", text: $model.diskText, keyboard: .numberPad, suffix: "MB")
            }
        } header: { Text("Resources") } footer: {
            Text(model.sizeBySlots
                 ? "The node sizes CPU, memory, and disk from the template’s recommended spec for the slot count."
                 : "Prefilled from the template’s recommended spec. Adjust as needed.")
        }
        .listRowBackground(Color.appCard)
    }

    @ViewBuilder private var configurationSection: some View {
        let vars = model.editableVariables
        if !vars.isEmpty {
            Section("Configuration") {
                ForEach(vars) { variable in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(variable.displayName).font(.caption.weight(.medium)).foregroundStyle(.appForeground)
                        envField(variable)
                        if let d = variable.description, !d.isEmpty {
                            Text(d).font(.caption2).foregroundStyle(.appMuted).lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listRowBackground(Color.appCard)
        }
    }

    private var createSection: some View {
        Section {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await model.submit() }
            } label: {
                HStack { if model.submitting { ProgressView() }
                    Text(model.submitting ? "Creating…" : "Create server") }
            }
            .buttonStyle(.refxPrimary)
            .disabled(!model.canSubmit)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private var successSection: some View {
        Section {
            Button("View server") { goToServer = true }
                .buttonStyle(.refxSecondary)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    // MARK: Helpers

    private func resourceField(_ label: String, text: Binding<String>,
                               keyboard: UIKeyboardType, suffix: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.appForeground)
            Spacer()
            TextField("0", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
                .font(.body.monospacedDigit())
            Text(suffix).font(.caption).foregroundStyle(.appMuted)
        }
    }

    @ViewBuilder private func envField(_ variable: TemplateVariable) -> some View {
        let binding = Binding(get: { model.env[variable.envName] ?? "" },
                              set: { model.env[variable.envName] = $0 })
        switch variable.type {
        case .boolean:
            Toggle("Enabled", isOn: Binding(get: { (model.env[variable.envName] ?? "") == "true" },
                                            set: { model.env[variable.envName] = $0 ? "true" : "false" }))
                .tint(.appPrimary)
        case .secret:
            SecureField("Value", text: binding)
        default:
            TextField(variable.defaultValue ?? "Value", text: binding)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }

    private func numberLabel(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }

    private func nodeLabel(_ node: NodeAdmin) -> String {
        if let region = node.region?.name, !region.isEmpty { return "\(node.name) · \(region)" }
        return node.name
    }

    private func templateLabel(_ template: AdminGameTemplate) -> String {
        if let category = template.category?.name, !category.isEmpty { return "\(category) · \(template.name)" }
        return template.name
    }

    private func recommendedLabel(_ t: AdminGameTemplate) -> String {
        "Recommended: \(numberLabel(t.recCpuCores)) vCPU · \(t.recMemoryMb) MB RAM · \(t.recDiskMb) MB disk"
    }
}

// MARK: - Owner picker

/// Searchable user picker for choosing the server owner during admin provisioning.
private struct OwnerPickerView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    let onPick: (AdminUser) -> Void

    @State private var state: LoadState<[AdminUser]> = .idle
    @State private var search = ""

    var body: some View {
        NavigationStack {
            AsyncStateView(
                state: state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No users",
                emptyMessage: "No accounts match that search.",
                retry: { Task { await load() } },
                content: { users in
                    List(users) { user in
                        Button {
                            onPick(user); dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName).foregroundStyle(.appForeground)
                                Text(user.email).font(.caption).foregroundStyle(.appMuted)
                            }
                        }
                        .listRowBackground(Color.appCard)
                    }
                    .scrollContentBackground(.hidden)
                },
                skeleton: { VStack(spacing: 10) { ForEach(0..<6, id: \.self) { _ in SkeletonBlock(height: 48) } }.padding(16) })
            .screenBackground()
            .navigationTitle("Select owner")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search by name or email")
            .onSubmit(of: .search) { Task { await load() } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { if state.value == nil { await load() } }
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do { state = .loaded(try await session.staff.users(query: search.isEmpty ? nil : search).items) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }
}
