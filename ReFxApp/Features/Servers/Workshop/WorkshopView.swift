import SwiftUI
import UIKit

@MainActor
final class WorkshopViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[WorkshopMod]> = .idle
    @Published var actionError: String?
    @Published var isApplying = false

    let serverId: String
    private var service: WorkshopService?

    init(serverId: String) { self.serverId = serverId }

    func bind(_ session: AppSession) { if service == nil { service = session.workshop } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.list(serverId)) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func add(_ input: String) async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await run(haptic: true) { try await $0.add(self.serverId, input: trimmed) }
    }

    func toggle(_ mod: WorkshopMod) async {
        await run { try await $0.toggle(self.serverId, modId: mod.id, enabled: !mod.enabled) }
    }

    func remove(_ mod: WorkshopMod) async {
        await run(haptic: true) { try await $0.remove(self.serverId, modId: mod.id) }
    }

    /// Move items and persist the new order (sortOrder = index). Optimistically
    /// updates the local list so the row animates immediately.
    func move(from offsets: IndexSet, to destination: Int) async {
        guard let service, var items = state.value else { return }
        items.move(fromOffsets: offsets, toOffset: destination)
        state = .loaded(items)
        actionError = nil
        do { try await service.reorder(serverId, ids: items.map(\.id)) }
        catch let error as APIError { actionError = error.userMessage; await load() }
        catch { actionError = "Couldn't save the new order."; await load() }
    }

    func apply() async {
        guard let service else { return }
        actionError = nil
        isApplying = true
        defer { isApplying = false }
        do {
            try await service.apply(serverId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't apply changes." }
    }

    private func run(haptic: Bool = false, _ work: (WorkshopService) async throws -> Void) async {
        guard let service else { return }
        actionError = nil
        do {
            try await work(service)
            if haptic { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            await load()
        }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Action failed. Try again." }
    }
}

struct WorkshopView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: WorkshopViewModel
    @State private var showAdd = false
    @State private var input = ""

    init(serverId: String) { _model = StateObject(wrappedValue: WorkshopViewModel(serverId: serverId)) }

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No Workshop content",
            emptyMessage: "Add Steam Workshop items or collections by ID or URL.",
            retry: { Task { await model.load() } },
            content: { _ in list },
            skeleton: { VStack(spacing: 10) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 52) } }.padding(16) })
        .screenBackground()
        .navigationTitle("Workshop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) { Button { input = ""; showAdd = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add item") }
        }
        .alert("Add Workshop item", isPresented: $showAdd) {
            TextField("ID or Steam Workshop URL", text: $input)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Add") { Task { await model.add(input) } }
            Button("Cancel", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom) { applyBar }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private var list: some View {
        List {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive).listRowBackground(Color.appCard)
            }
            ForEach(model.state.value ?? []) { mod in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mod.displayName).foregroundStyle(.appForeground).lineLimit(1)
                        Text(mod.workshopId).font(.caption2.monospaced()).foregroundStyle(.appMuted)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { mod.enabled }, set: { _ in Task { await model.toggle(mod) } }))
                        .labelsHidden().tint(.appPrimary)
                }
                .listRowBackground(Color.appCard)
                .swipeActions {
                    Button(role: .destructive) { Task { await model.remove(mod) } } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
            .onMove { offsets, destination in
                Task { await model.move(from: offsets, to: destination) }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).screenBackground()
        .refreshable { await model.load() }
    }

    private var applyBar: some View {
        Button { Task { await model.apply() } } label: {
            HStack {
                if model.isApplying { ProgressView().tint(.white) }
                Text(model.isApplying ? "Applying…" : "Apply changes (reinstall)")
            }.frame(maxWidth: .infinity)
        }
        .buttonStyle(.refxPrimary)
        .disabled(model.isApplying)
        .padding(12)
        .background(.ultraThinMaterial)
    }
}

/// Minecraft loader + version config. Loader, Minecraft version and loader build
/// are live dropdowns sourced from the catalog (scoped to the chosen loader, like
/// the web). Saving triggers a reinstall.
struct MinecraftView: View {
    @EnvironmentObject private var session: AppSession
    let serverId: String

    @State private var loader = "paper"
    @State private var version = "latest"
    @State private var loaderVersion = "latest"
    @State private var versions: [String] = []
    @State private var builds: [String] = []
    @State private var isSaving = false
    @State private var message: String?
    @State private var isError = false
    @State private var confirm = false

    @State private var worldStatus: LevelDatStatus?
    @State private var worldMessage: String?
    @State private var restoring = false
    @State private var confirmRestore = false

