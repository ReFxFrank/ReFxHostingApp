import SwiftUI

/// Hub for support configuration: canned responses, KB articles, categories.
struct SupportSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                NavigationLink { CannedResponsesView() } label: {
                    ManageRow(icon: "text.badge.plus", title: "Canned responses", subtitle: "Reusable ticket replies")
                }.buttonStyle(.plain)
                NavigationLink { KbArticlesView() } label: {
                    ManageRow(icon: "book", title: "Knowledge base", subtitle: "Author help articles")
                }.buttonStyle(.plain)
                NavigationLink { TicketCategoriesView() } label: {
                    ManageRow(icon: "tag", title: "Ticket categories", subtitle: "Categories & SLA targets")
                }.buttonStyle(.plain)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Support settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Canned responses

@MainActor
final class CannedResponsesViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[CannedResponse]> = .idle
    @Published var actionError: String?
    private var service: StaffService?
    func bind(_ s: AppSession) { if service == nil { service = s.staff } }
    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.cannedResponses()) }
        catch let e as APIError { state = .failed(e) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }
    func create(_ b: CannedResponseBody) async -> Bool { await mutate { try await $0.createCannedResponse(b) } }
    func update(_ id: String, _ b: CannedResponseBody) async -> Bool { await mutate { try await $0.updateCannedResponse(id, b) } }
    func delete(_ r: CannedResponse) async { _ = await mutate { try await $0.deleteCannedResponse(r.id) } }
    @discardableResult private func mutate(_ work: (StaffService) async throws -> Void) async -> Bool {
        guard let service else { return false }
        actionError = nil
        do { try await work(service); await load(); return true }
        catch let e as APIError { actionError = e.userMessage; return false }
        catch { actionError = "Action failed. Try again."; return false }
    }
}

struct CannedResponsesView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = CannedResponsesViewModel()
    @State private var showCreate = false
    @State private var editing: CannedResponse?

    var body: some View {
        ScrollView {
            AsyncStateView(state: model.state, isEmpty: { $0.isEmpty },
                emptyTitle: "No canned responses", emptyMessage: "Add reusable replies for tickets.",
                retry: { Task { await model.load() } }, content: { list($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 72) } } })
            .padding(16)
        }
        .screenBackground().navigationTitle("Canned responses").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showCreate = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showCreate) { CannedEditSheet(title: "New response") { await model.create($0) } }
        .sheet(item: $editing) { r in CannedEditSheet(title: "Edit response", response: r) { await model.update(r.id, $0) } }
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }
    private func list(_ items: [CannedResponse]) -> some View {
        VStack(spacing: 12) {
            if let e = model.actionError { Text(e).font(.footnote).foregroundStyle(.appDestructive).frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(items) { r in
                GlassCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.title).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                        Text(r.body).font(.caption).foregroundStyle(.appMuted).lineLimit(2)
                        if !r.tags.isEmpty { Text(r.tags.joined(separator: ", ")).font(.caption2).foregroundStyle(.appPrimary) }
                    }
                }
                .contextMenu {
                    Button { editing = r } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { Task { await model.delete(r) } } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }
}

private struct CannedEditSheet: View {
    let title: String
    var response: CannedResponse?
    let onSave: (CannedResponseBody) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var t = ""; @State private var b = ""; @State private var tags = ""; @State private var saving = false
    private var canSave: Bool { !t.trimmed.isEmpty && !b.trimmed.isEmpty && !saving }
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Title", text: $t); TextField("Body", text: $b, axis: .vertical).lineLimit(3...8)
                    TextField("Tags (comma-separated)", text: $tags).textInputAutocapitalization(.never).autocorrectionDisabled()
                }.listRowBackground(Color.appCard)
                Section { saveButton }
            }
            .scrollContentBackground(.hidden).screenBackground().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { if let r = response { t = r.title; b = r.body; tags = r.tags.joined(separator: ", ") } }
        }
    }
    private var saveButton: some View {
        Button {
            saving = true
            Task {
                let parsed = tags.split(separator: ",").map { $0.trimmed }.filter { !$0.isEmpty }
                let ok = await onSave(CannedResponseBody(title: t.trimmed, body: b.trimmed, tags: parsed))
                saving = false; if ok { dismiss() }
            }
        } label: { HStack { if saving { ProgressView() }; Text("Save") } }
        .buttonStyle(.refxPrimary).disabled(!canSave).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
    }
}

