import SwiftUI
import UIKit

@MainActor
final class BackupsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[Backup]> = .idle
    @Published var actionError: String?
    @Published var isCreating = false

    let serverId: String
    private var service: BackupsService?

    init(serverId: String) { self.serverId = serverId }

    /// Newest first.
    var backups: [Backup] { (state.value ?? []).sorted { $0.createdAt > $1.createdAt } }

    /// A backup is still being produced — poll until it settles.
    var hasWorkingBackup: Bool { (state.value ?? []).contains { $0.state.isWorking } }

    func bind(_ session: AppSession) {
        if service == nil { service = session.backups }
    }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.list(serverId).items) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func refresh() async {
        guard let service else { return }
        if let page = try? await service.list(serverId) { state = .loaded(page.items) }
    }

    func create(name: String) async {
        guard let service else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        actionError = nil
        isCreating = true
        defer { isCreating = false }
        do {
            try await service.create(serverId, name: trimmed)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load()
        } catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't start the backup." }
    }

    func restore(_ backup: Backup) async {
        await run { try await $0.restore(self.serverId, backupId: backup.id) }
    }

    func delete(_ backup: Backup) async {
        await run { try await $0.delete(self.serverId, backupId: backup.id) }
    }

    func toggleLock(_ backup: Backup) async {
        await run { try await $0.setLock(self.serverId, backupId: backup.id, isLocked: !backup.locked) }
    }

    func downloadURL(_ backup: Backup) async -> URL? {
        guard let service else { return nil }
        return try? await service.downloadURL(serverId, backupId: backup.id)
    }

    private func run(_ work: (BackupsService) async throws -> Void) async {
        guard let service else { return }
        actionError = nil
        do { try await work(service); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Action failed. Try again." }
    }
}

struct BackupsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: BackupsViewModel

    @State private var showCreate = false
    @State private var backupName = ""
    @State private var restoreTarget: Backup?

    init(serverId: String) {
        _model = StateObject(wrappedValue: BackupsViewModel(serverId: serverId))
    }

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No backups yet",
            emptyMessage: "Create a snapshot before a risky change so you can roll back.",
            retry: { Task { await model.load() } },
            content: { _ in list },
            skeleton: {
                VStack(spacing: 10) { ForEach(0..<5, id: \.self) { _ in SkeletonBlock(height: 64) } }
                    .padding(16)
            })
        .screenBackground()
        .navigationTitle("Backups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { backupName = ""; showCreate = true } label: {
                    if model.isCreating { ProgressView() } else { Image(systemName: "plus") }
                }
                .disabled(model.isCreating)
            }
        }
        .alert("New backup", isPresented: $showCreate) {
            TextField("Name", text: $backupName)
            Button("Create") { Task { await model.create(name: backupName) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Take a snapshot of this server's files.")
        }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(get: { restoreTarget != nil },
                                 set: { if !$0 { restoreTarget = nil } }),
            titleVisibility: .visible) {
            if let target = restoreTarget {
                Button("Restore", role: .destructive) { Task { await model.restore(target) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This overwrites the server's current files with the backup's contents. The server will be stopped during the restore.")
        }
        .task {
            model.bind(session)
            if model.state.value == nil { await model.load() }
            await poll()
        }
    }

    /// While the screen is visible, refresh every 5s but only when a backup is
    /// queued/in-progress, so completion shows without a manual pull (and a
    /// backup created mid-session is picked up too). Cancelled on disappear.
    private func poll() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { break }
            if model.hasWorkingBackup { await model.refresh() }
        }
    }

    private var list: some View {
        List {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive)
                    .listRowBackground(Color.appCard)
            }
            ForEach(model.backups) { backup in
                BackupRow(backup: backup)
                    .listRowBackground(Color.appCard)
                    .swipeActions(edge: .trailing) {
                        if !backup.locked {
                            Button(role: .destructive) {
                                Task { await model.delete(backup) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                        if backup.state == .completed {
                            Button { restoreTarget = backup } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }.tint(.appWarning)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if backup.state == .completed {
                            Button {
                                Task { if let url = await model.downloadURL(backup) { WebLink.open(url) } }
                            } label: { Label("Download", systemImage: "arrow.down") }
                                .tint(.appPrimary)
                        }
                        Button {
                            Task { await model.toggleLock(backup) }
                        } label: {
                            Label(backup.locked ? "Unlock" : "Lock",
                                  systemImage: backup.locked ? "lock.open" : "lock")
                        }.tint(.appMuted)
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .refreshable { await model.refresh() }
    }
}

struct BackupRow: View {
    let backup: Backup

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(backup.name).foregroundStyle(.appForeground).lineLimit(1)
                    if backup.locked {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.appMuted)
                    }
                }
                HStack(spacing: 8) {
                    if backup.state.isWorking {
                        ProgressView().controlSize(.mini).tint(backup.state.color)
                    }
                    Text(backup.state.label).font(.caption2).foregroundStyle(backup.state.color)
                    if backup.state == .completed {
                        Text("· \(backup.sizeDescription)").font(.caption2).foregroundStyle(.appMuted)
                    }
                    Text("· \(backup.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2).foregroundStyle(.appMuted)
                }
                if backup.state == .failed, let error = backup.error {
                    Text(error).font(.caption2).foregroundStyle(.appDestructive).lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
