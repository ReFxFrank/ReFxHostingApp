import SwiftUI
import UIKit

@MainActor
final class DomainsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[ServerDomain]> = .idle
    @Published var actionError: String?
    @Published var lastDnsTarget: String?   // shown after add/verify so DNS can be set
    @Published var isBusy = false

    let serverId: String
    private var service: ServerSettingsService?

    init(serverId: String) { self.serverId = serverId }

    func bind(_ session: AppSession) { if service == nil { service = session.serverSettings } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.domains(serverId)) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func add(hostname: String) async {
        guard let service, !isBusy else { return }
        let host = hostname.trimmingCharacters(in: .whitespaces).lowercased()
        guard !host.isEmpty else { return }
        isBusy = true; actionError = nil
        defer { isBusy = false }
        do {
            let created = try await service.addDomain(serverId, hostname: host)
            lastDnsTarget = created.dnsTarget
            await load()
        } catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't add the domain." }
    }

    func verify(_ domain: ServerDomain) async {
        guard let service, !isBusy else { return }
        isBusy = true; actionError = nil
        defer { isBusy = false }
        do {
            let result = try await service.verifyDomain(serverId, domainId: domain.id)
            lastDnsTarget = result.dnsTarget
            if result.verified == false { actionError = "DNS isn't pointing here yet. Update your DNS and try again." }
            await load()
        } catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't verify the domain." }
    }

    func delete(_ domain: ServerDomain) async {
        guard let service else { return }
        actionError = nil
        do { try await service.deleteDomain(serverId, domainId: domain.id); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't remove the domain." }
    }
}

/// Custom domains for a WEB_APP server: add a hostname, point DNS at the shown
/// target, then verify. SSL provisions automatically once verified.
struct DomainsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: DomainsViewModel
    @State private var showAdd = false
    @State private var hostname = ""

    init(serverId: String) { _model = StateObject(wrappedValue: DomainsViewModel(serverId: serverId)) }

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No custom domains",
            emptyMessage: "Add your own domain and point it at this server.",
            retry: { Task { await model.load() } },
            content: { _ in list },
            skeleton: { VStack(spacing: 10) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 64) } }.padding(16) })
        .screenBackground()
        .navigationTitle("Custom domains")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { hostname = ""; showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add domain")
            }
        }
        .alert("Add domain", isPresented: $showAdd) {
            TextField("play.example.com", text: $hostname)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Add") { Task { await model.add(hostname: hostname) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a hostname you own. You'll get a DNS target to point it at.")
        }
        .alert("Point your DNS here", isPresented: Binding(
            get: { model.lastDnsTarget != nil }, set: { if !$0 { model.lastDnsTarget = nil } })) {
            Button("Copy") { if let t = model.lastDnsTarget { UIPasteboard.general.string = t } }
            Button("Done", role: .cancel) {}
        } message: {
            if let t = model.lastDnsTarget {
                Text("Create a CNAME (or A) record pointing to:\n\n\(t)\n\nThen verify the domain.")
            }
        }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private var list: some View {
        List {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive).listRowBackground(Color.appCard)
            }
            ForEach(model.state.value ?? []) { domain in
                DomainRow(domain: domain, verify: { Task { await model.verify(domain) } }, busy: model.isBusy)
                    .listRowBackground(Color.appCard)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await model.delete(domain) } } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).screenBackground()
        .refreshable { await model.load() }
    }
}

private struct DomainRow: View {
    let domain: ServerDomain
    let verify: () -> Void
    let busy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(domain.hostname).foregroundStyle(.appForeground).lineLimit(1)
                if domain.isPrimary {
                    Text("PRIMARY").font(.caption2.weight(.bold)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.appPrimary.opacity(0.15))
                        .foregroundStyle(.appAccentText).clipShape(Capsule())
                }
            }
            HStack(spacing: 8) {
                Label(domain.isVerified ? "Verified" : "Unverified",
                      systemImage: domain.isVerified ? "checkmark.seal.fill" : "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(domain.isVerified ? .appSuccess : .appWarning)
                Text("· \(domain.sslStatus.label)").font(.caption2).foregroundStyle(domain.sslStatus.color)
            }
            if !domain.isVerified {
                Button { verify() } label: {
                    HStack(spacing: 6) { if busy { ProgressView().controlSize(.mini) }; Text("Verify DNS") }
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.appPrimary)
                .disabled(busy)
            }
        }
        .padding(.vertical, 4)
    }
}
