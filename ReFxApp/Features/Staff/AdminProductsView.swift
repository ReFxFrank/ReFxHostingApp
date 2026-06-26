import SwiftUI

@MainActor
final class AdminProductsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[AdminProduct]> = .idle
    @Published var actionError: String?
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.products()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func create(_ body: CreateProductBody) async -> Bool {
        guard let service else { return false }
        actionError = nil
        do { _ = try await service.createProduct(body); await load(); return true }
        catch let error as APIError { actionError = error.userMessage; return false }
        catch { actionError = "Couldn't create the product."; return false }
    }
}

struct AdminProductsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = AdminProductsViewModel()
    @State private var showCreate = false

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No products",
                emptyMessage: "Create a plan customers can subscribe to.",
                retry: { Task { await model.load() } },
                content: { list($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 84) } } })
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Products & pricing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add product")
            }
        }
        .sheet(isPresented: $showCreate) {
            ProductCreateSheet { await model.create($0) }
        }
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private func list(_ products: [AdminProduct]) -> some View {
        VStack(spacing: 12) {
            if let actionError = model.actionError {
                Text(actionError).font(.footnote).foregroundStyle(.appDestructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(products) { product in
                NavigationLink {
                    AdminProductDetailView(productId: product.id, preview: product)
                } label: {
                    ProductRow(product: product)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ProductRow: View {
    let product: AdminProduct

    private var priceSummary: String {
        let prices = (product.prices ?? []) + (product.hardwareTiers?.flatMap { $0.prices ?? [] } ?? [])
        guard let min = prices.filter({ $0.isActive }).min(by: { $0.amountMinor < $1.amountMinor }) else {
            return "No active price"
        }
        return "from \(min.label)"
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(product.name).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                    Spacer()
                    if !product.isActive { StatusChip(text: "Inactive", color: .appMuted) }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.appLabel)
                }
                Text(product.slug).font(.caption.monospaced()).foregroundStyle(.appMuted)
                HStack(spacing: 8) {
                    StatusChip(text: product.type.label, color: .appPrimary)
                    StatusChip(text: product.billingModel.label, color: .appSecondary)
                    Spacer()
                    Text(priceSummary).font(.caption2).foregroundStyle(.appAccentText)
                }
            }
        }
    }
}

private struct ProductCreateSheet: View {
    let onSave: (CreateProductBody) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var type: ProductType = .gameServer
    @State private var billingModel: BillingModel = .hardwareTier
    @State private var name = ""
    @State private var slug = ""
    @State private var description = ""
    @State private var isSaving = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !slug.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .onChange(of: name) { newValue in
                            if slug.isEmpty || slug == Self.slugify(String(name.dropLast())) {
                                slug = Self.slugify(newValue)
                            }
                        }
                    TextField("Slug", text: $slug)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Description (optional)", text: $description, axis: .vertical).lineLimit(2...4)
                } header: { Text("Product") }
                .listRowBackground(Color.appCard)

                Section {
                    Picker("Type", selection: $type) {
                        ForEach(ProductType.allCases.filter { $0 != .unknown }, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Billing model", selection: $billingModel) {
                        Text("Hardware tier").tag(BillingModel.hardwareTier)
                        Text("Per slot").tag(BillingModel.perSlot)
                    }
                } header: { Text("Configuration") } footer: {
                    Text("Add hardware tiers and prices after creating the product.")
                }
                .listRowBackground(Color.appCard)

                Section {
                    Button {
                        isSaving = true
                        let body = CreateProductBody(
                            type: type, billingModel: billingModel,
                            name: name.trimmingCharacters(in: .whitespaces),
                            slug: slug.trimmingCharacters(in: .whitespaces),
                            description: description.isEmpty ? nil : description, isActive: true)
                        Task {
                            let ok = await onSave(body)
                            isSaving = false
                            if ok { dismiss() }
                        }
                    } label: {
                        HStack { if isSaving { ProgressView() }; Text("Create product") }
                    }
                    .buttonStyle(.refxPrimary).disabled(!canSave)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("New product").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    static func slugify(_ s: String) -> String {
        let lowered = s.lowercased()
        let mapped = lowered.map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : "-"
        }
        let collapsed = String(mapped).split(separator: "-").joined(separator: "-")
        return collapsed
    }
}
