import Foundation

@MainActor
final class ServersListViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[Server]> = .idle
    @Published var searchText = ""

    private var service: ServersService?
    private var meta: PageMeta?
    private var loadedPages: [Server] = []
    private var loadingMore = false

    /// Inject the session's service once the environment is available (the view
    /// constructs the VM at init, before `@EnvironmentObject` is resolved).
    func bind(_ service: ServersService) {
        if self.service == nil { self.service = service }
    }

    /// Servers needing attention (offline/suspended/crashed) float to the top.
    var sortedServers: [Server] {
        (state.value ?? []).sorted { lhs, rhs in
            if lhs.state.needsAttention != rhs.state.needsAttention {
                return lhs.state.needsAttention
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var attentionCount: Int {
        (state.value ?? []).filter { $0.state.needsAttention }.count
    }

    func load(reset: Bool = true) async {
        guard let service else { return }
        if reset {
            state = .loading
            loadedPages = []
            meta = nil
        }
        do {
            let page = try await service.list(
                page: 1, query: searchText.isEmpty ? nil : searchText)
            loadedPages = page.items
            meta = page.meta
            state = .loaded(loadedPages)
            WidgetBridge.publish(servers: loadedPages)
        } catch let error as APIError {
            state = .failed(error)
        } catch {
            state = .failed(.network(isOffline: false, underlying: error.localizedDescription))
        }
    }

    /// Quiet refresh (pull-to-refresh / foreground / 12s tick) that doesn't flash
    /// a skeleton. Re-fetches *all currently-loaded pages* so a scrolled-down,
    /// multi-page list keeps its depth instead of snapping back to the first 25.
    func refresh() async {
        guard let service else { return }
        let pagesLoaded = max(1, meta?.page ?? 1)
        do {
            var combined: [Server] = []
            var lastMeta: PageMeta?
            for p in 1...pagesLoaded {
                let page = try await service.list(
                    page: p, query: searchText.isEmpty ? nil : searchText)
                combined += page.items
                lastMeta = page.meta
                if page.meta.page >= page.meta.totalPages { break }   // fleet shrank
            }
            loadedPages = combined
            meta = lastMeta
            state = .loaded(combined)
            WidgetBridge.publish(servers: combined)
        } catch {
            // Keep showing the last good data on a refresh failure.
            if state.value == nil { await load() }
        }
    }

    func loadMoreIfNeeded(currentItem: Server) async {
        guard let service, let meta, meta.page < meta.totalPages, !loadingMore else { return }
        // Prefetch when nearing the end of the DISPLAYED (sorted) order. Keying
        // off loadedPages (raw fetch order) put the trigger row at an arbitrary
        // position, so paging fired unreliably past the first page.
        let displayed = sortedServers
        guard let idx = displayed.firstIndex(where: { $0.id == currentItem.id }),
              idx >= displayed.count - 3 else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let next = try await service.list(
                page: meta.page + 1, query: searchText.isEmpty ? nil : searchText)
            loadedPages += next.items
            self.meta = next.meta
            state = .loaded(loadedPages)
        } catch {
            // Silently stop paginating on error; pull-to-refresh recovers.
        }
    }
}
