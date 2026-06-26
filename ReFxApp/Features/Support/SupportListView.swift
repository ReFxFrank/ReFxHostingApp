import SwiftUI

@MainActor
final class SupportListViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[Ticket]> = .idle
    private var service: SupportService?

    func bind(_ session: AppSession) { if service == nil { service = session.support } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.tickets().items) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func refresh() async {
        guard let service else { return }
        if let page = try? await service.tickets() { state = .loaded(page.items) }
    }
}

/// Support tab: the customer's tickets, with create + thread/reply.
struct SupportListView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var pushRouter: PushRouter
    @StateObject private var model = SupportListViewModel()
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No tickets",
                emptyMessage: "Need help? Open a ticket and our team will respond.",
                retry: { Task { await model.load() } },
                content: { _ in list },
                skeleton: { VStack(spacing: 10) { ForEach(0..<5, id: \.self) { _ in SkeletonBlock(height: 64) } }.padding(16) })
            .screenBackground()
            .navigationTitle("Support")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New ticket")
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateTicketView { await model.refresh() }
            }
            .navigationDestination(isPresented: Binding(
                get: { pushRouter.ticketId != nil },
                set: { if !$0 { pushRouter.ticketId = nil } })) {
                if let id = pushRouter.ticketId { TicketDetailView(ticketId: id, subject: "Ticket") }
            }
            .task { model.bind(session); if model.state.value == nil { await model.load() } }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(model.state.value ?? []) { ticket in
                    NavigationLink {
                        TicketDetailView(ticketId: ticket.id, subject: ticket.subject)
                    } label: { TicketRow(ticket: ticket) }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .refreshable { await model.refresh() }
    }
}

struct TicketRow: View {
    let ticket: Ticket
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(ticket.number)").font(.caption.monospaced()).foregroundStyle(.appMuted)
                Spacer()
                StatusChip(text: ticket.state.label, color: ticket.state.color)
            }
            Text(ticket.subject).font(.subheadline.weight(.semibold))
                .foregroundStyle(.appForeground).lineLimit(2)
            HStack(spacing: 8) {
                if ticket.priority == .high || ticket.priority == .urgent {
                    StatusChip(text: ticket.priority.label, color: ticket.priority.color)
                }
                Spacer()
                Text(ticket.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption2).foregroundStyle(.appMuted)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ticket \(ticket.number), \(ticket.subject), \(ticket.state.label)")
    }
}

struct StatusChip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold)).tracking(0.7)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(color.opacity(0.14))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

/// Generic "coming soon" placeholder, shared by the not-yet-native server
/// section stubs. (Kept here to remain available app-wide.)
struct ComingSoonView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.appPrimary)
                .frame(width: 84, height: 84)
                .cardSurface(elevated: true, glow: true)
            Text(title).font(.title2.bold()).foregroundStyle(.appForegroundStrong)
            Text(message).font(.subheadline).foregroundStyle(.appMuted)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.refxPrimary(fullWidth: false))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .screenBackground()
    }
}
