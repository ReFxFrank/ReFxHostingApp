import SwiftUI
import UIKit

@MainActor
final class ModpacksViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var state: LoadState<[ModSearchResult]> = .idle
    @Published private(set) var installed: InstalledModpack?
    @Published var isSearching = false
    @Published var message: String?
    @Published var isError = false
    /// True while showing the default popular list (no active query).
    @Published private(set) var isFeatured = true

    /// The current result list (empty until loaded).
    var results: [ModSearchResult] { state.value ?? [] }

    @Published var versionsFor: ModSearchResult?
    @Published private(set) var versions: [ModpackVersion] = []
    @Published var loadingVersions = false
    @Published var installingVersionId: String?

    let serverId: String
    private var service: ModpacksService?

    init(serverId: String) { self.serverId = serverId }

    func bind(_ session: AppSession) { if service == nil { service = session.modpacks } }

    func loadInstalled() async {
        guard let service else { return }
        installed = try? await service.installed(serverId)
    }

    /// Popular modpacks shown on open (empty-query search → Modrinth relevance).
    /// Skips re-fetching when a populated featured list is already on screen.
    func loadFeatured() async {
        guard let service, !(isFeatured && !results.isEmpty) else { return }
        isSearching = true
        defer { isSearching = false }
        isFeatured = true
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.search(serverId, query: "")) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func search() async {
        guard let service else { return }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { await loadFeatured(); return }
        isSearching = true
        defer { isSearching = false }
        isFeatured = false
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.search(serverId, query: q)) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    /// Reload the current view (featured list or active query) for pull-to-refresh.
    func refresh() async {
        if isFeatured {
            isFeatured = false // force re-fetch even if a featured list is on screen
            await loadFeatured()
        } else {
            await search()
        }
    }

    func openVersions(_ pack: ModSearchResult) async {
        guard let service else { return }
        versionsFor = pack
        versions = []
        loadingVersions = true
        defer { loadingVersions = false }
        versions = (try? await service.versions(serverId, projectId: pack.projectId)) ?? []
    }

    func install(_ version: ModpackVersion) async {
        guard let service else { return }
        installingVersionId = version.id
        defer { installingVersionId = nil }
        message = nil
        do {
            try await service.install(serverId, versionId: version.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            versionsFor = nil
            flash("Modpack install queued — the server will reinstall.", error: false)
            await loadInstalled()
        } catch let error as APIError { flash(error.userMessage, error: true) }
        catch { flash("Couldn't install.", error: true) }
    }

    func uninstall() async {
        guard let service else { return }
        do {
            try await service.uninstall(serverId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            flash("Modpack removed.", error: false)
            await loadInstalled()
        }
        catch let error as APIError { flash(error.userMessage, error: true) }
        catch { flash("Couldn't remove.", error: true) }
    }

    private func flash(_ text: String, error: Bool) { message = text; isError = error }
}

struct ModpacksView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: ModpacksViewModel

    init(serverId: String) { _model = StateObject(wrappedValue: ModpacksViewModel(serverId: serverId)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let message = model.message {
                    Text(message).font(.footnote)
                        .foregroundStyle(model.isError ? .appDestructive : .appSuccess)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let installed = model.installed {
                    installedCard(installed)
                }
                searchBar

                resultsSection
            }
            .padding(16)
        }
        .refreshable { await model.refresh() }
        .screenBackground()
        .navigationTitle("Modpacks")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $model.versionsFor) { pack in
            VersionPicker(pack: pack, versions: model.versions, loading: model.loadingVersions,
                          installingId: model.installingVersionId) { v in Task { await model.install(v) } }
        }
        .task { model.bind(session); await model.loadInstalled(); await model.loadFeatured() }
    }

    @ViewBuilder
    private var resultsSection: some View {
        switch model.state {
        case .idle, .loading:
            VStack(spacing: 10) { ForEach(0..<5, id: \.self) { _ in SkeletonBlock(height: 76) } }
                .padding(.top, 2)
        case .failed(let error):
            ErrorStateView(error: error, retry: { Task { await model.refresh() } })
        case .loaded(let packs):
            if packs.isEmpty {
                EmptyStateView(title: model.isFeatured ? "No modpacks" : "No results",
                               message: model.isFeatured ? "No popular modpacks to show right now."
                                                          : "Try a different search term.")
            } else {
                SectionHeader(model.isFeatured ? "Popular modpacks" : "Results",
                              systemImage: model.isFeatured ? "flame.fill" : "magnifyingglass")
                    .padding(.horizontal, 4).padding(.top, 2)
                ForEach(packs) { pack in
                    Button { Task { await model.openVersions(pack) } } label: {
                        ModResultRow(mod: pack, installing: false, onInstall: { Task { await model.openVersions(pack) } })
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.appMuted)
            TextField("Search modpacks…", text: $model.query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).onSubmit { Task { await model.search() } }
            if model.isSearching { ProgressView().controlSize(.small) }
        }
        .padding(12).cardSurface()
    }

    private func installedCard(_ pack: InstalledModpack) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Installed").font(.caption.weight(.semibold)).foregroundStyle(.appMuted)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.title ?? "Modpack").foregroundStyle(.appForeground)
                    Text([pack.versionNumber, pack.mcVersion, pack.loader?.capitalized]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.appMuted)
                }
                Spacer()
                Button("Remove", role: .destructive) { Task { await model.uninstall() } }
                    .buttonStyle(.refxDestructive(fullWidth: false))
            }
        }
        .padding(Theme.cardPadding).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }
}

struct VersionPicker: View {
    let pack: ModSearchResult
    let versions: [ModpackVersion]
    let loading: Bool
    let installingId: String?
    let onInstall: (ModpackVersion) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().tint(.appPrimary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if versions.isEmpty {
                    EmptyStateView(title: "No versions", message: "This modpack has no installable versions.")
                } else {
                    List {
                        ForEach(versions) { v in
                            Button { onInstall(v) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(v.displayName).foregroundStyle(.appForeground).lineLimit(1)
                                        Text(v.subtitle).font(.caption2).foregroundStyle(.appMuted)
                                    }
                                    Spacer()
                                    if installingId == v.id { ProgressView().controlSize(.small) }
                                    else { Image(systemName: "arrow.down.circle").foregroundStyle(.appPrimary) }
                                }
                            }
                            .listRowBackground(Color.appCard)
                        }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden).screenBackground()
                }
            }
            .screenBackground()
            .navigationTitle(pack.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
