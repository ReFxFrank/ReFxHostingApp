import SwiftUI

// MARK: - Entry: product list + precondition gate

@MainActor
final class NewServerViewModel: ObservableObject {
    @Published var products: LoadState<[CatalogProduct]> = .idle
    @Published var templates: [CatalogTemplate] = []
    @Published var profile: OrderProfile?
    private var catalog: CatalogService?
    private var account: AccountService?

    func bind(_ session: AppSession) {
        if catalog == nil { catalog = session.catalog }
        if account == nil { account = session.account }
    }

    func load() async {
        guard let catalog else { return }
        if products.value == nil { products = .loading }
        do {
            async let prods = catalog.products()
            async let temps = catalog.templates()
            let (p, t) = try await (prods, temps)
            products = .loaded(p.filter { $0.isActive && $0.type != .addon })
            templates = t
        }
        catch let error as APIError { products = .failed(error) }
        catch { products = .failed(.network(isOffline: false, underlying: "\(error)")) }
        if let account { profile = try? await account.orderProfile() }
    }

    /// Templates a product allows (empty allow-list = all), game templates only.
    func templates(for product: CatalogProduct) -> [CatalogTemplate] {
        let allowed = product.allowedTemplateIds
        return templates.filter { allowed.isEmpty || allowed.contains($0.id) }
    }
}

struct NewServerView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = NewServerViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let profile = model.profile, !profile.orderReady {
                    PreconditionBanner(profile: profile, onUpdated: { Task { await model.load() } })
                }
                AsyncStateView(
                    state: model.products,
                    isEmpty: { $0.isEmpty },
                    emptyTitle: "No products",
                    emptyMessage: "Nothing is available to order right now.",
                    retry: { Task { await model.load() } },
                    content: { products in
                        VStack(spacing: 12) {
                            ForEach(products) { product in
                                NavigationLink {
                                    OrderConfigureView(product: product,
                                                       templates: model.templates(for: product),
                                                       profile: model.profile)
                                } label: { ProductCard(product: product) }
                                .buttonStyle(.plain)
                            }
                        }
                    },
                    skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 88) } } })
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("New server")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.bind(session); if model.products.value == nil { await model.load() } }
    }
}

private struct ProductCard: View {
    let product: CatalogProduct
    private var fromPrice: Money? {
        let all = product.productPrices + product.hardwareTiers.flatMap { $0.activePrices }
        return all.min(by: { $0.amountMinor < $1.amountMinor })?.money
    }
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(product.name).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.appLabel)
                }
                if let description = product.description, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.appMuted).lineLimit(2)
                }
                HStack(spacing: 8) {
                    StatusChip(text: product.type.label, color: .appPrimary)
                    StatusChip(text: product.isPerSlot ? "Per slot" : "Tiered", color: .appSecondary)
                    Spacer()
                    if let fromPrice { Text("from \(fromPrice.formatted)").font(.caption2).foregroundStyle(.appAccentText) }
                }
            }
        }
    }
}

// MARK: - Configurator

@MainActor
final class OrderConfigureViewModel: ObservableObject {
    let product: CatalogProduct
    let templates: [CatalogTemplate]
    @Published var profile: OrderProfile?

    @Published var templateId: String?
    @Published var tierId: String?
    @Published var slots: Int
    @Published var interval: BillingInterval = .monthly
    @Published var regionId: String?            // nil = automatic
    @Published var regions: [Region] = []
    @Published var name = ""
    @Published var env: [String: String] = [:]

    @Published var couponCode = ""
    @Published var coupon: CouponValidateResult?
    @Published var couponError: String?
    @Published var giftCardCode = ""
    @Published var giftCard: GiftCardLookupResult?
    @Published var giftCardError: String?
    @Published var useCredit = false

    @Published var placing = false
    @Published var message: String?
    @Published var placedServerId: String?

    private var billing: BillingService?
    private var catalog: CatalogService?

    init(product: CatalogProduct, templates: [CatalogTemplate], profile: OrderProfile?) {
        self.product = product
        self.templates = templates
        self.profile = profile
        self.slots = product.minSlots
        // Default selections.
        if product.isPerSlot { templateId = product.gameTemplateId ?? templates.first?.id }
        else { templateId = templates.first?.id }
        tierId = product.hardwareTiers.first(where: { $0.isRecommended })?.id ?? product.hardwareTiers.first?.id
    }

