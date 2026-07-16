import SwiftUI

@MainActor
final class BugDetailViewModel: ObservableObject {
    @Published var state: LoadState<BugReport>
    @Published var staff: [BugUserRef] = []
    @Published var actionError: String?
    @Published var commentText = ""
    @Published var commentInternal = true
    @Published var isPosting = false

    let bugId: String
    private var service: StaffService?

    init(bugId: String, preview: BugReport?) {
        self.bugId = bugId
        self.state = preview.map { .loaded($0) } ?? .idle
    }

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.bug(bugId)) }
        catch let error as APIError { if state.value == nil { state = .failed(error) } }
        catch { if state.value == nil { state = .failed(.network(isOffline: false, underlying: "\(error)")) } }
        if staff.isEmpty { staff = (try? await service.bugStaff()) ?? [] }
    }

    func setStatus(_ status: BugStatus) async { await run { try await $0.updateBug(self.bugId, UpdateBugBody(status: status.rawValue)) } }
    func setSeverity(_ severity: BugSeverity) async { await run { try await $0.updateBug(self.bugId, UpdateBugBody(severity: severity.rawValue)) } }
    func assign(_ user: BugUserRef?) async { await run { try await $0.assignBug(self.bugId, assigneeId: user?.id) } }

    private func run(_ work: (StaffService) async throws -> BugReport) async {
        guard let service else { return }
        actionError = nil
        do { state = .loaded(try await work(service)); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't update the report." }
    }

    func postComment() async {
        guard let service, !commentText.trimmed.isEmpty, !isPosting else { return }
        isPosting = true; actionError = nil
        defer { isPosting = false }
        do {
            try await service.addBugComment(bugId, body: commentText.trimmed, isInternal: commentInternal)
            commentText = ""
            await load()
        } catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't post the comment." }
    }
}

struct BugDetailView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: BugDetailViewModel

    init(bugId: String, preview: BugReport?) {
        _model = StateObject(wrappedValue: BugDetailViewModel(bugId: bugId, preview: preview))
    }

    var body: some View {
        ScrollView {
            if let bug = model.state.value {
                content(bug)
            } else {
                SkeletonBlock(height: 300).padding(16)
            }
        }
        .screenBackground()
        .navigationTitle(model.state.value?.ref ?? "Bug")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.bind(session); await model.load() }
    }

    private func content(_ bug: BugReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(bug.title).font(.headline).foregroundStyle(.appForeground)
                    Text(bug.description).font(.callout).foregroundStyle(.appMuted)
                    if let steps = bug.stepsToReproduce, !steps.isEmpty {
                        Text("Steps to reproduce").font(.caption.weight(.semibold)).foregroundStyle(.appForeground)
                        Text(steps).font(.caption).foregroundStyle(.appMuted)
                    }
                    HStack(spacing: 8) {
                        if let server = bug.server { Label(server.name, systemImage: "server.rack").font(.caption2).foregroundStyle(.appMuted) }
                        if let v = bug.appVersion { Text("· v\(v)").font(.caption2).foregroundStyle(.appMuted) }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Triage", systemImage: "slider.horizontal.3")
                    Picker("Status", selection: Binding(
                        get: { bug.status }, set: { s in Task { await model.setStatus(s) } })) {
                        ForEach(BugStatus.allCases.filter { $0 != .unknown }) { Text($0.label).tag($0) }
                    }
                    Picker("Severity", selection: Binding(
                        get: { bug.severity }, set: { s in Task { await model.setSeverity(s) } })) {
                        ForEach(BugSeverity.allCases.filter { $0 != .unknown }) { Text($0.label).tag($0) }
                    }
                    Picker("Assignee", selection: Binding(
                        get: { bug.assigneeId ?? "" },
                        set: { id in Task { await model.assign(model.staff.first { $0.id == id }) } })) {
                        Text("Unassigned").tag("")
                        ForEach(model.staff, id: \.id) { Text($0.displayName).tag($0.id) }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Comments", systemImage: "text.bubble")
                    ForEach(bug.comments ?? []) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(c.author?.displayName ?? "Unknown").font(.caption.weight(.semibold)).foregroundStyle(.appForeground)
                                if c.isInternal { StatusChip(text: "Internal", color: .appWarning) }
                                Spacer()
                                Text(c.createdAt.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.appMuted)
                            }
                            Text(c.body).font(.caption).foregroundStyle(.appMuted)
                        }
                        Divider()
                    }
                    if (bug.comments ?? []).isEmpty {
                        Text("No comments yet.").font(.caption).foregroundStyle(.appMuted)
                    }
                    TextField("Add a comment…", text: $model.commentText, axis: .vertical).lineLimit(1...4)
                    Toggle("Internal note", isOn: $model.commentInternal).tint(.appPrimary).font(.caption)
                    Button { Task { await model.postComment() } } label: {
                        HStack { if model.isPosting { ProgressView() }; Text("Post comment") }
                    }
                    .buttonStyle(.refxSecondary)
                    .disabled(model.commentText.trimmed.isEmpty || model.isPosting)
                }
            }
        }
        .padding(16)
    }
}
