import SwiftUI

@MainActor
final class AdminCouponsViewModel: ObservableObject {
    @Published private(set) var coupons: LoadState<[Coupon]> = .idle
    @Published private(set) var giftCards: LoadState<[GiftCard]> = .idle
    @Published var actionError: String?
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func loadCoupons() async {
        guard let service else { return }
        if coupons.value == nil { coupons = .loading }
        do { coupons = .loaded(try await service.coupons()) }
        catch let error as APIError { coupons = .failed(error) }
        catch { coupons = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func loadGiftCards() async {
        guard let service else { return }
        if giftCards.value == nil { giftCards = .loading }
        do { giftCards = .loaded(try await service.giftCards()) }
        catch let error as APIError { giftCards = .failed(error) }
        catch { giftCards = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func createCoupon(_ body: CreateCouponBody) async -> Bool {
        await mutate(reloadCoupons: true) { try await $0.createCoupon(body) }
    }
    func setCouponActive(_ coupon: Coupon, isActive: Bool) async {
        _ = await mutate(reloadCoupons: true) { try await $0.updateCoupon(coupon.id, .init(isActive: isActive)) }
    }
    func deleteCoupon(_ coupon: Coupon) async {
        _ = await mutate(reloadCoupons: true) { try await $0.deleteCoupon(coupon.id) }
    }
    func createGiftCard(_ body: CreateGiftCardBody) async -> Bool {
        await mutate(reloadCoupons: false) { try await $0.createGiftCard(body) }
    }
    func setGiftCardActive(_ card: GiftCard, isActive: Bool) async {
        _ = await mutate(reloadCoupons: false) { try await $0.updateGiftCard(card.id, .init(isActive: isActive)) }
    }

    @discardableResult
    private func mutate(reloadCoupons: Bool, _ work: (StaffService) async throws -> Void) async -> Bool {
        guard let service else { return false }
        actionError = nil
        do {
            try await work(service)
            if reloadCoupons { await loadCoupons() } else { await loadGiftCards() }
            return true
        }
        catch let error as APIError { actionError = error.userMessage; return false }
        catch { actionError = "Action failed. Try again."; return false }
    }
}

struct AdminCouponsView: View {
    enum Tab: String, CaseIterable { case coupons = "Coupons", giftCards = "Gift cards" }

    @EnvironmentObject private var session: AppSession
    @StateObject private var model = AdminCouponsViewModel()
    @State private var tab: Tab = .coupons
    @State private var showCreateCoupon = false
    @State private var showCreateGiftCard = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if let actionError = model.actionError {
                    Text(actionError).font(.footnote).foregroundStyle(.appDestructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                switch tab {
                case .coupons: couponsList
                case .giftCards: giftCardsList
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Coupons & gift cards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if tab == .coupons { showCreateCoupon = true } else { showCreateGiftCard = true }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add coupon")
            }
        }
        .sheet(isPresented: $showCreateCoupon) {
            CouponEditSheet { await model.createCoupon($0) }
        }
        .sheet(isPresented: $showCreateGiftCard) {
            GiftCardEditSheet { await model.createGiftCard($0) }
        }
        .refreshable { if tab == .coupons { await model.loadCoupons() } else { await model.loadGiftCards() } }
        .task { model.bind(session); if model.coupons.value == nil { await model.loadCoupons() } }
        .onChange(of: tab) { newTab in
            if newTab == .giftCards, model.giftCards.value == nil { Task { await model.loadGiftCards() } }
        }
    }

    private var couponsList: some View {
        AsyncStateView(
            state: model.coupons,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No coupons",
            emptyMessage: "Create a discount code customers can redeem at checkout.",
            retry: { Task { await model.loadCoupons() } },
            content: { coupons in
                VStack(spacing: 12) {
                    ForEach(coupons) { coupon in
                        CouponCard(coupon: coupon,
                                   onToggle: { isActive in Task { await model.setCouponActive(coupon, isActive: isActive) } },
                                   onDelete: { Task { await model.deleteCoupon(coupon) } })
                    }
                }
            },
            skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 92) } } })
    }

    private var giftCardsList: some View {
        AsyncStateView(
            state: model.giftCards,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No gift cards",
            emptyMessage: "Issue store credit customers can redeem.",
            retry: { Task { await model.loadGiftCards() } },
            content: { cards in
                VStack(spacing: 12) {
                    ForEach(cards) { card in
                        GiftCardCard(card: card,
                                     onToggle: { isActive in Task { await model.setGiftCardActive(card, isActive: isActive) } })
                    }
                }
            },
            skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 92) } } })
    }
}

