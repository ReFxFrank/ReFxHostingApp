import Foundation
import UIKit

@MainActor
final class FilesBrowserViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[FileEntry]> = .idle
    @Published var actionError: String?

    let path: String
    private var service: FilesService?
    private var serverId: String?

    init(path: String) {
        self.path = path
    }

    /// Directories first, then files, each alphabetical.
    var sortedEntries: [FileEntry] {
        (state.value ?? []).sorted { lhs, rhs in
            if lhs.isDir != rhs.isDir { return lhs.isDir }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func bind(serverId: String, service: FilesService) {
        self.serverId = serverId
        if self.service == nil { self.service = service }
    }

    func load() async {
        guard let service, let serverId else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await service.list(serverId, path: path))
        } catch let error as APIError {
            state = .failed(error)
        } catch {
            state = .failed(.network(isOffline: false, underlying: error.localizedDescription))
        }
    }

    func refresh() async { await load() }

    func makeDirectory(named name: String) async {
        guard let service, let serverId, !name.isEmpty else { return }
        let newPath = join(path, name)
        await run { try await service.mkdir(serverId, path: newPath) }
    }

    func delete(_ entry: FileEntry) async {
        guard let service, let serverId else { return }
        await run(haptic: true) { try await service.delete(serverId, paths: [entry.path]) }
    }

    func rename(_ entry: FileEntry, to newName: String) async {
        guard let service, let serverId, !newName.isEmpty, newName != entry.name else { return }
        let target = join(path, newName)
        await run { try await service.rename(serverId, from: entry.path, to: target) }
    }

    func downloadURL(for entry: FileEntry) async -> URL? {
        guard let service, let serverId else { return nil }
        return try? await service.downloadURL(serverId, path: entry.path)
    }

    func compress(_ entry: FileEntry) async {
        guard let service, let serverId else { return }
        await run(haptic: true) { _ = try await service.compress(serverId, paths: [entry.path]) }
    }

    func decompress(_ entry: FileEntry) async {
        guard let service, let serverId else { return }
        await run(haptic: true) { try await service.decompress(serverId, path: entry.path) }
    }

    /// Run a mutation then reload; surface errors in `actionError`.
    private func run(haptic: Bool = false, _ work: () async throws -> Void) async {
        actionError = nil
        do {
            try await work()
            if haptic { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            await load()
        } catch let error as APIError {
            actionError = error.userMessage
        } catch {
            actionError = "Action failed. Try again."
        }
    }

    /// Join a directory path with a child name, normalizing slashes.
    private func join(_ dir: String, _ name: String) -> String {
        var base = dir
        if base.hasSuffix("/") { base.removeLast() }
        return "\(base)/\(name)"
    }
}
