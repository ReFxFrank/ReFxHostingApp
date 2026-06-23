import SwiftUI

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[AppNotification]> = .idle
    private var service: AccountService?
    private weak var session: AppSession?

    func bind(_ session: AppSession) {
        self.session = session
        if service == nil { service = session.account }
    }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await service.notifications())
        } catch let error as APIError {
            state = .failed(error)
        } catch {
            state = .failed(.network(isOffline: false, underlying: error.localizedDescription))
        }
    }

    func markRead(_ item: AppNotification) async {
        guard let service, item.isUnread else { return }
        try? await service.markRead(item.id)
        await load()
        await session?.refreshUnreadCount()
    }

    func markAllRead() async {
        guard let service else { return }
        try? await service.markAllRead()
        await load()
        await session?.refreshUnreadCount()
    }
}

struct NotificationsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = NotificationsViewModel()

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "You're all caught up",
            emptyMessage: "Notifications about your servers and tickets appear here.",
            retry: { Task { await model.load() } },
            content: { items in list(items) },
            skeleton: { skeleton })
        .screenBackground()
        .navigationTitle("Notifications")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark all read") { Task { await model.markAllRead() } }
            }
        }
        .task {
            model.bind(session)
            await model.load()
        }
    }

    private func list(_ items: [AppNotification]) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    NotificationRow(item: item)
                        .onTapGesture { Task { await model.markRead(item) } }
                }
            }
            .padding(16)
        }
        .refreshable { await model.load() }
    }

    private var skeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { _ in SkeletonBlock(height: 56) }
        }.padding(16)
    }
}

struct NotificationRow: View {
    let item: AppNotification
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(item.isUnread ? Color.appPrimary : Color.clear)
                .frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.appForeground)
                Text(item.body).font(.caption).foregroundStyle(.appMuted)
                Text(item.createdAt, style: .relative)
                    .font(.caption2).foregroundStyle(.appMuted)
            }
            Spacer()
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(elevated: item.isUnread)
    }
}
