import SwiftUI

@MainActor
final class AdminProductDetailViewModel: ObservableObject {
    @Published var state: LoadState<AdminProduct> = .idle
    @Published var actionError: String?
    private var service: StaffService?
    let productId: String

    init(productId: String, preview: AdminProduct?) {
        self.productId = productId
        if let preview { state = .loaded(preview) }
    }

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.product(productId)) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func setActive(_ isActive: Bool) async {
        await run { try await $0.updateProduct(self.productId, .init(isActive: isActive)) }
    }
    func addTier(_ body: CreateTierBody) async -> Bool {
        await run { try await $0.createTier(productId: self.productId, body) }
    }
    func deleteTier(_ tier: HardwareTier) async {
        await run { try await $0.deleteTier(tier.id) }
    }
    func addProductPrice(_ body: CreatePriceBody) async -> Bool {
        await run { try await $0.createPrice(productId: self.productId, body) }
    }
    func addTierPrice(tierId: String, _ body: CreatePriceBody) async -> Bool {
        await run { try await $0.createTierPrice(productId: self.productId, tierId: tierId, body) }
    }
    func deletePrice(_ price: AdminPrice) async {
        await run { try await $0.deletePrice(price.id) }
    }

    @discardableResult
    private func run(_ work: (StaffService) async throws -> Void) async -> Bool {
        guard let service else { return false }
        actionError = nil
        do { try await work(service); await load(); return true }
        catch let error as APIError { actionError = error.userMessage; return false }
        catch { actionError = "Action failed. Try again."; return false }
    }
}

struct AdminProductDetailView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: AdminProductDetailViewModel
    @State private var showAddTier = false
    @State private var priceTarget: PriceTarget?

    /// Where a new price attaches: the product itself, or a specific tier.
    struct PriceTarget: Identifiable { let id: String; let tierId: String?; let title: String }

    init(productId: String, preview: AdminProduct? = nil) {
        _model = StateObject(wrappedValue: AdminProductDetailViewModel(productId: productId, preview: preview))
    }

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { _ in false },
                emptyTitle: "Not found",
                retry: { Task { await model.load() } },
                content: { detail($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 100) } } })
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(model.state.value?.name ?? "Product")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddTier) {
            TierCreateSheet { await model.addTier($0) }
        }
        .sheet(item: $priceTarget) { target in
            PriceCreateSheet(title: target.title) { body in
                if let tierId = target.tierId { return await model.addTierPrice(tierId: tierId, body) }
                return await model.addProductPrice(body)
            }
        }
        .refreshable { await model.load() }
        .task { model.bind(session); await model.load() }
    }

    @ViewBuilder private func detail(_ product: AdminProduct) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let actionError = model.actionError {
                Text(actionError).font(.footnote).foregroundStyle(.appDestructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name).font(.headline).foregroundStyle(.appForeground)
                            Text(product.slug).font(.caption.monospaced()).foregroundStyle(.appMuted)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { product.isActive },
                                                 set: { v in Task { await model.setActive(v) } }))
                            .labelsHidden().tint(.appPrimary).accessibilityLabel("Active")
                    }
                    HStack(spacing: 8) {
                        StatusChip(text: product.type.label, color: .appPrimary)
                        StatusChip(text: product.billingModel.label, color: .appSecondary)
                        if !product.isActive { StatusChip(text: "Inactive", color: .appMuted) }
                    }
                    if let description = product.description, !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(.appMuted)
                    }
                }
            }

            // Product-level prices
            section(title: "Product prices", systemImage: "dollarsign.circle",
                    trailing: { Button { priceTarget = .init(id: product.id, tierId: nil, title: "Product price") }
                        label: { Image(systemName: "plus.circle") }.foregroundStyle(.appPrimary) }) {
                priceList(product.prices ?? [], emptyText: "No product-level prices.")
            }

            // Hardware tiers
            section(title: "Hardware tiers", systemImage: "cpu",
                    trailing: { Button { showAddTier = true } label: { Image(systemName: "plus.circle") }
                        .foregroundStyle(.appPrimary) }) {
                let tiers = product.hardwareTiers ?? []
                if tiers.isEmpty {
                    Text("No tiers yet.").font(.caption).foregroundStyle(.appMuted)
                } else {
                    VStack(spacing: 10) {
                        ForEach(tiers) { tier in
                            TierCard(tier: tier,
                                     onAddPrice: { priceTarget = .init(id: tier.id, tierId: tier.id, title: "\(tier.name) price") },
                                     onDeleteTier: { Task { await model.deleteTier(tier) } },
                                     onDeletePrice: { price in Task { await model.deletePrice(price) } })
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func section<Trailing: View, Content: View>(
        title: String, systemImage: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title, systemImage: systemImage, trailing: trailing)
            content()
        }
    }

    @ViewBuilder
    private func priceList(_ prices: [AdminPrice], emptyText: String) -> some View {
        if prices.isEmpty {
            Text(emptyText).font(.caption).foregroundStyle(.appMuted)
        } else {
            VStack(spacing: 8) {
                ForEach(prices) { price in
                    PriceRow(price: price, onDelete: { Task { await model.deletePrice(price) } })
                }
            }
        }
    }
}

private struct PriceRow: View {
    let price: AdminPrice
    let onDelete: () -> Void
    @State private var confirm = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag").font(.caption).foregroundStyle(.appSecondary)
            Text(price.label).font(.callout.weight(.medium)).foregroundStyle(.appForeground)
            if !price.isActive { StatusChip(text: "Inactive", color: .appMuted) }
            Spacer()
            Button { confirm = true } label: { Image(systemName: "trash").font(.caption) }
                .foregroundStyle(.appDestructive)
        }
        .padding(10)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .confirmationDialog("Delete this price?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct TierCard: View {
    let tier: HardwareTier
    let onAddPrice: () -> Void
    let onDeleteTier: () -> Void
    let onDeletePrice: (AdminPrice) -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(tier.name).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                if tier.isRecommended { StatusChip(text: "Recommended", color: .appSuccess) }
                Spacer()
                Button { onAddPrice() } label: { Image(systemName: "plus.circle") }.foregroundStyle(.appPrimary)
                Button { confirmDelete = true } label: { Image(systemName: "trash").font(.caption) }
                    .foregroundStyle(.appDestructive)
            }
            Text("\(tier.cpuCores, specifier: "%.1f") vCPU · \(tier.memoryMb / 1024)GB RAM · \(tier.diskMb / 1024)GB disk")
                .font(.caption2).foregroundStyle(.appMuted)
            ForEach(tier.prices ?? []) { price in
                HStack(spacing: 6) {
                    Image(systemName: "tag").font(.caption2).foregroundStyle(.appSecondary)
                    Text(price.label).font(.caption).foregroundStyle(.appForeground)
                    if !price.isActive { StatusChip(text: "Inactive", color: .appMuted) }
                    Spacer()
                    Button { onDeletePrice(price) } label: { Image(systemName: "minus.circle").font(.caption2) }
                        .foregroundStyle(.appDestructive)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .confirmationDialog("Delete \(tier.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDeleteTier)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tiers referenced by subscriptions can't be deleted.")
        }
    }
}

