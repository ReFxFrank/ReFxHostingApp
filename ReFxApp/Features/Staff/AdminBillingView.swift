import SwiftUI

@MainActor
final class AdminBillingViewModel: ObservableObject {
    @Published var summary: LoadState<BillingSummary> = .idle
    @Published var invoices: [AdminBillingInvoice] = []
    @Published var orders: [AdminOrder] = []
    @Published var payments: [Payment] = []
    @Published var invoiceState: InvoiceState? = nil
    @Published var actionError: String?

    private var service: StaffService?
    private var invoicePage = 1, orderPage = 1, paymentPage = 1
    private var invoiceMore = true, orderMore = true, paymentMore = true
    private var loading = false

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func loadSummary() async {
        guard let service else { return }
        if summary.value == nil { summary = .loading }
        do { summary = .loaded(try await service.billingSummary()) }
        catch let error as APIError { summary = .failed(error) }
        catch { summary = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    // Invoices
    func reloadInvoices() async {
        invoicePage = 1; invoiceMore = true; invoices = []
        await loadMoreInvoices()
    }
    func loadMoreInvoices() async {
        guard let service, invoiceMore, !loading else { return }
        loading = true; defer { loading = false }
        do {
            let page = try await service.invoices(page: invoicePage, state: invoiceState)
            invoices += page.items; invoiceMore = page.hasMore; invoicePage += 1
        } catch { invoiceMore = false }
    }
    func invoiceAppeared(_ invoice: AdminBillingInvoice) async {
        if invoice.id == invoices.last?.id { await loadMoreInvoices() }
    }
    func voidInvoice(_ inv: AdminBillingInvoice) async { await run { try await $0.voidInvoice(inv.id) }; await reloadInvoices() }
    func markPaid(_ inv: AdminBillingInvoice) async { await run { try await $0.markInvoicePaid(inv.id) }; await reloadInvoices() }
    func deleteInvoice(_ inv: AdminBillingInvoice) async { await run { try await $0.deleteInvoice(inv.id) }; await reloadInvoices() }

    // Orders
    func reloadOrders() async {
        orderPage = 1; orderMore = true; orders = []
        await loadMoreOrders()
    }
    func loadMoreOrders() async {
        guard let service, orderMore, !loading else { return }
        loading = true; defer { loading = false }
        do {
            let page = try await service.orders(page: orderPage)
            orders += page.items; orderMore = page.hasMore; orderPage += 1
        } catch { orderMore = false }
    }
    func orderAppeared(_ order: AdminOrder) async {
        if order.id == orders.last?.id { await loadMoreOrders() }
    }
    func deleteOrder(_ order: AdminOrder) async { await run { try await $0.deleteOrder(order.id) }; await reloadOrders() }

    // Payments
    func reloadPayments() async {
        paymentPage = 1; paymentMore = true; payments = []
        await loadMorePayments()
    }
    func loadMorePayments() async {
        guard let service, paymentMore, !loading else { return }
        loading = true; defer { loading = false }
        do {
            let page = try await service.payments(page: paymentPage)
            payments += page.items; paymentMore = page.hasMore; paymentPage += 1
        } catch { paymentMore = false }
    }
    func paymentAppeared(_ payment: Payment) async {
        if payment.id == payments.last?.id { await loadMorePayments() }
    }

    private func run(_ work: (StaffService) async throws -> Void) async {
        guard let service else { return }
        actionError = nil
        do { try await work(service) }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Action failed. Try again." }
    }
}

struct AdminBillingView: View {
    enum Tab: String, CaseIterable { case summary = "Summary", invoices = "Invoices", orders = "Orders", payments = "Payments" }

    @EnvironmentObject private var session: AppSession
    @StateObject private var model = AdminBillingViewModel()
    @State private var tab: Tab = .summary

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
                case .summary: summaryTab
                case .invoices: invoicesTab
                case .orders: ordersTab
                case .payments: paymentsTab
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Billing")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.bind(session); if model.summary.value == nil { await model.loadSummary() } }
        .onChange(of: tab) { newTab in Task { await loadTab(newTab) } }
    }

    private func loadTab(_ tab: Tab) async {
        switch tab {
        case .summary: if model.summary.value == nil { await model.loadSummary() }
        case .invoices: if model.invoices.isEmpty { await model.reloadInvoices() }
        case .orders: if model.orders.isEmpty { await model.reloadOrders() }
        case .payments: if model.payments.isEmpty { await model.reloadPayments() }
        }
    }

    // MARK: Summary

    private var summaryTab: some View {
        AsyncStateView(
            state: model.summary,
            isEmpty: { _ in false },
            emptyTitle: "No data",
            retry: { Task { await model.loadSummary() } },
            content: { s in
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(title: "Revenue", value: s.revenue.formatted, systemImage: "dollarsign.circle")
                    StatCard(title: "Outstanding", value: s.outstanding.formatted, systemImage: "hourglass")
                    StatCard(title: "Active subs", value: "\(s.activeSubscriptions)", systemImage: "arrow.triangle.2.circlepath")
                    StatCard(title: "Open invoices", value: "\(s.openInvoices)", systemImage: "doc.text")
                    StatCard(title: "Paid invoices", value: "\(s.paidInvoices)", systemImage: "checkmark.seal")
                }
            },
            skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 80) } } })
    }

    // MARK: Invoices

    private var invoicesTab: some View {
        VStack(spacing: 12) {
            Menu {
                Button("All states") { model.invoiceState = nil; Task { await model.reloadInvoices() } }
                ForEach([InvoiceState.open, .paid, .draft, .void, .uncollectible, .refunded], id: \.self) { state in
                    Button(state.label) { model.invoiceState = state; Task { await model.reloadInvoices() } }
                }
            } label: {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text(model.invoiceState?.label ?? "All states")
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .font(.caption).foregroundStyle(.appPrimary)
                .padding(10).frame(maxWidth: .infinity)
                .background(Color.appCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if model.invoices.isEmpty {
                Text("No invoices.").font(.caption).foregroundStyle(.appMuted).padding(.top, 12)
            } else {
                ForEach(model.invoices) { invoice in
                    InvoiceCard(invoice: invoice,
                                onVoid: { Task { await model.voidInvoice(invoice) } },
                                onMarkPaid: { Task { await model.markPaid(invoice) } },
                                onDelete: { Task { await model.deleteInvoice(invoice) } })
                        .task { await model.invoiceAppeared(invoice) }
                }
            }
        }
    }

    // MARK: Orders

    private var ordersTab: some View {
        VStack(spacing: 12) {
            if model.orders.isEmpty {
                Text("No orders.").font(.caption).foregroundStyle(.appMuted).padding(.top, 12)
            } else {
                ForEach(model.orders) { order in
                    OrderCard(order: order, onDelete: { Task { await model.deleteOrder(order) } })
                        .task { await model.orderAppeared(order) }
                }
            }
        }
    }

    // MARK: Payments

    private var paymentsTab: some View {
        VStack(spacing: 12) {
            if model.payments.isEmpty {
                Text("No payments.").font(.caption).foregroundStyle(.appMuted).padding(.top, 12)
            } else {
                ForEach(model.payments) { payment in
                    PaymentCard(payment: payment)
                        .task { await model.paymentAppeared(payment) }
                }
            }
        }
    }
}

private struct InvoiceCard: View {
    let invoice: AdminBillingInvoice
    let onVoid: () -> Void
    let onMarkPaid: () -> Void
    let onDelete: () -> Void
    @State private var confirmDelete = false

    private var stateColor: Color {
        switch invoice.state {
        case .paid: return .appSuccess
        case .open: return .appWarning
        case .void, .uncollectible: return .appDestructive
        default: return .appMuted
        }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(invoice.number).font(.subheadline.weight(.semibold).monospaced()).foregroundStyle(.appForeground)
                    Spacer()
                    Text(invoice.total.formatted).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                }
                HStack(spacing: 8) {
                    StatusChip(text: invoice.state.label, color: stateColor)
                    if let user = invoice.user { Text(user.email).font(.caption2).foregroundStyle(.appMuted).lineLimit(1) }
                    Spacer()
                    Text(invoice.createdAt.formatted(.dateTime.month().day().year()))
                        .font(.caption2).foregroundStyle(.appMuted)
                }
            }
        }
        .contextMenu {
            if invoice.state != .paid { Button { onMarkPaid() } label: { Label("Mark paid", systemImage: "checkmark.circle") } }
            if invoice.state != .void && invoice.state != .paid {
                Button { onVoid() } label: { Label("Void", systemImage: "xmark.circle") }
            }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        }
        .confirmationDialog("Delete invoice \(invoice.number)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct OrderCard: View {
    let order: AdminOrder
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(order.product?.name ?? "Subscription").font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                    Spacer()
                    StatusChip(text: order.state.label, color: order.state == .active ? .appSuccess : .appMuted)
                }
                HStack(spacing: 8) {
                    if let user = order.user { Text(user.email).font(.caption2).foregroundStyle(.appMuted).lineLimit(1) }
                    Spacer()
                    if let end = order.currentPeriodEnd {
                        Text("renews \(end.formatted(.dateTime.month().day()))").font(.caption2).foregroundStyle(.appMuted)
                    }
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        }
        .confirmationDialog("Delete this order?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Orders with active servers can't be deleted.")
        }
    }
}

private struct PaymentCard: View {
    let payment: Payment

    private var stateColor: Color {
        switch payment.state {
        case .succeeded: return .appSuccess
        case .pending: return .appWarning
        case .failed: return .appDestructive
        case .refunded, .unknown: return .appMuted
        }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(payment.amount.formatted).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                    Spacer()
                    StatusChip(text: payment.state.label, color: stateColor)
                }
                HStack(spacing: 8) {
                    Text(payment.gateway.capitalized).font(.caption2).foregroundStyle(.appSecondary)
                    Text(payment.invoice.number).font(.caption2.monospaced()).foregroundStyle(.appMuted)
                    Spacer()
                    Text(payment.createdAt.formatted(.dateTime.month().day())).font(.caption2).foregroundStyle(.appMuted)
                }
                if let reason = payment.failureReason, !reason.isEmpty {
                    Text(reason).font(.caption2).foregroundStyle(.appDestructive).lineLimit(2)
                }
            }
        }
    }
}
