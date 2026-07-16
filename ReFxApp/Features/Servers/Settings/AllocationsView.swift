import SwiftUI
import UIKit

@MainActor
final class AllocationsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[Allocation]> = .idle
    @Published var actionError: String?
    @Published private(set) var isAdding = false

    let serverId: String
    private var service: ServerSettingsService?

    init(serverId: String) { self.serverId = serverId }

    func bind(_ session: AppSession) { if service == nil { service = session.serverSettings } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.allocations(serverId)) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    /// The IP to prefill the add-port form with (the primary allocation's IP).
    var defaultIP: String { state.value?.first(where: { $0.isPrimary })?.ip ?? state.value?.first?.ip ?? "" }

    func add(ip: String, port: Int) async {
        guard let service, !isAdding else { return }
        isAdding = true; actionError = nil
        defer { isAdding = false }
        do { try await service.addAllocation(serverId, ip: ip, port: port); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't add a port. Try again." }
    }

    func delete(_ allocation: Allocation) async {
        guard let service else { return }
        actionError = nil
        do { try await service.deleteAllocation(serverId, allocationId: allocation.id); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't remove the port. Try again." }
    }
}

/// Extra port allocations for a server. The primary allocation is the connect
/// address and can't be removed; additional ports are assigned from the node.
struct AllocationsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: AllocationsViewModel

    @State private var showAdd = false

    init(serverId: String) { _model = StateObject(wrappedValue: AllocationsViewModel(serverId: serverId)) }

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No ports",
            emptyMessage: "This server has no port allocations yet.",
            retry: { Task { await model.load() } },
            content: { _ in list },
            skeleton: { VStack(spacing: 10) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 60) } }.padding(16) })
        .screenBackground()
        .navigationTitle("Ports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: {
                    if model.isAdding { ProgressView() } else { Image(systemName: "plus") }
                }
                .disabled(model.isAdding)
                .accessibilityLabel("Add port")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddAllocationSheet(defaultIP: model.defaultIP) { ip, port in
                Task { await model.add(ip: ip, port: port) }
            }
        }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private var list: some View {
        List {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive).listRowBackground(Color.appCard)
            }
            ForEach(model.state.value ?? []) { allocation in
                AllocationRow(allocation: allocation)
                    .listRowBackground(Color.appCard)
                    .swipeActions(edge: .trailing) {
                        if !allocation.isPrimary {
                            Button(role: .destructive) { Task { await model.delete(allocation) } } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
            }
            Section {
                Text("The primary port is your connect address and can't be removed. Additional ports are assigned automatically from the node.")
                    .font(.caption).foregroundStyle(.appMuted)
            }.listRowBackground(Color.clear)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).screenBackground()
        .refreshable { await model.load() }
    }
}

/// Attach a specific `ip:port`. The backend has no auto-assign, so the customer
/// supplies a free port on the server's node (IP defaults to the primary's).
private struct AddAllocationSheet: View {
    let defaultIP: String
    let onAdd: (String, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ip = ""
    @State private var portText = ""

    private var port: Int? { Int(portText.trimmingCharacters(in: .whitespaces)) }
    private var isValid: Bool { !ip.trimmingCharacters(in: .whitespaces).isEmpty && (port.map { $0 > 0 && $0 <= 65535 } ?? false) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("IP address", text: $ip)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Port (1–65535)", text: $portText)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Add a port")
                } footer: {
                    Text("Attach an additional port on this server's node. It must be a free port in your node's allocation pool — if it's taken you'll get an error.")
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("Add port").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let port { onAdd(ip.trimmingCharacters(in: .whitespaces), port) }
                        dismiss()
                    }.disabled(!isValid)
                }
            }
            .onAppear { if ip.isEmpty { ip = defaultIP } }
        }
    }
}

private struct AllocationRow: View {
    let allocation: Allocation

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(allocation.connectionString).font(.callout.monospaced()).foregroundStyle(.appForeground)
                    if allocation.isPrimary {
                        Text("PRIMARY").font(.caption2.weight(.bold)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.appPrimary.opacity(0.15))
                            .foregroundStyle(.appAccentText).clipShape(Capsule())
                    }
                }
                if let alias = allocation.alias, alias != allocation.ip {
                    Text(alias).font(.caption2).foregroundStyle(.appMuted)
                }
            }
            Spacer()
            Button {
                UIPasteboard.general.string = allocation.connectionString
            } label: { Image(systemName: "doc.on.doc").foregroundStyle(.appMuted) }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
