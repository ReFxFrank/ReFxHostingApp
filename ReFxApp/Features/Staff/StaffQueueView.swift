import SwiftUI

@MainActor
final class StaffQueueViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[Ticket]> = .idle
    @Published var filter: TicketState = .open

    private var service: SupportService?

    func bind(_ session: AppSession) { if service == nil { service = session.support } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.tickets(state: filter == .unknown ? nil : filter).items) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func refresh() async {
        guard let service else { return }
        if let page = try? await service.tickets(state: filter == .unknown ? nil : filter) {
            state = .loaded(page.items)
        }
    }
}

/// Staff ticket queue: all tickets, filterable by status; opens the shared
/// ticket thread (which surfaces staff workflow actions).
struct StaffQueueView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = StaffQueueViewModel()

    private let filters: [TicketState] = [.open, .pendingAgent, .pendingCustomer, .resolved]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $model.filter) {
                Text("Open").tag(TicketState.open)
                Text("Agent").tag(TicketState.pendingAgent)
                Text("Customer").tag(TicketState.pendingCustomer)
                Text("Resolved").tag(TicketState.resolved)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 10)

            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "Nothing here",
                emptyMessage: "No tickets in this status.",
                retry: { Task { await model.load() } },
                content: { _ in list },
                skeleton: { VStack(spacing: 10) { ForEach(0..<6, id: \.self) { _ in SkeletonBlock(height: 64) } }.padding(16) })
        }
        .screenBackground()
        .navigationTitle("Support queue")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.filter) { _ in Task { await model.load() } }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
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
            .readableWidth()
        }
        .refreshable { await model.refresh() }
    }
}
