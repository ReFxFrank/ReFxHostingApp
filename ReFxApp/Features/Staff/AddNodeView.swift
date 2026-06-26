import SwiftUI
import UIKit

// MARK: - View model

@MainActor
final class AddNodeViewModel: ObservableObject {
    @Published var regions: [Region] = []
    @Published var regionsState: LoadState<Bool> = .idle

    @Published var name = ""
    @Published var fqdn = ""
    @Published var regionId: String?
    @Published var os: NodeOS = .linux
    @Published var cpuText = "8"
    @Published var memoryText = "16384"
    @Published var diskText = "512000"
    @Published var portStartText = "25565"
    @Published var portEndText = "25999"

    @Published var submitting = false
    @Published var errorText: String?
    @Published var result: CreateNodeResult?

    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func loadRegions() async {
        guard let service else { return }
        if regionsState.value == nil { regionsState = .loading }
        do {
            regions = try await service.locations()
            if regionId == nil { regionId = regions.first?.id }
            regionsState = .loaded(true)
        }
        catch let error as APIError { regionsState = .failed(error) }
        catch { regionsState = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    // Parsed fields
    private var cpu: Int? { Int(cpuText) }
    private var memory: Int? { Int(memoryText) }
    private var disk: Int? { Int(diskText) }
    private var portStart: Int? { Int(portStartText) }
    private var portEnd: Int? { Int(portEndText) }

    var portsValid: Bool {
        guard let start = portStart, let end = portEnd else { return false }
        return (1...65535).contains(start) && (1...65535).contains(end) && start <= end
    }

    var canSubmit: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !fqdn.trimmingCharacters(in: .whitespaces).isEmpty,
              regionId != nil, !submitting else { return false }
        guard let cpu, let memory, let disk else { return false }
        return cpu >= 1 && memory >= 512 && disk >= 1024 && portsValid
    }

    func submit() async {
        guard let service, let regionId,
              let cpu, let memory, let disk, let start = portStart, let end = portEnd else { return }
        submitting = true; errorText = nil
        defer { submitting = false }
        let body = CreateNodeBody(
            name: name.trimmingCharacters(in: .whitespaces),
            fqdn: fqdn.trimmingCharacters(in: .whitespaces),
            regionId: regionId, os: os.rawValue,
            cpuCores: cpu, memoryMb: memory, diskMb: disk,
            allocationPortStart: start, allocationPortEnd: end)
        do { result = try await service.createNode(body) }
        catch let error as APIError { errorText = error.userMessage }
        catch { errorText = "Couldn't create the node. Check the fields and try again." }
    }
}

// MARK: - Add node form

/// Admin → Nodes → Add, native. Registers a node and surfaces the one-time
/// bootstrap token for the operator to run the installer with. Presented as a
/// sheet from the node-health screen.
struct AddNodeView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AddNodeViewModel()
    let onCreated: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let result = model.result {
                    bootstrapSection(result)
                } else {
                    if let errorText = model.errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.appDestructive)
                            .listRowBackground(Color.appCard)
                    }
                    identitySection
                    placementSection
                    resourcesSection
                    portsSection
                    createSection
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(model.result == nil ? "Add node" : "Node created")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.result == nil ? "Cancel" : "Done") {
                        if model.result != nil { onCreated() }
                        dismiss()
                    }
                }
            }
            .task { model.bind(session); if model.regionsState.value == nil { await model.loadRegions() } }
        }
    }

    // MARK: Form sections

    private var identitySection: some View {
        Section("Identity") {
            TextField("Name (e.g. node-eu-01)", text: $model.name)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("FQDN (e.g. node-eu-01.example.com)", text: $model.fqdn)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.URL)
        }
        .listRowBackground(Color.appCard)
    }

    @ViewBuilder private var placementSection: some View {
        Section("Placement") {
            if model.regions.isEmpty {
                Text("No regions yet — add a location first.").font(.caption).foregroundStyle(.appMuted)
            } else {
                Picker("Region", selection: $model.regionId) {
                    ForEach(model.regions) { region in
                        Text(regionLabel(region)).tag(String?.some(region.id))
                    }
                }
                .tint(.appPrimary)
            }
            Picker("Operating system", selection: $model.os) {
                ForEach(NodeOS.allCases) { os in Text(os.label).tag(os) }
            }
            .tint(.appPrimary)
        }
        .listRowBackground(Color.appCard)
    }

    private var resourcesSection: some View {
        Section {
            numberField("CPU cores", text: $model.cpuText, suffix: "vCPU")
            numberField("Memory", text: $model.memoryText, suffix: "MB")
            numberField("Disk", text: $model.diskText, suffix: "MB")
        } header: { Text("Capacity") } footer: {
            Text("Total resources the node advertises to the scheduler.")
        }
        .listRowBackground(Color.appCard)
    }

    private var portsSection: some View {
        Section {
            numberField("Port range start", text: $model.portStartText, suffix: nil)
            numberField("Port range end", text: $model.portEndText, suffix: nil)
        } header: { Text("Allocation ports") } footer: {
            Text(model.portsValid
                 ? "Servers on this node get a free port from this range."
                 : "Start and end must be 1–65535, and start cannot exceed end.")
                .foregroundStyle(model.portsValid ? .appMuted : .appDestructive)
        }
        .listRowBackground(Color.appCard)
    }

    private var createSection: some View {
        Section {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await model.submit() }
            } label: {
                HStack { if model.submitting { ProgressView() }
                    Text(model.submitting ? "Creating…" : "Create node") }
            }
            .buttonStyle(.refxPrimary)
            .disabled(!model.canSubmit)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private func bootstrapSection(_ result: CreateNodeResult) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Bootstrap token", systemImage: "key.horizontal.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                Text(result.bootstrapToken)
                    .font(.footnote.monospaced()).foregroundStyle(.appAccentText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.appBackground))
                Button {
                    UIPasteboard.general.string = result.bootstrapToken
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: { Label("Copy token", systemImage: "doc.on.doc") }
                .buttonStyle(.refxSecondary)
                Text("Shown once — it can’t be retrieved later. Run the node installer with this token to register the agent.")
                    .font(.caption2).foregroundStyle(.appWarning)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.appCard)
    }

    // MARK: Helpers

    private func numberField(_ label: String, text: Binding<String>, suffix: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(.appForeground)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
                .font(.body.monospacedDigit())
            if let suffix { Text(suffix).font(.caption).foregroundStyle(.appMuted) }
        }
    }

    private func regionLabel(_ region: Region) -> String {
        "\(region.name) · \(region.country)"
    }
}