// MARK: - KB articles

@MainActor
final class KbArticlesViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[KbArticle]> = .idle
    @Published var actionError: String?
    private var service: StaffService?
    func bind(_ s: AppSession) { if service == nil { service = s.staff } }
    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.kbArticles()) }
        catch let e as APIError { state = .failed(e) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }
    func create(_ b: CreateKbArticleBody) async -> Bool { await mutate { try await $0.createKbArticle(b) } }
    func update(_ slug: String, _ b: UpdateKbArticleBody) async -> Bool { await mutate { try await $0.updateKbArticle(slug, b) } }
    @discardableResult private func mutate(_ work: (StaffService) async throws -> Void) async -> Bool {
        guard let service else { return false }
        actionError = nil
        do { try await work(service); await load(); return true }
        catch let e as APIError { actionError = e.userMessage; return false }
        catch { actionError = "Action failed. Try again."; return false }
    }
}

struct KbArticlesView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = KbArticlesViewModel()
    @State private var showCreate = false
    @State private var editing: KbArticle?

    var body: some View {
        ScrollView {
            AsyncStateView(state: model.state, isEmpty: { $0.isEmpty },
                emptyTitle: "No articles", emptyMessage: "Write help-center articles for customers.",
                retry: { Task { await model.load() } }, content: { list($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 72) } } })
            .padding(16)
        }
        .screenBackground().navigationTitle("Knowledge base").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showCreate = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showCreate) { KbEditSheet(title: "New article", onCreate: { await model.create($0) }, onUpdate: nil) }
        .sheet(item: $editing) { a in KbEditSheet(title: "Edit article", article: a, onCreate: nil, onUpdate: { await model.update(a.slug, $0) }) }
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }
    private func list(_ items: [KbArticle]) -> some View {
        VStack(spacing: 12) {
            if let e = model.actionError { Text(e).font(.footnote).foregroundStyle(.appDestructive).frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(items) { a in
                GlassCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(a.title).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground).lineLimit(1)
                            Spacer()
                            StatusChip(text: a.isPublished ? "Published" : "Draft", color: a.isPublished ? .appSuccess : .appMuted)
                        }
                        Text(a.slug).font(.caption2.monospaced()).foregroundStyle(.appMuted)
                        if let c = a.category { Text(c).font(.caption2).foregroundStyle(.appPrimary) }
                    }
                }
                .contextMenu { Button { editing = a } label: { Label("Edit", systemImage: "pencil") } }
            }
        }
    }
}

private struct KbEditSheet: View {
    let title: String
    var article: KbArticle?
    let onCreate: ((CreateKbArticleBody) async -> Bool)?
    let onUpdate: ((UpdateKbArticleBody) async -> Bool)?
    @Environment(\.dismiss) private var dismiss
    @State private var slug = ""; @State private var t = ""; @State private var b = ""
    @State private var category = ""; @State private var published = false; @State private var saving = false
    private var isEditing: Bool { article != nil }
    private var canSave: Bool { !slug.trimmed.isEmpty && !t.trimmed.isEmpty && !b.trimmed.isEmpty && !saving }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Slug (lowercase-with-dashes)", text: $slug).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Title", text: $t)
                    TextField("Category", text: $category)
                    TextField("Body (markdown)", text: $b, axis: .vertical).lineLimit(5...15)
                    Toggle("Published", isOn: $published).tint(.appPrimary)
                }.listRowBackground(Color.appCard)
                Section { saveButton }
            }
            .scrollContentBackground(.hidden).screenBackground().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { if let a = article { slug = a.slug; t = a.title; b = a.body; category = a.category ?? ""; published = a.isPublished } }
        }
    }
    private var saveButton: some View {
        Button {
            saving = true
            Task {
                let cat = category.trimmed.isEmpty ? nil : category.trimmed
                let ok: Bool
                if isEditing, let onUpdate {
                    ok = await onUpdate(UpdateKbArticleBody(slug: slug.trimmed, title: t.trimmed, body: b.trimmed, category: cat, isPublished: published))
                } else if let onCreate {
                    ok = await onCreate(CreateKbArticleBody(slug: slug.trimmed, title: t.trimmed, body: b.trimmed, category: cat, isPublished: published))
                } else { ok = false }
                saving = false; if ok { dismiss() }
            }
        } label: { HStack { if saving { ProgressView() }; Text("Save") } }
        .buttonStyle(.refxPrimary).disabled(!canSave).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
    }
}