    func bind(_ session: AppSession) {
        if billing == nil { billing = session.billing }
        if catalog == nil { catalog = session.catalog }
        if interval == .monthly, !availableIntervals.contains(.monthly) {
            interval = availableIntervals.first ?? .monthly
        }
        seedEnv()
    }

    // Derived selection
    var selectedTier: CatalogTier? { product.hardwareTiers.first { $0.id == tierId } }
    var selectedTemplate: CatalogTemplate? { templates.first { $0.id == templateId } }
    var availablePrices: [CatalogPrice] {
        product.isPerSlot ? product.productPrices : (selectedTier?.activePrices ?? [])
    }
    var availableIntervals: [BillingInterval] {
        var seen = Set<BillingInterval>(); var out: [BillingInterval] = []
        for p in availablePrices where !seen.contains(p.interval) { seen.insert(p.interval); out.append(p.interval) }
        return out
    }
    var selectedPrice: CatalogPrice? { availablePrices.first { $0.interval == interval } }
    var quantity: Int { product.isPerSlot ? slots : 1 }
    var currency: String { selectedPrice?.currency ?? "USD" }
    var subtotalMinor: Int { (selectedPrice?.amountMinor ?? 0) * quantity }
    var subtotal: Money { Money(minorUnits: subtotalMinor, currency: currency) }

    var couponDiscountMinor: Int { coupon?.discountMinor ?? 0 }
    var giftCardAppliedMinor: Int { min(giftCard?.balanceMinor ?? 0, max(0, subtotalMinor - couponDiscountMinor)) }
    var creditAppliedMinor: Int {
        guard useCredit else { return 0 }
        let remaining = max(0, subtotalMinor - couponDiscountMinor - giftCardAppliedMinor)
        return min(profile?.creditBalanceMinor ?? 0, remaining)
    }
    var estimatedTotalMinor: Int { max(0, subtotalMinor - couponDiscountMinor - giftCardAppliedMinor - creditAppliedMinor) }
    var estimatedTotal: Money { Money(minorUnits: estimatedTotalMinor, currency: currency) }

    var canPlace: Bool {
        (profile?.orderReady ?? false) && templateId != nil && selectedPrice != nil &&
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !placing
    }

    func onTemplateChange() { seedEnv() }

    private func seedEnv() {
        guard let template = selectedTemplate else { env = [:]; return }
        var next: [String: String] = [:]
        for v in template.variables where v.userEditable {
            next[v.envName] = env[v.envName] ?? (v.defaultValue ?? "")
        }
        env = next
    }

    func loadRegions() async {
        guard let catalog else { return }
        let tier = selectedTier
        let cpu = tier?.cpuCores ?? 0
        let mem = tier?.memoryMb ?? 0
        let disk = tier?.diskMb ?? 0
        regions = (try? await catalog.regions(cpuCores: cpu, memoryMb: mem, diskMb: disk)) ?? []
    }

    func applyCoupon() async {
        guard let billing, !couponCode.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        couponError = nil
        do {
            let r = try await billing.validateCoupon(code: couponCode.trimmingCharacters(in: .whitespaces),
                                                     subtotalMinor: subtotalMinor)
            if r.valid { coupon = r } else { coupon = nil; couponError = "That code isn't valid." }
        } catch let error as APIError { coupon = nil; couponError = error.userMessage }
        catch { coupon = nil; couponError = "Couldn't check that code." }
    }

    func applyGiftCard() async {
        guard let billing, !giftCardCode.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        giftCardError = nil
        do { giftCard = try await billing.lookupGiftCard(code: giftCardCode.trimmingCharacters(in: .whitespaces)) }
        catch let error as APIError { giftCard = nil; giftCardError = error.userMessage }
        catch { giftCard = nil; giftCardError = "Couldn't find that gift card." }
    }