private struct TierCreateSheet: View {
    let onSave: (CreateTierBody) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var cpu = ""
    @State private var ramGb = ""
    @State private var diskGb = ""
    @State private var isSaving = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        Double(cpu) != nil && Int(ramGb) != nil && Int(diskGb) != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Standard)", text: $name)
                    HStack { Text("vCPU cores"); Spacer(); TextField("2", text: $cpu).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    HStack { Text("RAM (GB)"); Spacer(); TextField("4", text: $ramGb).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Disk (GB)"); Spacer(); TextField("20", text: $diskGb).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                } header: { Text("Hardware tier") } footer: {
                    Text("Add prices to the tier after it's created.")
                }
                .listRowBackground(Color.appCard)

                Section {
                    Button {
                        guard let cpuV = Double(cpu), let ramV = Int(ramGb), let diskV = Int(diskGb) else { return }
                        isSaving = true
                        let body = CreateTierBody(name: name.trimmingCharacters(in: .whitespaces),
                                                  cpuCores: cpuV, memoryMb: ramV * 1024, diskMb: diskV * 1024,
                                                  isActive: true)
                        Task { let ok = await onSave(body); isSaving = false; if ok { dismiss() } }
                    } label: { HStack { if isSaving { ProgressView() }; Text("Add tier") } }
                    .buttonStyle(.refxPrimary).disabled(!canSave)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("New tier").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct PriceCreateSheet: View {
    let title: String
    let onSave: (CreatePriceBody) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var interval: BillingInterval = .monthly
    @State private var amount = ""
    @State private var isSaving = false

    private var amountMinor: Int? {
        Double(amount.trimmingCharacters(in: .whitespaces)).map { Int(($0 * 100).rounded()) }
    }
    private var canSave: Bool { (amountMinor ?? 0) > 0 && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Interval", selection: $interval) {
                        ForEach(BillingInterval.allCases.filter { $0 != .unknown }, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    HStack {
                        TextField("Amount (e.g. 12.00)", text: $amount).keyboardType(.decimalPad)
                        Text("USD").foregroundStyle(.appMuted)
                    }
                } header: { Text(title) }
                .listRowBackground(Color.appCard)

                Section {
                    Button {
                        guard let minor = amountMinor else { return }
                        isSaving = true
                        let body = CreatePriceBody(interval: interval, currency: "USD",
                                                   amountMinor: minor, isActive: true)
                        Task { let ok = await onSave(body); isSaving = false; if ok { dismiss() } }
                    } label: { HStack { if isSaving { ProgressView() }; Text("Add price") } }
                    .buttonStyle(.refxPrimary).disabled(!canSave)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("New price").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
