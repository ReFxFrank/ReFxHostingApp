import SwiftUI

@MainActor
final class InvoiceDetailViewModel: ObservableObject {
    @Published var state: LoadState<Invoice> = .idle
    @Published var actionMessage: String?
    @Published var isPaying = false
    let invoiceId: String
    private var service: BillingService?

    init(invoiceId: String, preview: Invoice?) {
        self.invoiceId = invoiceId
        if let preview { state = .loaded(preview) }
    }

    func bind(_ session: AppSession) { if service == nil { service = session.billing } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.invoice(invoiceId)) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func pay() async {
        guard let service else { return }
        isPaying = true; actionMessage = nil
        defer { isPaying = false }
        do {
            let r = try await service.payInvoice(invoiceId)
            if r.paid { actionMessage = "Payment complete." }
            else if let urlStr = r.checkoutUrl, let url = URL(string: urlStr) {
                WebLink.open(url)
                actionMessage = "Finish the payment in your browser, then pull to refresh."
            } else { actionMessage = r.reason ?? "Payment couldn't be completed." }
            await load()
        }
        catch let error as APIError { actionMessage = error.userMessage }
        catch { actionMessage = "Couldn't start the payment." }
    }
}

struct InvoiceDetailView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: InvoiceDetailViewModel

    init(invoiceId: String, preview: Invoice? = nil) {
        _model = StateObject(wrappedValue: InvoiceDetailViewModel(invoiceId: invoiceId, preview: preview))
    }

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { _ in false },
                emptyTitle: "Not found",
                retry: { Task { await model.load() } },
                content: { detail($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 90) } } })
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(model.state.value?.number ?? "Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { model.bind(session); await model.load() }
    }

    @ViewBuilder private func detail(_ invoice: Invoice) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let message = model.actionMessage {
                Text(message).font(.footnote).foregroundStyle(.appPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(invoice.number).font(.headline.monospaced()).foregroundStyle(.appForeground)
                        Spacer()
                        StatusChip(text: invoice.state.label, color: InvoiceStateStyle.color(invoice.state))
                    }
                    Text("Created \(invoice.createdAt.formatted(.dateTime.month().day().year()))")
                        .font(.caption2).foregroundStyle(.appMuted)
                    if let paidAt = invoice.paidAt {
                        Text("Paid \(paidAt.formatted(.dateTime.month().day().year()))")
                            .font(.caption2).foregroundStyle(.appSuccess)
                    } else if let due = invoice.dueAt {
                        Text("Due \(due.formatted(.dateTime.month().day().year()))")
                            .font(.caption2).foregroundStyle(.appWarning)
                    }
                }
            }

            lineItemsCard(invoice)
            totalsCard(invoice)

            if let payments = invoice.payments, !payments.isEmpty {
                paymentsCard(payments)
            }

            // In-app card payment is disabled on public App Store builds
            // (Guideline 3.1.3 — invoices are settled on the web there); the full
            // invoice stays viewable, only the pay action is withheld.
            if invoice.isOpen && FeatureFlags.purchasingEnabled {
                Button(action: { Task { await model.pay() } }) {
                    HStack { if model.isPaying { ProgressView() }
                        Text(model.isPaying ? "Processing…" : "Pay \(invoice.outstanding.formatted)") }
                }
                .buttonStyle(.refxPrimary).disabled(model.isPaying)
            }
        }
    }

    private func lineItemsCard(_ invoice: Invoice) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Items", systemImage: "list.bullet")
                ForEach(invoice.lineItems ?? []) { item in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.description).font(.caption).foregroundStyle(.appForeground)
                            if item.quantity > 1 {
                                Text("×\(item.quantity)").font(.caption2).foregroundStyle(.appMuted)
                            }
                        }
                        Spacer()
                        Text(item.amount(in: invoice.currency).formatted)
                            .font(.caption.monospacedDigit()).foregroundStyle(.appForeground)
                    }
                    if item.id != invoice.lineItems?.last?.id { Divider().overlay(Color.appBorder) }
                }
            }
        }
    }

    private func totalsCard(_ invoice: Invoice) -> some View {
        GlassCard {
            VStack(spacing: 8) {
                totalRow("Subtotal", invoice.subtotal.formatted)
                if invoice.discountMinor > 0 {
                    totalRow("Discount" + (invoice.couponCode.map { " (\($0))" } ?? ""),
                             "−" + invoice.discount.formatted, color: .appSuccess)
                }
                if invoice.taxMinor > 0 {
                    totalRow(invoice.taxType ?? "Tax", invoice.tax.formatted)
                }
                Divider().overlay(Color.appBorder)
                totalRow("Total", invoice.total.formatted, bold: true)
                if invoice.amountPaidMinor > 0 && !invoice.isPaid {
                    totalRow("Paid", "−" + invoice.amountPaid.formatted, color: .appSuccess)
                    totalRow("Balance", invoice.outstanding.formatted, bold: true)
                }
            }
        }
    }

    private func totalRow(_ label: String, _ value: String, bold: Bool = false, color: Color = .appForeground) -> some View {
        let valueFont: Font = bold ? .subheadline.weight(.bold) : .caption
        return HStack {
            Text(label).font(bold ? .subheadline.weight(.semibold) : .caption).foregroundStyle(bold ? .appForeground : .appMuted)
            Spacer()
            Text(value).font(valueFont.monospacedDigit()).foregroundStyle(color)
        }
    }

    private func paymentsCard(_ payments: [InvoicePayment]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Payments", systemImage: "checkmark.seal")
                ForEach(payments) { payment in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(payment.gateway.capitalized).font(.caption).foregroundStyle(.appForeground)
                            Text(payment.createdAt.formatted(.dateTime.month().day().year()))
                                .font(.caption2).foregroundStyle(.appMuted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(payment.amount.formatted).font(.caption.monospacedDigit()).foregroundStyle(.appForeground)
                            StatusChip(text: payment.state.label,
                                       color: payment.state == .succeeded ? .appSuccess
                                            : payment.state == .failed ? .appDestructive : .appMuted)
                        }
                    }
                }
            }
        }
    }
}