    func place() async {
        guard let billing, let price = selectedPrice, let templateId else { return }
        placing = true; message = nil
        defer { placing = false }
        var body = CreateOrderBody(productId: product.id, priceId: price.id,
                                   templateId: templateId,
                                   name: name.trimmingCharacters(in: .whitespaces))
        if product.isPerSlot { body.slots = slots } else { body.hardwareTierId = tierId }
        body.regionId = regionId
        if coupon?.valid == true { body.couponCode = coupon?.code }
        if giftCard != nil { body.giftCardCode = giftCard?.code }
        if useCredit { body.useCredit = true }
        let filledEnv = env.filter { !$0.value.isEmpty }
        if !filledEnv.isEmpty { body.environment = filledEnv }
        do {
            let result = try await billing.createOrder(body)
            if result.paid {
                message = "Order placed — your server is provisioning."
                placedServerId = result.serverId
            } else if let urlStr = result.checkoutUrl, let url = URL(string: urlStr) {
                WebLink.open(url)
                message = "Finish payment in your browser. Your server activates once it's paid."
                placedServerId = result.serverId
            } else {
                message = "Order placed."
                placedServerId = result.serverId
            }
        }
        catch let error as APIError { message = error.userMessage }
        catch { message = "Couldn't place the order." }
    }
}