private struct CouponCard: View {
    let coupon: Coupon
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(coupon.code).font(.subheadline.weight(.bold).monospaced()).foregroundStyle(.appForeground)
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(get: { coupon.isActive }, set: { onToggle($0) }))
                        .labelsHidden().tint(.appPrimary).accessibilityLabel("Coupon active")
                }
                if let description = coupon.description, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.appMuted).lineLimit(2)
                }
                HStack(spacing: 8) {
                    StatusChip(text: coupon.valueLabel, color: .appAccentText)
                    Text(coupon.redemptionsLabel).font(.caption2).foregroundStyle(.appMuted)
                    Spacer()
                    if let expires = coupon.expiresAt {
                        Text("ends \(expires.formatted(.dateTime.month().day()))")
                            .font(.caption2).foregroundStyle(.appMuted)
                    }
                    if !coupon.isActive { StatusChip(text: "Inactive", color: .appMuted) }
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        }
        .confirmationDialog("Delete \(coupon.code)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct GiftCardCard: View {
    let card: GiftCard
    let onToggle: (Bool) -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(card.code).font(.subheadline.weight(.bold).monospaced()).foregroundStyle(.appForeground)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(get: { card.isActive }, set: { onToggle($0) }))
                        .labelsHidden().tint(.appPrimary).accessibilityLabel("Gift card active")
                }
                if let note = card.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.appMuted).lineLimit(2)
                }
                HStack(spacing: 8) {
                    StatusChip(text: "\(card.balance.formatted) left", color: .appAccentText)
                    Text("of \(card.initialBalance.formatted)").font(.caption2).foregroundStyle(.appMuted)
                    Spacer()
                    if !card.isActive { StatusChip(text: "Inactive", color: .appMuted) }
                }
            }
        }
    }
}

private struct CouponEditSheet: View {
    let onSave: (CreateCouponBody) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var description = ""
    @State private var kind: CouponKind = .percent
    @State private var amount = ""          // percent integer OR dollars for fixed
    @State private var hasExpiry = false
    @State private var expiresAt = Date().addingTimeInterval(60 * 60 * 24 * 30)
    @State private var isSaving = false

    private var valueMinorOrPercent: Int? {
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .percent: return Int(trimmed).flatMap { (1...100).contains($0) ? $0 : nil }
        case .fixed: return Double(trimmed).map { Int(($0 * 100).rounded()) }
        case .unknown: return nil
        }
    }
    private var canSave: Bool {
        !code.trimmingCharacters(in: .whitespaces).isEmpty && (valueMinorOrPercent ?? 0) > 0 && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Code (e.g. SUMMER20)", text: $code)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    TextField("Description (optional)", text: $description)
                } header: { Text("Coupon") }
                .listRowBackground(Color.appCard)

                Section {
                    Picker("Type", selection: $kind) {
                        Text("Percent off").tag(CouponKind.percent)
                        Text("Fixed amount").tag(CouponKind.fixed)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        TextField(kind == .percent ? "Percent (1–100)" : "Amount (e.g. 5.00)", text: $amount)
                            .keyboardType(.decimalPad)
                        Text(kind == .percent ? "%" : "USD").foregroundStyle(.appMuted)
                    }
                } header: { Text("Discount") }
                .listRowBackground(Color.appCard)

                Section {
                    Toggle("Set expiry", isOn: $hasExpiry).tint(.appPrimary)
                    if hasExpiry {
                        DatePicker("Expires", selection: $expiresAt, displayedComponents: .date)
                    }
                }
                .listRowBackground(Color.appCard)

                Section {
                    Button {
                        guard let value = valueMinorOrPercent else { return }
                        isSaving = true
                        let body = CreateCouponBody(
                            code: code.trimmingCharacters(in: .whitespaces).uppercased(),
                            description: description.isEmpty ? nil : description,
                            kind: kind, value: value, currency: "USD",
                            expiresAt: hasExpiry ? expiresAt : nil, isActive: true)
                        Task {
                            let ok = await onSave(body)
                            isSaving = false
                            if ok { dismiss() }
                        }
                    } label: {
                        HStack { if isSaving { ProgressView() }; Text("Create coupon") }
                    }
                    .buttonStyle(.refxPrimary).disabled(!canSave)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("New coupon").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct GiftCardEditSheet: View {
    let onSave: (CreateGiftCardBody) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var amount = ""
    @State private var note = ""
    @State private var hasExpiry = false
    @State private var expiresAt = Date().addingTimeInterval(60 * 60 * 24 * 365)
    @State private var isSaving = false

    private var balanceMinor: Int? {
        Double(amount.trimmingCharacters(in: .whitespaces)).map { Int(($0 * 100).rounded()) }
    }
    private var canSave: Bool { (balanceMinor ?? 0) > 0 && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Balance (e.g. 25.00)", text: $amount).keyboardType(.decimalPad)
                        Text("USD").foregroundStyle(.appMuted)
                    }
                    TextField("Note (optional)", text: $note)
                } header: { Text("Gift card") } footer: {
                    Text("A code is auto-generated. Balance and currency are fixed after creation.")
                }
                .listRowBackground(Color.appCard)

                Section {
                    Toggle("Set expiry", isOn: $hasExpiry).tint(.appPrimary)
                    if hasExpiry { DatePicker("Expires", selection: $expiresAt, displayedComponents: .date) }
                }
                .listRowBackground(Color.appCard)

                Section {
                    Button {
                        guard let balance = balanceMinor else { return }
                        isSaving = true
                        let body = CreateGiftCardBody(
                            initialBalanceMinor: balance, currency: "USD",
                            note: note.isEmpty ? nil : note,
                            expiresAt: hasExpiry ? expiresAt : nil, isActive: true)
                        Task {
                            let ok = await onSave(body)
                            isSaving = false
                            if ok { dismiss() }
                        }
                    } label: {
                        HStack { if isSaving { ProgressView() }; Text("Create gift card") }
                    }
                    .buttonStyle(.refxPrimary).disabled(!canSave)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("New gift card").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
