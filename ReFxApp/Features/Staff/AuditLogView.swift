import SwiftUI

@MainActor
final class AuditLogViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[AuditEntry]> = .idle
    @Published private(set) var hasMore = true
    private var service: StaffService?
    private var page = 1
    private var isLoadingMore = false

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        page = 1
        if state.value == nil { state = .loading }
        do {
            let result = try await service.auditLogs(page: 1)
            hasMore = result.items.count >= 40
            state = .loaded(result.items)
        } catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func refresh() async { await load() }

    func loadMoreIfNeeded(current item: AuditEntry) async {
        guard let service, hasMore, !isLoadingMore,
              let items = state.value, item.id == items.last?.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        page += 1
        if let result = try? await service.auditLogs(page: page) {
            hasMore = result.items.count >= 40
            state = .loaded((state.value ?? []) + result.items)
        } else {
            hasMore = false
        }
    }
}

/// Read-only feed of recent staff & system actions (admin audit log).
struct AuditLogView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = AuditLogViewModel()

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No audit entries",
                emptyMessage: "Staff and system actions will appear here.",
                retry: { Task { await model.load() } },
                content: { list($0) },
                skeleton: { skeleton })
            .padding(16)
            .readableWidth()
        }
        .screenBackground()
        .navigationTitle("Audit log")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private func list(_ entries: [AuditEntry]) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(entries) { entry in
                AuditRow(entry: entry)
                    .task { await model.loadMoreIfNeeded(current: entry) }
            }
            if model.hasMore {
                ProgressView().tint(.appPrimary).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
        }
    }

    private var skeleton: some View {
        VStack(spacing: 10) { ForEach(0..<8, id: \.self) { _ in SkeletonBlock(height: 56) } }
    }
}

private struct AuditRow: View {
    let entry: AuditEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.appPrimary).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.action).font(.caption.monospaced()).foregroundStyle(.appForeground).lineLimit(1)
                if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(.appMuted).lineLimit(1) }
            }
            Spacer(minLength: 8)
            Text(entry.createdAt.formatted(.relative(presentation: .named)))
                .font(.caption2.monospacedDigit()).foregroundStyle(.appMuted)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.action), \(subtitle ?? "")")
    }

    private var subtitle: String? {
        guard let targetType = entry.targetType else { return entry.ip }
        if let id = entry.targetId, !id.isEmpty { return "\(targetType) · \(id.prefix(8))" }
        return targetType
    }

    private var icon: String {
        switch entry.domain {
        case "server": return "server.rack"
        case "user": return "person"
        case "node": return "externaldrive.connected.to.line.below"
        case "auth": return "key"
        case "billing", "invoice", "coupon", "giftcard", "order", "payment": return "creditcard"
        case "alert", "content": return "megaphone"
        case "role", "settings": return "gearshape"
        default: return "bolt"
        }
    }
}
