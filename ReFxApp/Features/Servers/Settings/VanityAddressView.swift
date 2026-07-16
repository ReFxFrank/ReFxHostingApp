import SwiftUI
import UIKit

@MainActor
final class VanityAddressViewModel: ObservableObject {
    @Published private(set) var status: LoadState<VanityStatus> = .idle
    @Published var actionError: String?
    @Published var infoMessage: String?
    @Published var isBusy = false

    let serverId: String
    private var service: ServerSettingsService?

    init(serverId: String) { self.serverId = serverId }

    func bind(_ session: AppSession) { if service == nil { service = session.serverSettings } }

    func load() async {
        guard let service else { return }
        if status.value == nil { status = .loading }
        do { status = .loaded(try await service.vanityStatus(serverId)) }
        catch let error as APIError { status = .failed(error) }
        catch { status = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func setLabel(_ label: String) async {
        guard let service, !isBusy else { return }
        let clean = label.trimmingCharacters(in: .whitespaces).lowercased()
        guard !clean.isEmpty else { return }
        isBusy = true; actionError = nil; infoMessage = nil
        defer { isBusy = false }
        do {
            let result = try await service.setVanity(serverId, label: clean)
            infoMessage = result.isApplied
                ? "Address set: \(result.address)"
                : "An invoice was created to activate this address. Pay it on the web to finish."
            await load()
        } catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't set the address." }
    }

    func remove() async {
        guard let service, !isBusy else { return }
        isBusy = true; actionError = nil; infoMessage = nil
        defer { isBusy = false }
        do { try await service.removeVanity(serverId); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't remove the address." }
    }
}

/// A friendly, memorable connect address (e.g. `myserver.virginia.rfx.refx.gg`).
/// Buying/changing is a paid flow, so it's gated on public builds where in-app
/// purchasing is disabled — the current address is always shown read-only.
struct VanityAddressView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: VanityAddressViewModel
    @State private var showSet = false
    @State private var label = ""
    @State private var confirmRemove = false

    init(serverId: String) { _model = StateObject(wrappedValue: VanityAddressViewModel(serverId: serverId)) }

    var body: some View {
        AsyncStateView(
            state: model.status,
            isEmpty: { _ in false },
            emptyTitle: "Unavailable",
            retry: { Task { await model.load() } },
            content: { content($0) },
            skeleton: { SkeletonBlock(height: 160).padding(16) })
        .screenBackground()
        .navigationTitle("Vanity address")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Choose an address", isPresented: $showSet) {
            TextField("myserver", text: $label)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Set") { Task { await model.setLabel(label) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("3–32 characters: letters, numbers and hyphens. This becomes the start of your connect address.")
        }
        .confirmationDialog("Remove vanity address?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await model.remove() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your server reverts to its default connect address.")
        }
        .task { model.bind(session); if model.status.value == nil { await model.load() } }
    }

    private func content(_ status: VanityStatus) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let address = status.currentAddress {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Current address", systemImage: "link")
                            CopyChip(label: "Address", value: address)
                            if let label = status.currentLabel {
                                Text("Label: \(label)").font(.caption).foregroundStyle(.appMuted)
                            }
                        }
                    }
                } else {
                    Text("No vanity address set. Your server uses its default connect address.")
                        .font(.subheadline).foregroundStyle(.appMuted)
                }

                if let pending = status.pending {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionHeader("Pending", systemImage: "clock")
                            Text("\(pending.address)").font(.callout).foregroundStyle(.appForeground)
                            Text("Awaiting payment of \(Money(minorUnits: pending.amountMinor, currency: pending.currency).formatted).")
                                .font(.caption).foregroundStyle(.appWarning)
                        }
                    }
                }

                if let info = model.infoMessage {
                    Text(info).font(.footnote).foregroundStyle(.appSuccess)
                }
                if let error = model.actionError {
                    Text(error).font(.footnote).foregroundStyle(.appDestructive)
                }

                if FeatureFlags.purchasingEnabled {
                    VStack(spacing: 10) {
                        Button {
                            label = status.currentLabel ?? ""; showSet = true
                        } label: {
                            HStack { if model.isBusy { ProgressView() }
                                Text(status.currentAddress == nil ? "Set vanity address (\(status.feeDescription))" : "Change address") }
                        }
                        .buttonStyle(.refxPrimary).disabled(model.isBusy)

                        if status.currentAddress != nil {
                            Button(role: .destructive) { confirmRemove = true } label: {
                                Text("Remove vanity address")
                            }.buttonStyle(.refxSecondary).disabled(model.isBusy)
                        }
                    }
                } else {
                    Text("Buying or changing a vanity address is available on the web.")
                        .font(.caption).foregroundStyle(.appMuted)
                }
            }
            .padding(16)
        }
    }
}
