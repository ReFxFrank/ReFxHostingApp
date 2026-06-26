import SwiftUI

@MainActor
final class AdminLocationsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[Region]> = .idle
    @Published var actionError: String?
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.locations()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func create(code: String, name: String, country: String) async -> Bool {
        await mutate { try await $0.createLocation(.init(code: code, name: name, country: country)) }
    }

    func update(_ region: Region, code: String, name: String, country: String) async -> Bool {
        await mutate { try await $0.updateLocation(region.id, .init(code: code, name: name, country: country)) }
    }

    func delete(_ region: Region) async {
        _ = await mutate { try await $0.deleteLocation(region.id) }
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

struct AdminLocationsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = AdminLocationsViewModel()
    @State private var editing: Region?
    @State private var showCreate = false

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No locations",
                emptyMessage: "Add a region so nodes can be grouped by location.",
                retry: { Task { await model.load() } },
                content: { list($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 72) } } })
            .padding(16)
            .readableWidth()
        }
        .screenBackground()
        .navigationTitle("Locations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add location")
            }
        }
        .sheet(isPresented: $showCreate) {
            LocationEditSheet(title: "New location") { code, name, country in
                await model.create(code: code, name: name, country: country)
            }
        }
        .sheet(item: $editing) { region in
            LocationEditSheet(title: "Edit location", region: region) { code, name, country in
                await model.update(region, code: code, name: name, country: country)
            }
        }
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private func list(_ regions: [Region]) -> some View {
        VStack(spacing: 12) {
            if let actionError = model.actionError {
                Text(actionError).font(.footnote).foregroundStyle(.appDestructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(regions) { region in
                RegionCard(region: region,
                           onEdit: { editing = region },
                           onDelete: { Task { await model.delete(region) } })
            }
        }
    }
}

private struct RegionCard: View {
    let region: Region
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(.appSecondary).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.name).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                    HStack(spacing: 6) {
                        StatusChip(text: region.code.uppercased(), color: .appPrimary)
                        Text(region.country).font(.caption).foregroundStyle(.appMuted)
                    }
                }
                Spacer()
            }
        }
        .contextMenu {
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        }
        .confirmationDialog("Delete \(region.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Regions with nodes can't be deleted.")
        }
    }
}

private struct LocationEditSheet: View {
    let title: String
    var region: Region?
    let onSave: (String, String, String) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var name = ""
    @State private var country = ""
    @State private var isSaving = false

    private var canSave: Bool {
        !code.trimmingCharacters(in: .whitespaces).isEmpty &&
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !country.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Code (e.g. eu-west)", text: $code)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Name", text: $name)
                    TextField("Country", text: $country)
                } footer: {
                    Text("Code is a short slug used in node grouping; it's lowercased on save.")
                }
                .listRowBackground(Color.appCard)

                Section {
                    Button {
                        isSaving = true
                        Task {
                            let ok = await onSave(code.trimmingCharacters(in: .whitespaces),
                                                  name.trimmingCharacters(in: .whitespaces),
                                                  country.trimmingCharacters(in: .whitespaces))
                            isSaving = false
                            if ok { dismiss() }
                        }
                    } label: {
                        HStack { if isSaving { ProgressView() }; Text("Save") }
                    }
                    .buttonStyle(.refxPrimary)
                    .disabled(!canSave)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                if let region {
                    code = region.code; name = region.name; country = region.country
                }
            }
        }
    }
}
