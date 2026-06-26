import SwiftUI

@MainActor
final class TicketDetailViewModel: ObservableObject {
    @Published private(set) var state: LoadState<TicketDetail> = .idle
    @Published var draft = ""
    @Published private(set) var isSending = false
    @Published var actionError: String?

    let ticketId: String
    private var service: SupportService?

    init(ticketId: String) { self.ticketId = ticketId }

    func bind(_ session: AppSession) { if service == nil { service = session.support } }

    /// Customers never see internal staff notes; hide them defensively too.
    var visibleMessages: [TicketMessage] {
        (state.value?.messages ?? []).filter { $0.isInternal != true }
    }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.ticket(ticketId)) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func send() async {
        guard let service else { return }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        actionError = nil
        isSending = true
        defer { isSending = false }
        do {
            try await service.reply(ticketId, body: body)
            draft = ""
            await load()
        } catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't send your reply." }
    }

    // MARK: Staff actions

    func setState(_ newState: TicketState) async {
        await staffRun { try await $0.update(self.ticketId, state: newState) }
    }

    func setPriority(_ priority: TicketPriority) async {
        await staffRun { try await $0.update(self.ticketId, priority: priority) }
    }

    func assign(to userId: String) async {
        await staffRun { try await $0.assign(self.ticketId, assigneeId: userId) }
    }

    private func staffRun(_ work: (SupportService) async throws -> Void) async {
        guard let service else { return }
        actionError = nil
        do { try await work(service); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Action failed. Try again." }
    }
}

struct TicketDetailView: View {
    let ticketId: String
    let subject: String
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: TicketDetailViewModel

    init(ticketId: String, subject: String) {
        self.ticketId = ticketId
        self.subject = subject
        _model = StateObject(wrappedValue: TicketDetailViewModel(ticketId: ticketId))
    }

    var body: some View {
        VStack(spacing: 0) {
            AsyncStateView(
                state: model.state,
                isEmpty: { _ in false },
                retry: { Task { await model.load() } },
                content: { detail in thread(detail) },
                skeleton: { VStack(spacing: 10) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 70) } }.padding(16) })
            replyBar
        }
        .screenBackground()
        .navigationTitle(subject)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.currentUser?.globalRole.isStaff == true {
                ToolbarItem(placement: .topBarTrailing) { staffMenu }
            }
        }
        .task { model.bind(session); await model.load() }
    }

    private var staffMenu: some View {
        Menu {
            Section("Set status") {
                Button("Open") { Task { await model.setState(.open) } }
                Button("Awaiting customer") { Task { await model.setState(.pendingCustomer) } }
                Button("Resolved") { Task { await model.setState(.resolved) } }
                Button("Closed") { Task { await model.setState(.closed) } }
            }
            Section("Priority") {
                Button("Low") { Task { await model.setPriority(.low) } }
                Button("Normal") { Task { await model.setPriority(.normal) } }
                Button("High") { Task { await model.setPriority(.high) } }
                Button("Urgent") { Task { await model.setPriority(.urgent) } }
            }
            if let myId = session.currentUser?.id {
                Button { Task { await model.assign(to: myId) } } label: {
                    Label("Assign to me", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Ticket actions")
    }

    private func thread(_ detail: TicketDetail) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        StatusChip(text: detail.state.label, color: detail.state.color)
                        Text("#\(detail.number)").font(.caption.monospaced()).foregroundStyle(.appMuted)
                        Spacer()
                    }
                    ForEach(model.visibleMessages) { message in
                        MessageBubble(message: message).id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
                .readableWidth()
            }
            .onChange(of: model.visibleMessages.count) { _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var replyBar: some View {
        VStack(spacing: 4) {
            if let error = model.actionError {
                Text(error).font(.caption).foregroundStyle(.appDestructive)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
            }
            HStack(spacing: 10) {
                TextField("Reply…", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .foregroundStyle(.appForeground)
                Button { Task { await model.send() } } label: {
                    if model.isSending { ProgressView() }
                    else { Image(systemName: "paperplane.fill") }
                }
                .disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty || model.isSending)
                .foregroundStyle(.appPrimary)
            }
            .padding(12)
        }
        .background(Color.appCard)
        .overlay(Rectangle().fill(Color.appBorder).frame(height: 1), alignment: .top)
    }
}

struct MessageBubble: View {
    let message: TicketMessage

    private var fromStaff: Bool { message.author?.isStaff ?? false }

    var body: some View {
        HStack {
            if fromStaff { Spacer(minLength: 24) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(message.author?.displayName ?? "User")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(fromStaff ? .appPrimary : .appForeground)
                    if fromStaff {
                        Text("Support").font(.caption2).foregroundStyle(.appMuted)
                    }
                }
                Text(message.body).font(.callout).foregroundStyle(.appForeground)
                    .textSelection(.enabled)
                Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.appMuted)
            }
            .padding(12)
            .background(fromStaff ? Color.appPrimary.opacity(0.12) : Color.appCard)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appBorder))
            if !fromStaff { Spacer(minLength: 24) }
        }
    }
}
