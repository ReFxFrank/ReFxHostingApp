import SwiftUI
import UIKit

@MainActor
final class ModsViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [ModSearchResult] = []
    @Published private(set) var installed: [InstalledMod] = []
    @Published private(set) var context: ModContext?
    @Published var isSearching = false
    @Published var message: String?
    @Published var isError = false
    @Published var installingId: String?

    let serverId: String
    private var service: ModsService?

    init(serverId: String) { self.serverId = serverId }

    func bind(_ session: AppSession) { if service == nil { service = session.mods } }

    func loadInitial() async {
        guard let service else { return }
        context = try? await service.context(serverId)
        await loadInstalled()
    }

    func loadInstalled() async {
        guard let service else { return }
        if let res = try? await service.installed(serverId) { installed = res.files }
    }

    func search() async {
        guard let service else { return }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        isSearching = true
        defer { isSearching = false }
        do { results = try await service.search(serverId, query: q) }
        catch { flash("Search failed.", error: true) }
    }

    func install(_ mod: ModSearchResult) async {
        guard let service else { return }
        installingId = mod.projectId
        defer { installingId = nil }
        message = nil
        do {
            try await service.install(serverId, projectId: mod.projectId)
            flash("Installed \(mod.title).", error: false)
            await loadInstalled()
        } catch let error as APIError { flash(error.userMessage, error: true) }
        catch { flash("Couldn't install.", error: true) }
    }

    func remove(_ mod: InstalledMod) async {
        guard let service else { return }
        do { try await service.remove(serverId, filename: mod.name); await loadInstalled() }
        catch { flash("Couldn't remove \(mod.name).", error: true) }
    }

    private func flash(_ text: String, error: Bool) { message = text; isError = error }
}

struct ModsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: ModsViewModel
    @State private var tab = 0

    init(serverId: String) { _model = StateObject(wrappedValue: ModsViewModel(serverId: serverId)) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Browse").tag(0); Text("Installed").tag(1)
            }
            .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 10)

            if let message = model.message {
                Text(message).font(.footnote)
                    .foregroundStyle(model.isError ? .appDestructive : .appSuccess)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
            }

            if tab == 0 { browse } else { installedList }
        }
        .screenBackground()
        .navigationTitle("Mods")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.bind(session); await model.loadInitial() }
    }

    private var browse: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.appMuted)
                TextField("Search Modrinth…", text: $model.query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search).onSubmit { Task { await model.search() } }
                if model.isSearching { ProgressView().controlSize(.small) }
            }
            .padding(12).cardSurface().padding(.horizontal, 16).padding(.bottom, 8)

            if let ctx = model.context, let gv = ctx.gameVersion {
                Text("Compatible with \(ctx.loader?.capitalized ?? "") \(gv)")
                    .font(.caption2).foregroundStyle(.appMuted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.results) { mod in
                        ModResultRow(mod: mod, installing: model.installingId == mod.projectId) {
                            Task { await model.install(mod) }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var installedList: some View {
        Group {
            if model.installed.isEmpty {
                EmptyStateView(title: "No mods installed", message: "Browse and install mods to see them here.")
            } else {
                List {
                    ForEach(model.installed) { mod in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mod.name).foregroundStyle(.appForeground).lineLimit(1)
                            Text(mod.sizeDescription).font(.caption2).foregroundStyle(.appMuted)
                        }
                        .listRowBackground(Color.appCard)
                        .swipeActions {
                            Button(role: .destructive) { Task { await model.remove(mod) } } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden).screenBackground()
                .refreshable { await model.loadInstalled() }
            }
        }
    }
}

struct ModResultRow: View {
    let mod: ModSearchResult
    let installing: Bool
    let onInstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: mod.iconUrl ?? "")) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "shippingbox.fill").font(.title3).foregroundStyle(.appLabel)
                }
            }
            .frame(width: 46, height: 46)
            .background(Color.appPopover)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.appBorder, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(mod.title).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground).lineLimit(1)
                if let desc = mod.description {
                    Text(desc).font(.caption2).foregroundStyle(.appMuted).lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let author = mod.author {
                        Text(author).font(.caption2).foregroundStyle(.appMuted)
                    }
                    Label(mod.downloadsDescription, systemImage: "arrow.down.circle")
                        .font(.caption2).foregroundStyle(.appMuted)
                }
            }
            Spacer()
            Button(action: onInstall) {
                if installing { ProgressView().controlSize(.small) }
                else { Text("Install").font(.caption.weight(.semibold)) }
            }
            .buttonStyle(.refxPrimary(fullWidth: false))
            .disabled(installing)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
