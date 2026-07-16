import SwiftUI

@MainActor
final class BugTriageViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[BugReport]> = .idle
    @Published var searchText = ""
    @Published var statusFilter: BugStatus?
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await service.bugs(
                status: statusFilter,
                query: searchText.isEmpty ? nil : searchText).items)
        }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }
}

struct BugTriageView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = BugTriageViewModel()

    private let filters: [BugStatus?] = [nil, .new, .triaged, .inProgress, .resolved, .closed]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters, id: \.self) { status in
                        let selected = model.statusFilter == status
                        Button {
                            model.statusFilter = status
                            Task { await model.load() }
                        } label: {
                            Text(status?.label ?? "All")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(selected ? Color.appPrimary.opacity(0.2) : Color.appCard)
                                .foregroundStyle(selected ? .appAccentText : .appMuted)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No bug reports",
                emptyMessage: "Nothing matches this filter.",
                retry: { Task { await model.load() } },
                content: { _ in list },
                skeleton: { VStack(spacing: 10) { ForEach(0..<5, id: \.self) { _ in SkeletonBlock(height: 72) } }.padding(16) })
        }
        .screenBackground()
        .navigationTitle("Bug triage")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.searchText, prompt: "Search bugs")
        .onSubmit(of: .search) { Task { await model.load() } }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private var list: some View {
        List {
            ForEach(model.state.value ?? []) { bug in
                NavigationLink { BugDetailView(bugId: bug.id, preview: bug) } label: { BugRow(bug: bug) }
                    .listRowBackground(Color.appCard)
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).screenBackground()
        .refreshable { await model.load() }
    }
}

struct BugRow: View {
    let bug: BugReport
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(bug.ref).font(.caption2.monospaced()).foregroundStyle(.appMuted)
                StatusChip(text: bug.severity.label, color: bug.severity.color)
                StatusChip(text: bug.status.label, color: bug.status.color)
                Spacer()
            }
            Text(bug.title).foregroundStyle(.appForeground).lineLimit(2)
            HStack(spacing: 8) {
                if let reporter = bug.reporter {
                    Text(reporter.displayName).font(.caption2).foregroundStyle(.appMuted)
                }
                if let server = bug.server {
                    Text("· \(server.name)").font(.caption2).foregroundStyle(.appMuted)
                }
                Spacer()
                Text(bug.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption2).foregroundStyle(.appMuted)
            }
        }
        .padding(.vertical, 4)
    }
}
