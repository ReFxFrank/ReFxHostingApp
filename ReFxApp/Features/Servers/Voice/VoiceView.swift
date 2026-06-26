import SwiftUI
import UIKit

@MainActor
final class VoiceViewModel: ObservableObject {
    @Published private(set) var info: VoiceInfo?
    @Published private(set) var status: VoiceStatus?
    @Published private(set) var loaded = false
    @Published var message: String?
    @Published var isError = false

    let serverId: String
    private var service: VoiceService?

    init(serverId: String) { self.serverId = serverId }

    func bind(_ session: AppSession) { if service == nil { service = session.voice } }

    func load() async {
        guard let service else { return }
        info = try? await service.info(serverId)
        status = try? await service.status(serverId)
        loaded = true
    }

    func acceptLicense() async {
        guard let service else { return }
        await run("License accepted.") { try await service.acceptLicense(self.serverId) }
    }

    func rename(_ name: String) async {
        guard let service, !name.isEmpty else { return }
        await run("Renamed.") { try await service.rename(self.serverId, name: name) }
    }

    private func run(_ success: String, _ work: () async throws -> Void) async {
        message = nil
        do { try await work(); await load(); message = success; isError = false }
        catch let error as APIError { message = error.userMessage; isError = true }
        catch { message = "Action failed."; isError = true }
    }
}

/// TeamSpeak voice admin: live status, connection details, the first-boot admin
/// privilege key, license acceptance and renaming.
struct VoiceView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: VoiceViewModel
    @State private var showRename = false
    @State private var newName = ""

    init(serverId: String) { _model = StateObject(wrappedValue: VoiceViewModel(serverId: serverId)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !model.loaded {
                    ProgressView().tint(.appPrimary).padding(.top, 40)
                } else {
                    if let message = model.message {
                        Text(message).font(.footnote)
                            .foregroundStyle(model.isError ? .appDestructive : .appSuccess)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    statusCard
                    connectionCard
                    if let info = model.info, !info.licenseAccepted {
                        Button { Task { await model.acceptLicense() } } label: {
                            Label("Accept TeamSpeak license", systemImage: "checkmark.seal")
                        }
                        .buttonStyle(.refxPrimary)
                    }
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { newName = ""; showRename = true } label: { Image(systemName: "pencil") }
                    .accessibilityLabel("Rename voice server")
            }
        }
        .alert("Rename server", isPresented: $showRename) {
            TextField("Server name", text: $newName)
            Button("Rename") { Task { await model.rename(newName) } }
            Button("Cancel", role: .cancel) {}
        }
        .task { model.bind(session); await model.load() }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.status?.serverName ?? "TeamSpeak server")
                    .font(.headline).foregroundStyle(.appForeground).lineLimit(1)
                Spacer()
                StatusChip(text: (model.status?.ready ?? false) ? "Online" : "Offline",
                           color: (model.status?.ready ?? false) ? .appSuccess : .appMuted)
            }
            HStack(spacing: 18) {
                VoiceStat(value: "\(model.status?.online ?? 0)\(maxSuffix)", label: "Clients")
                VoiceStat(value: "\(model.status?.channelCount ?? 0)", label: "Channels")
                if let up = model.status?.uptimeSeconds, up > 0 {
                    VoiceStat(value: Format.duration(ms: Double(up) * 1000), label: "Uptime")
                }
            }
        }
        .padding(Theme.cardPadding).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    private var maxSuffix: String {
        if let max = model.status?.maxClients ?? model.info?.slots { return "/\(max)" }
        return ""
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connection").font(.caption.weight(.semibold)).foregroundStyle(.appMuted)
            if let address = model.info?.address {
                CopyChip(label: "Address", value: address)
            }
            if let key = model.info?.privilegeKey, !key.isEmpty {
                Text("Admin privilege key (use once in the TeamSpeak client)")
                    .font(.caption2).foregroundStyle(.appMuted)
                CopyChip(label: "Privilege key", value: key)
            }
        }
        .padding(Theme.cardPadding).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }
}

struct VoiceStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(.appForeground)
            Text(label).font(.caption2).foregroundStyle(.appMuted)
        }
    }
}