/// Shared invoice-state → colour mapping.
enum InvoiceStateStyle {
    static func color(_ state: InvoiceState) -> Color {
        switch state {
        case .paid: return .appSuccess
        case .open: return .appWarning
        case .void, .uncollectible: return .appDestructive
        case .draft, .refunded, .unknown: return .appMuted
        }
    }
}

// MARK: - Invoice history list

@MainActor
final class InvoicesListViewModel: ObservableObject {
    @Published private(set) var invoices: [Invoice] = []
    @Published private(set) var state: LoadState<[Invoice]> = .idle
    private var service: BillingService?
    private var page = 1
    private var hasMore = true
    private var loading = false

    func bind(_ session: AppSession) { if service == nil { service = session.billing } }

    func reload() async {
        page = 1; hasMore = true; invoices = []
        if state.value == nil { state = .loading }
        await loadMore()
        if case .loading = state { state = .loaded(invoices) }
    }

    func loadMore() async {
        guard let service, hasMore, !loading else { return }
        loading = true; defer { loading = false }
        do {
            let pageResult = try await service.invoices(page: page)
            invoices += pageResult.items
            hasMore = pageResult.hasMore
            page += 1
            state = .loaded(invoices)
        } catch let error as APIError {
            if invoices.isEmpty { state = .failed(error) }
            hasMore = false
        } catch {
            if invoices.isEmpty { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
            hasMore = false
        }
    }

    func appeared(_ invoice: Invoice) async {
        if invoice.id == invoices.last?.id { await loadMore() }
    }
}

struct InvoicesListView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = InvoicesListViewModel()

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No invoices",
                emptyMessage: "Your invoices and receipts will appear here.",
                retry: { Task { await model.reload() } },
                content: { invoices in
                    LazyVStack(spacing: 10) {
                        ForEach(invoices) { invoice in
                            NavigationLink { InvoiceDetailView(invoiceId: invoice.id, preview: invoice) } label: {
                                InvoiceRow(invoice: invoice)
                            }
                            .buttonStyle(.plain)
                            .task { await model.appeared(invoice) }
                        }
                    }
                },
                skeleton: { VStack(spacing: 10) { ForEach(0..<6, id: \.self) { _ in SkeletonBlock(height: 64) } } })
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Invoices")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.reload() }
        .task { model.bind(session); if model.state.value == nil { await model.reload() } }
    }
}

private struct InvoiceRow: View {
    let invoice: Invoice
    var body: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(invoice.number).font(.subheadline.weight(.medium).monospaced()).foregroundStyle(.appForeground)
                    Text(invoice.createdAt.formatted(.dateTime.month().day().year()))
                        .font(.caption2).foregroundStyle(.appMuted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(invoice.total.formatted).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                    StatusChip(text: invoice.state.label, color: InvoiceStateStyle.color(invoice.state))
                }
            }
        }
    }
}