    private let loaders = ["vanilla", "paper", "fabric", "forge", "neoforge"]
    private var needsBuild: Bool { ["fabric", "forge", "neoforge"].contains(loader) }
    private var buildLabel: String {
        switch loader {
        case "fabric": return "Fabric loader"
        case "forge": return "Forge build"
        case "neoforge": return "NeoForge build"
        default: return "Loader build"
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Loader", selection: $loader) {
                    ForEach(loaders, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.menu)

                Picker("Minecraft version", selection: $version) {
                    Text("Latest (recommended)").tag("latest")
                    if version != "latest", !versions.contains(version) {
                        Text("\(version) (current)").tag(version)
                    }
                    ForEach(versions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)

                if needsBuild {
                    Picker(buildLabel, selection: $loaderVersion) {
                        Text("Latest").tag("latest")
                        if loaderVersion != "latest", !builds.contains(loaderVersion) {
                            Text("\(loaderVersion) (current)").tag(loaderVersion)
                        }
                        ForEach(builds, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Eyebrow("Loader & version")
            } footer: {
                Text("Changing the loader or version reinstalls the server software (world & files preserved).")
            }
            .listRowBackground(Color.appCard)

            if let message {
                Text(message).font(.footnote).foregroundStyle(isError ? .appDestructive : .appSuccess)
                    .listRowBackground(Color.appCard)
            }

            Section {
                Button { confirm = true } label: {
                    HStack { if isSaving { ProgressView() }; Text("Apply & reinstall") }
                }.disabled(isSaving)
            }
            .listRowBackground(Color.appCard)

            worldRecoverySection
        }
        .scrollContentBackground(.hidden).screenBackground()
        .navigationTitle("Minecraft").navigationBarTitleDisplayMode(.inline)
        .task { await loadVersions(); await loadBuilds(); await loadWorldStatus() }
        .confirmationDialog("Restore level.dat?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore") { Task { await restoreWorld() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Replaces the current level.dat with Minecraft's automatic backup copy. The corrupt file is preserved alongside it.")
        }
        .onChange(of: loader) { _ in
            version = "latest"; loaderVersion = "latest"; builds = []
            Task { await loadVersions(); await loadBuilds() }
        }
        .onChange(of: version) { _ in
            loaderVersion = "latest"
            Task { await loadBuilds() }
        }
        .confirmationDialog("Apply and reinstall?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Apply & reinstall", role: .destructive) { Task { await save() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The server will reinstall with \(loader.capitalized) \(version). It will be offline during the process.")
        }
    }

    @ViewBuilder private var worldRecoverySection: some View {
        if let status = worldStatus {
            Section {
                HStack {
                    Label(status.looksCorrupt ? "World may be corrupt" : "World looks healthy",
                          systemImage: status.looksCorrupt ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundStyle(status.looksCorrupt ? .appWarning : .appSuccess)
                }
                if status.restorable {
                    Button {
                        confirmRestore = true
                    } label: {
                        HStack { if restoring { ProgressView() }; Text("Restore level.dat from backup") }
                    }.disabled(restoring)
                } else if status.looksCorrupt {
                    Text("No backup copy is available to restore from.")
                        .font(.caption).foregroundStyle(.appMuted)
                }
                if let worldMessage {
                    Text(worldMessage).font(.footnote)
                        .foregroundStyle(worldMessage.hasPrefix("Restored") ? .appSuccess : .appDestructive)
                }
            } header: {
                Text("World recovery — \(status.world)")
            } footer: {
                Text("Detects and repairs a corrupt level.dat using Minecraft's automatic backup.")
            }
            .listRowBackground(Color.appCard)
        }
    }

    private func loadWorldStatus() async {
        // Only meaningful for Minecraft; tolerate 400/unsupported.
        worldStatus = try? await session.minecraft.levelDatStatus(serverId)
    }

    private func restoreWorld() async {
        restoring = true; worldMessage = nil
        defer { restoring = false }
        do {
            let result = try await session.minecraft.restoreLevelDat(serverId)
            worldMessage = result.restored ? "Restored from backup." : "Nothing to restore."
            await loadWorldStatus()
        } catch let error as APIError { worldMessage = error.userMessage }
        catch { worldMessage = "Couldn't restore level.dat." }
    }

    private func loadVersions() async {
        versions = (try? await session.catalog.minecraftVersions(loader: loader)) ?? []
    }

    private func loadBuilds() async {
        guard needsBuild else { builds = []; return }
        // Backend returns [] for forge/neoforge when version is "latest"; Fabric's
        // loader list is Minecraft-independent, so it loads regardless.
        builds = (try? await session.catalog.minecraftBuilds(loader: loader, version: version)) ?? []
    }

    private func save() async {
        message = nil; isSaving = true
        defer { isSaving = false }
        do {
            try await session.minecraft.setConfig(
                serverId, loader: loader,
                version: version.isEmpty ? nil : version,
                loaderVersion: loader == "vanilla" || loaderVersion.isEmpty ? nil : loaderVersion)
            isError = false; message = "Applied. Reinstalling…"
        } catch let error as APIError { isError = true; message = error.userMessage }
        catch { isError = true; message = "Couldn't apply." }
    }
}
