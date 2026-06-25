import SwiftUI

@MainActor
final class AdminTemplatesViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[AdminGameTemplate]> = .idle
    @Published var actionError: String?
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.templates()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func setFlags(_ template: AdminGameTemplate, published: Bool? = nil, featured: Bool? = nil) async {
        await mutate { try await $0.updateTemplate(template.id, .init(isPublished: published, featured: featured)) }
    }
    func saveBasics(_ template: AdminGameTemplate, name: String, author: String,
                    description: String, tags: [String]) async -> Bool {
        await mutate { try await $0.updateTemplate(template.id, .init(
            name: name, author: author,
            description: description.isEmpty ? nil : description, tags: tags)) }
    }
    func delete(_ template: AdminGameTemplate) async {
        _ = await mutate { try await $0.deleteTemplate(template.id) }
    }

    @discardableResult
    private func mutate(_ work: (StaffService) async throws -> Void) async -> Bool {
        guard let service else { return false }
        actionError = nil
        do { try await work(service); await load(); return true }
        catch let error as APIError { actionError = error.userMessage; return false }
        catch { actionError = "Action failed. Try again."; return false }
    }
}

struct AdminTemplatesView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = AdminTemplatesViewModel()

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No templates",
                emptyMessage: "Game templates (eggs) define how servers install and run.",
                retry: { Task { await model.load() } },
                content: { list($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 84) } } })
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Game templates")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private func list(_ templates: [AdminGameTemplate]) -> some View {
        VStack(spacing: 12) {
            if let actionError = model.actionError {
                Text(actionError).font(.footnote).foregroundStyle(.appDestructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(templates) { template in
                NavigationLink {
                    AdminTemplateDetailView(template: template, model: model)
                } label: {
                    TemplateRow(template: template)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct TemplateRow: View {
    let template: AdminGameTemplate

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(template.name).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                    if template.featured { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.appWarning) }
                    Spacer()
                    if !template.isPublished { StatusChip(text: "Draft", color: .appMuted) }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.appLabel)
                }
                HStack(spacing: 8) {
                    if let category = template.category?.name {
                        StatusChip(text: category, color: .appPrimary)
                    }
                    Text("by \(template.author)").font(.caption2).foregroundStyle(.appMuted)
                    Spacer()
                    Text(template.platformsLabel).font(.caption2).foregroundStyle(.appMuted)
                }
            }
        }
    }
}

struct AdminTemplateDetailView: View {
    let template: AdminGameTemplate
    @ObservedObject var model: AdminTemplatesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var confirmDelete = false

    /// Latest copy from the VM after edits, falling back to the passed-in value.
    private var current: AdminGameTemplate {
        model.state.value?.first(where: { $0.id == template.id }) ?? template
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(current.name).font(.headline).foregroundStyle(.appForeground)
                        Text(current.slug).font(.caption.monospaced()).foregroundStyle(.appMuted)
                        if let description = current.description, !description.isEmpty {
                            Text(description).font(.caption).foregroundStyle(.appMuted)
                        }
                        HStack(spacing: 8) {
                            if let category = current.category?.name { StatusChip(text: category, color: .appPrimary) }
                            StatusChip(text: "v\(current.version)", color: .appSecondary)
                            StatusChip(text: current.platformsLabel, color: .appMuted)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Published", isOn: Binding(
                            get: { current.isPublished },
                            set: { v in Task { await model.setFlags(current, published: v) } }))
                            .tint(.appPrimary)
                        Toggle("Featured", isOn: Binding(
                            get: { current.featured },
                            set: { v in Task { await model.setFlags(current, featured: v) } }))
                            .tint(.appPrimary)
                    }
                }

                infoCard
                variablesCard

                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete template", systemImage: "trash")
                }
                .buttonStyle(.refxDestructive)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Template")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { showEdit = true } } }
        .sheet(isPresented: $showEdit) {
            TemplateEditSheet(template: current) { name, author, desc, tags in
                await model.saveBasics(current, name: name, author: author, description: desc, tags: tags)
            }
        }
        .confirmationDialog("Delete \(current.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await model.delete(current); dismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Templates referenced by a server can't be deleted.")
        }
    }

    private var infoCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Runtime", systemImage: "gearshape.2")
                infoRow("Deploy", current.deployMethods.map(\.label).joined(separator: ", "))
                infoRow("Startup", current.startupCommand)
                if let steam = current.steamAppId { infoRow("Steam app", String(steam)) }
                infoRow("Recommended", String(format: "%.1f vCPU · %dGB RAM · %dGB disk", current.recCpuCores, current.recMemoryMb / 1024, current.recDiskMb / 1024))
                if let tags = current.tags, !tags.isEmpty { infoRow("Tags", tags.joined(separator: ", ")) }
            }
        }
    }

    private var variablesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Variables", systemImage: "curlybraces")
                let vars = current.variables ?? []
                if vars.isEmpty {
                    Text("No variables.").font(.caption).foregroundStyle(.appMuted)
                } else {
                    ForEach(vars) { variable in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(variable.displayName).font(.caption.weight(.semibold)).foregroundStyle(.appForeground)
                                StatusChip(text: variable.type.label, color: .appSecondary)
                                if variable.type == .secret { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.appWarning) }
                            }
                            Text(variable.envName).font(.caption2.monospaced()).foregroundStyle(.appMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.appMuted)
            Text(value).font(.caption).foregroundStyle(.appForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TemplateEditSheet: View {
    let template: AdminGameTemplate
    let onSave: (String, String, String, [String]) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var author = ""
    @State private var description = ""
    @State private var tags = ""
    @State private var isSaving = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !author.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Author", text: $author)
                    TextField("Description", text: $description, axis: .vertical).lineLimit(2...5)
                    TextField("Tags (comma-separated)", text: $tags)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Template") } footer: {
                    Text("Install scripts, Docker images and variables are edited on the web admin.")
                }
                .listRowBackground(Color.appCard)

                Section {
                    Button {
                        isSaving = true
                        let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        Task {
                            let ok = await onSave(name.trimmingCharacters(in: .whitespaces),
                                                  author.trimmingCharacters(in: .whitespaces),
                                                  description.trimmingCharacters(in: .whitespaces), tagList)
                            isSaving = false
                            if ok { dismiss() }
                        }
                    } label: { HStack { if isSaving { ProgressView() }; Text("Save") } }
                    .buttonStyle(.refxPrimary).disabled(!canSave)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("Edit template").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                name = template.name; author = template.author
                description = template.description ?? ""
                tags = (template.tags ?? []).joined(separator: ", ")
            }
        }
    }
}