struct OrderConfigureView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: OrderConfigureViewModel
    @State private var goToServer = false

    init(product: CatalogProduct, templates: [CatalogTemplate], profile: OrderProfile?) {
        _model = StateObject(wrappedValue: OrderConfigureViewModel(product: product, templates: templates, profile: profile))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let profile = model.profile, !profile.orderReady {
                    PreconditionBanner(profile: profile, onUpdated: {})
                }
                if let message = model.message {
                    Text(message).font(.footnote).foregroundStyle(.appPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.placedServerId != nil {
                    Button("View server") { goToServer = true }.buttonStyle(.refxSecondary)
                } else {
                    if !model.product.isPerSlot { tierSection }
                    if model.product.isPerSlot { slotSection }
                    intervalSection
                    if model.templates.count > 1 && !model.product.isPerSlot { templateSection }
                    regionSection
                    nameSection
                    envSection
                    discountsSection
                    totalsSection
                    placeButton
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(model.product.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goToServer) {
            if let id = model.placedServerId { ServerDetailView(serverId: id, preview: nil) }
        }
        .task {
            model.bind(session)
            await model.loadRegions()
        }
    }

    private func card<Content: View>(_ title: String, systemImage: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title, systemImage: systemImage)
                content()
            }
        }
    }

    private var tierSection: some View {
        card("Hardware tier", systemImage: "cpu") {
            ForEach(model.product.hardwareTiers.filter { $0.isActive }) { tier in
                Button { model.tierId = tier.id; Task { await model.loadRegions() } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tier.id == model.tierId ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(tier.id == model.tierId ? .appPrimary : .appMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(tier.name).font(.subheadline.weight(.medium)).foregroundStyle(.appForeground)
                                if tier.isRecommended { StatusChip(text: "Recommended", color: .appSuccess) }
                            }
                            Text(tier.resourceLabel).font(.caption2).foregroundStyle(.appMuted)
                        }
                        Spacer()
                        if let p = tier.activePrices.first(where: { $0.interval == model.interval }) ?? tier.activePrices.first {
                            Text(p.label).font(.caption.weight(.semibold)).foregroundStyle(.appAccentText)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var slotSection: some View {
        card("Slots", systemImage: "person.3") {
            HStack {
                Text("\(model.slots) slots").font(.title3.weight(.semibold)).foregroundStyle(.appForeground)
                Spacer()
                Stepper("", value: $model.slots,
                        in: model.product.slotRange, step: model.product.safeSlotStep)
                    .labelsHidden()
            }
        }
    }

    private var intervalSection: some View {
        card("Billing cycle", systemImage: "calendar") {
            if model.availableIntervals.isEmpty {
                Text("No pricing available.").font(.caption).foregroundStyle(.appMuted)
            } else {
                Picker("Cycle", selection: $model.interval) {
                    ForEach(model.availableIntervals, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu).tint(.appPrimary)
            }
        }
    }

    private var templateSection: some View {
        card("Game", systemImage: "gamecontroller") {
            Picker("Game", selection: Binding(get: { model.templateId ?? "" },
                                              set: { model.templateId = $0; model.onTemplateChange() })) {
                ForEach(model.templates) { template in Text(template.name).tag(template.id) }
            }
            .pickerStyle(.menu).tint(.appPrimary)
        }
    }

    private var regionSection: some View {
        card("Region", systemImage: "globe") {
            Picker("Region", selection: $model.regionId) {
                Text("Automatic").tag(String?.none)
                ForEach(model.regions) { region in Text("\(region.name) · \(region.country)").tag(String?.some(region.id)) }
            }
            .pickerStyle(.menu).tint(.appPrimary)
        }
    }

    private var nameSection: some View {
        card("Server name", systemImage: "tag") {
            TextField("e.g. My Server", text: $model.name)
        }
    }

    @ViewBuilder private var envSection: some View {
        let vars = (model.selectedTemplate?.variables ?? []).filter { $0.userEditable }
        if !vars.isEmpty {
            card("Configuration", systemImage: "slider.horizontal.3") {
                ForEach(vars) { variable in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(variable.displayName).font(.caption.weight(.medium)).foregroundStyle(.appForeground)
                        envField(variable)
                        if let d = variable.description, !d.isEmpty {
                            Text(d).font(.caption2).foregroundStyle(.appMuted).lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func envField(_ variable: CatalogTemplateVariable) -> some View {
        let binding = Binding(get: { model.env[variable.envName] ?? "" },
                              set: { model.env[variable.envName] = $0 })
        switch variable.type {
        case .boolean:
            Toggle("Enabled", isOn: Binding(get: { (model.env[variable.envName] ?? "") == "true" },
                                            set: { model.env[variable.envName] = $0 ? "true" : "false" }))
                .tint(.appPrimary)
        case .secret:
            SecureField("Value", text: binding)
        default:
            TextField("Value", text: binding).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }

    private var discountsSection: some View {
        card("Discounts", systemImage: "tag.circle") {
            VStack(spacing: 8) {
                HStack {
                    TextField("Coupon code", text: $model.couponCode)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("Apply") { Task { await model.applyCoupon() } }
                        .buttonStyle(.refxSecondary(fullWidth: false)).disabled(model.couponCode.isEmpty)
                }
                if let coupon = model.coupon { Text("Coupon applied: −\(Money(minorUnits: coupon.discountMinor, currency: model.currency).formatted)").font(.caption2).foregroundStyle(.appSuccess).frame(maxWidth: .infinity, alignment: .leading) }
                if let e = model.couponError { Text(e).font(.caption2).foregroundStyle(.appDestructive).frame(maxWidth: .infinity, alignment: .leading) }

                HStack {
                    TextField("Gift card code", text: $model.giftCardCode)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("Apply") { Task { await model.applyGiftCard() } }
                        .buttonStyle(.refxSecondary(fullWidth: false)).disabled(model.giftCardCode.isEmpty)
                }
                if let gc = model.giftCard { Text("Gift card: \(gc.balance.formatted) available").font(.caption2).foregroundStyle(.appSuccess).frame(maxWidth: .infinity, alignment: .leading) }
                if let e = model.giftCardError { Text(e).font(.caption2).foregroundStyle(.appDestructive).frame(maxWidth: .infinity, alignment: .leading) }

                if (model.profile?.creditBalanceMinor ?? 0) > 0 {
                    Toggle("Use store credit (\(model.profile!.creditBalance.formatted))", isOn: $model.useCredit)
                        .tint(.appPrimary).font(.caption)
                }
            }
        }
    }

    private var totalsSection: some View {
        card("Total", systemImage: "creditcard") {
            VStack(spacing: 6) {
                totalRow("Subtotal", model.subtotal.formatted, muted: true)
                if model.couponDiscountMinor > 0 {
                    totalRow("Coupon", "−" + Money(minorUnits: model.couponDiscountMinor, currency: model.currency).formatted, color: .appSuccess)
                }
                if model.giftCardAppliedMinor > 0 {
                    totalRow("Gift card", "−" + Money(minorUnits: model.giftCardAppliedMinor, currency: model.currency).formatted, color: .appSuccess)
                }
                if model.creditAppliedMinor > 0 {
                    totalRow("Store credit", "−" + Money(minorUnits: model.creditAppliedMinor, currency: model.currency).formatted, color: .appSuccess)
                }
                Divider().overlay(Color.appBorder)
                totalRow("Due today (est.)", model.estimatedTotal.formatted, bold: true)
                Text("Tax and the final total are calculated at checkout.")
                    .font(.caption2).foregroundStyle(.appMuted).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func totalRow(_ label: String, _ value: String, muted: Bool = false, bold: Bool = false, color: Color = .appForeground) -> some View {
        let labelFont: Font = bold ? .subheadline.weight(.semibold) : .caption
        let valueFont: Font = bold ? .subheadline.weight(.bold) : .caption
        return HStack {
            Text(label).font(labelFont).foregroundStyle(muted ? .appMuted : .appForeground)
            Spacer()
            Text(value).font(valueFont.monospacedDigit()).foregroundStyle(color)
        }
    }

    private var placeButton: some View {
        Button { Task { await model.place() } } label: {
            HStack { if model.placing { ProgressView() }
                Text(model.placing ? "Placing…" : "Place order · \(model.estimatedTotal.formatted)") }
        }
        .buttonStyle(.refxPrimary).disabled(!model.canPlace)
    }
}

// MARK: - Precondition banner + address form

private struct PreconditionBanner: View {
    let profile: OrderProfile
    let onUpdated: () -> Void
    @State private var showAddress = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Before you can order", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.appWarning)
                if !profile.emailVerified {
                    Text("• Verify your email address (check your inbox).")
                        .font(.caption).foregroundStyle(.appMuted)
                }
                if !profile.hasAddress || profile.needsState {
                    Text("• Add your billing address.").font(.caption).foregroundStyle(.appMuted)
                    Button("Add billing address") { showAddress = true }.buttonStyle(.refxSecondary)
                }
            }
        }
        .sheet(isPresented: $showAddress) {
            AddressFormView(profile: profile, onSaved: onUpdated)
        }
    }
}

private struct AddressFormView: View {
    let profile: OrderProfile
    let onSaved: () -> Void
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var line1 = ""
    @State private var line2 = ""
    @State private var city = ""
    @State private var region = ""
    @State private var postalCode = ""
    @State private var country = ""
    @State private var saving = false
    @State private var errorText: String?

    private var isUS: Bool { country.trimmingCharacters(in: .whitespaces).uppercased() == "US" }
    private var canSave: Bool {
        !line1.isEmpty && !city.isEmpty && !postalCode.isEmpty && !country.isEmpty &&
        (!isUS || !region.isEmpty) && !saving
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorText { Text(errorText).font(.footnote).foregroundStyle(.appDestructive).listRowBackground(Color.appCard) }
                Section {
                    TextField("Address line 1", text: $line1)
                    TextField("Address line 2 (optional)", text: $line2)
                    TextField("City", text: $city)
                    TextField("State / province\(isUS ? " (required)" : "")", text: $region)
                    TextField("Postal code", text: $postalCode)
                    TextField("Country (ISO code, e.g. US)", text: $country)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                } header: { Text("Billing address") }
                .listRowBackground(Color.appCard)

                Section {
                    Button { save() } label: { HStack { if saving { ProgressView() }; Text("Save address") } }
                        .buttonStyle(.refxPrimary).disabled(!canSave)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("Billing address").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                line1 = profile.addressLine1 ?? ""; line2 = profile.addressLine2 ?? ""
                city = profile.city ?? ""; region = profile.region ?? ""
                postalCode = profile.postalCode ?? ""; country = profile.country ?? ""
            }
        }
    }

    private func save() {
        saving = true; errorText = nil
        var body = UpdateProfileBody()
        body.addressLine1 = line1; body.addressLine2 = line2.isEmpty ? nil : line2
        body.city = city; body.region = region.isEmpty ? nil : region
        body.postalCode = postalCode; body.country = country
        Task {
            do { try await session.account.updateProfile(body); saving = false; onSaved(); dismiss() }
            catch let e as APIError { saving = false; errorText = e.userMessage }
            catch { saving = false; errorText = "Couldn't save the address." }
        }
    }
}
