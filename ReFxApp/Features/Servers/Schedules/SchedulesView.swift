import SwiftUI

@MainActor
final class SchedulesViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[Schedule]> = .idle
    @Published var actionError: String?

    let serverId: String
    private var service: SchedulesService?

    init(serverId: String) { self.serverId = serverId }

    func bind(_ session: AppSession) { if service == nil { service = session.schedules } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.list(serverId)) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func toggle(_ schedule: Schedule) async {
        await run { try await $0.setActive(self.serverId, scheduleId: schedule.id, isActive: !schedule.isActive) }
    }

    func run(_ schedule: Schedule) async {
        await run { try await $0.run(self.serverId, scheduleId: schedule.id) }
    }

    func delete(_ schedule: Schedule) async {
        await run { try await $0.delete(self.serverId, scheduleId: schedule.id) }
    }

    func create(name: String, cron: String, onlyWhenOnline: Bool,
                action: ScheduleAction, payload: String) async {
        await run {
            try await $0.create(self.serverId, name: name, cron: cron,
                                 onlyWhenOnline: onlyWhenOnline, action: action, payload: payload)
        }
    }

    private func run(_ work: (SchedulesService) async throws -> Void) async {
        guard let service else { return }
        actionError = nil
        do { try await work(service); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Action failed. Try again." }
    }
}

struct SchedulesView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: SchedulesViewModel
    @State private var showCreate = false

    init(serverId: String) { _model = StateObject(wrappedValue: SchedulesViewModel(serverId: serverId)) }

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No schedules",
            emptyMessage: "Automate restarts, commands or backups on a cron schedule.",
            retry: { Task { await model.load() } },
            content: { _ in list },
            skeleton: { VStack(spacing: 10) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 70) } }.padding(16) })
        .screenBackground()
        .navigationTitle("Schedules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateScheduleSheet { name, cron, online, action, payload in
                Task { await model.create(name: name, cron: cron, onlyWhenOnline: online, action: action, payload: payload) }
            }
        }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private var list: some View {
        List {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive).listRowBackground(Color.appCard)
            }
            ForEach(model.state.value ?? []) { schedule in
                ScheduleRow(schedule: schedule, toggle: { Task { await model.toggle(schedule) } })
                    .listRowBackground(Color.appCard)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await model.delete(schedule) } } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { Task { await model.run(schedule) } } label: {
                            Label("Run", systemImage: "play.fill")
                        }.tint(.appPrimary)
                    }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(Color.appBackground)
        .refreshable { await model.load() }
    }
}

struct ScheduleRow: View {
    let schedule: Schedule
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(schedule.name).foregroundStyle(.appForeground)
                Text(schedule.cron).font(.caption.monospaced()).foregroundStyle(.appPrimary)
                Text(schedule.taskSummary).font(.caption2).foregroundStyle(.appMuted).lineLimit(1)
                if let next = schedule.nextRunAt {
                    Text("Next: \(next.formatted(.relative(presentation: .named)))")
                        .font(.caption2).foregroundStyle(.appMuted)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { schedule.isActive }, set: { _ in toggle() }))
                .labelsHidden().tint(.appPrimary)
        }
        .padding(.vertical, 4)
    }
}

struct CreateScheduleSheet: View {
    let onCreate: (String, String, Bool, ScheduleAction, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var cron = "0 */6 * * *"
    @State private var onlyWhenOnline = false
    @State private var action: ScheduleAction = .power
    @State private var payload = "restart"

    var body: some View {
        NavigationStack {
            Form {
                Section("Schedule") {
                    TextField("Name", text: $name)
                    TextField("Cron (5 fields)", text: $cron)
                        .font(.callout.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Only when online", isOn: $onlyWhenOnline)
                }
                Section("Task") {
                    Picker("Action", selection: $action) {
                        Text("Power").tag(ScheduleAction.power)
                        Text("Command").tag(ScheduleAction.command)
                        Text("Backup").tag(ScheduleAction.backup)
                    }
                    TextField(payloadHint, text: $payload)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: {
                    Text(payloadHint)
                }
            }
            .scrollContentBackground(.hidden).background(Color.appBackground)
            .navigationTitle("New schedule").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(name, cron, onlyWhenOnline, action, payload); dismiss()
                    }.disabled(name.isEmpty || cron.isEmpty)
                }
            }
        }
    }

    private var payloadHint: String {
        switch action {
        case .power: return "start, stop, restart or kill"
        case .command: return "Console command to run"
        case .backup: return "Backup name"
        case .unknown: return "Payload"
        }
    }
}