// MARK: - Ticket categories

@MainActor
final class TicketCategoriesViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[TicketCategory]> = .idle
    @Published var actionError: String?
    private var service: StaffService?
    func bind(_ s: AppSession) { if service == nil { service = s.staff } }
    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.ticketCategories()) }
        catch let e as APIError { state = .failed(e) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }
    func create(_ b: CreateCategoryBody) async -> Bool { await mutate { try await $0.createCategory(b) } }
    func update(_ id: String, _ b: UpdateCategoryBody) async -> Bool { await mutate { try await $0.updateCategory(id, b) } }
    func delete(_ c: TicketCategory) async { _ = await mutate { try await $0.deleteCategory(c.id) } }
    @discardableResult private func mutate(_ work: (StaffService) async throws -> Void) async -> Bool {
        guard let service else { return false }
        actionError = nil
        do { try await work(service); await load(); return true }
        catch let e as APIError { actionError = e.userMessage; return false }
        catch { actionError = "Action failed. Try again."; return false }
    }
}

struct TicketCategoriesView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = TicketCategoriesViewModel()
    @State private var showCreate = false
    @State private var editing: TicketCategory?

    var body: some View {
        ScrollView {
            AsyncStateView(state: model.state, isEmpty: { $0.isEmpty },
                emptyTitle: "No categories", emptyMessage: "Add ticket categories with SLA targets.",
                retry: { Task { await model.load() } }, content: { list($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 64) } } })
            .padding(16)
        }
        .screenBackground().navigationTitle("Ticket categories").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showCreate = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showCreate) { CategoryEditSheet(title: "New category") { await model.create($0) } }
        .sheet(item: $editing) { c in CategoryEditSheet(title: "Edit category", category: c) { body in
            await model.update(c.id, UpdateCategoryBody(name: body.name, slug: body.slug, slaFirstResponseMin: body.slaFirstResponseMin, slaResolutionMin: body.slaResolutionMin)) } }
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }
    private func list(_ items: [TicketCategory]) -> some View {
        VStack(spacing: 12) {
            if let e = model.actionError { Text(e).font(.footnote).foregroundStyle(.appDestructive).frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(items) { c in
                GlassCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                            Text("first \(c.slaFirstResponseMin)m · resolve \(c.slaResolutionMin)m").font(.caption2).foregroundStyle(.appMuted)
                        }
                        Spacer()
                        StatusChip(text: c.slug, color: .appPrimary)
                    }
                }
                .contextMenu {
                    Button { editing = c } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { Task { await model.delete(c) } } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }
}

private struct CategoryEditSheet: View {
    let title: String
    var category: TicketCategory?
    let onSave: (CreateCategoryBody) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var slug = ""
    @State private var firstMin = "240"; @State private var resolveMin = "2880"; @State private var saving = false
    private var canSave: Bool { !name.trimmed.isEmpty && !slug.trimmed.isEmpty && !saving }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Slug (lowercase-with-dashes)", text: $slug).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("First-response SLA (min)", text: $firstMin).keyboardType(.numberPad)
                    TextField("Resolution SLA (min)", text: $resolveMin).keyboardType(.numberPad)
                }.listRowBackground(Color.appCard)
                Section {
                    Button {
                        saving = true
                        Task {
                            let ok = await onSave(CreateCategoryBody(name: name.trimmed, slug: slug.trimmed,
                                slaFirstResponseMin: Int(firstMin), slaResolutionMin: Int(resolveMin)))
                            saving = false; if ok { dismiss() }
                        }
                    } label: { HStack { if saving { ProgressView() }; Text("Save") } }
                    .buttonStyle(.refxPrimary).disabled(!canSave).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden).screenBackground().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { if let c = category { name = c.name; slug = c.slug; firstMin = String(c.slaFirstResponseMin); resolveMin = String(c.slaResolutionMin) } }
        }
    }
}
