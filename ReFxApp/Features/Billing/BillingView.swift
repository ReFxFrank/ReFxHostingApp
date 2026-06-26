import SwiftUI

@MainActor
final class BillingViewModel: ObservableObject {
    @Published var credit: LoadState<CreditBalance> = .idle
    @Published var subscriptions: LoadState<[SubscriptionListItem]> = .idle
    @Published var invoices: LoadState<[Invoice]> = .idle
    @Published var actionMessage: String?
    @Published var busyInvoiceId: String?

    private var service: BillingService?

    func bind(_ session: AppSession) { if service == nil { service = session.billing } }

    func loadAll() async {
        guard let service else { return }
        if credit.value == nil { credit = .loading }
        if subscriptions.value == nil { subscriptions = .loading }
        if invoices.value == nil { invoices = .loading }
        async let c = result { try await service.credit() }
        async let s = result { try await service.subscriptions() }
        async let i = result { try await service.invoices().items }
        credit = await c
        subscriptions = await s
        invoices = await i
    }

    var openInvoices: [Invoice] { (invoices.value ?? []).filter { $0.isOpen } }

    func pay(_ invoice: Invoice) async {
        guard let service else { return }
        busyInvoiceId = invoice.id; actionMessage = nil
        defer { busyInvoiceId = nil }
        do {
            let r = try await service.payInvoice(invoice.id)
            handlePay(r)
            await loadAll()
        }
        catch let error as APIError { actionMessage = error.userMessage }
        catch { actionMessage = "Couldn't start the payment." }
    }

    func cancel(_ sub: SubscriptionListItem) async { await mutateSub { try await $0.cancelSubscription(sub.id) } }
    func resume(_ sub: SubscriptionListItem) async { await mutateSub { try await $0.resumeSubscription(sub.id) } }

    private func handlePay(_ r: PayInvoiceResult) {
        if r.paid {
            actionMessage = "Payment complete."
        } else if let urlStr = r.checkoutUrl, let url = URL(string: urlStr) {
            WebLink.open(url)
            actionMessage = "Finish the payment in your browser, then pull to refresh."
        } else {
            actionMessage = r.reason ?? "Payment couldn't be completed."
        }
    }

    private func mutateSub(_ work: (BillingService) async throws -> Void) async {
        guard let service else { return }
        actionMessage = nil
        do { try await work(service); await loadAll() }
        catch let error as APIError { actionMessage = error.userMessage }
        catch { actionMessage = "Action failed. Try again." }
    }

    private func result<T>(_ work: () async throws -> T) async -> LoadState<T> {
        do { return .loaded(try await work()) }
        catch let error as APIError { return .failed(error) }
        catch { return .failed(.network(isOffline: false, underlying: "\(error)")) }
    }
}

struct BillingView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = BillingViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let message = model.actionMessage {
                    Text(message).font(.footnote).foregroundStyle(.appPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                summaryCards
                openInvoicesSection
                subscriptionsSection
                links
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Billing")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.loadAll() }
        .task { model.bind(session); if model.credit.value == nil { await model.loadAll() } }
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Store credit",
                     value: model.credit.value?.balance.formatted ?? "—",
                     systemImage: "creditcard.and.123")
            StatCard(title: "Open invoices",
                     value: "\(model.openInvoices.count)",
                     systemImage: "doc.text")
        }
    }

    @ViewBuilder private var openInvoicesSection: some View {
        if !model.openInvoices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Open invoices", systemImage: "exclamationmark.circle")
                ForEach(model.openInvoices) { invoice in
                    OpenInvoiceCard(invoice: invoice,
                                    busy: model.busyInvoiceId == invoice.id,
                                    onPay: { Task { await model.pay(invoice) } })
                }
            }
        }
    }

    @ViewBuilder private var subscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Subscriptions", systemImage: "arrow.triangle.2.circlepath")
            AsyncStateView(
                state: model.subscriptions,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No subscriptions",
                emptyMessage: "Plans you purchase appear here.",
                retry: { Task { await model.loadAll() } },
                content: { subs in
                    VStack(spacing: 10) {
                        ForEach(subs) { sub in
                            SubscriptionCard(sub: sub,
                                             onCancel: { Task { await model.cancel(sub) } },
                                             onResume: { Task { await model.resume(sub) } })
                        }
                    }
                },
                skeleton: { VStack(spacing: 10) { ForEach(0..<2, id: \.self) { _ in SkeletonBlock(height: 96) } } })
        }
    }

    private var links: some View {
        VStack(spacing: 10) {
            NavigationLink { InvoicesListView() } label: {
                ManageRow(icon: "doc.text", title: "Invoice history", subtitle: "All invoices & receipts")
            }.buttonStyle(.plain)
            NavigationLink { PaymentMethodsView() } label: {
                ManageRow(icon: "creditcard", title: "Payment methods", subtitle: "Cards & PayPal")
            }.buttonStyle(.plain)
            NavigationLink { CreditView() } label: {
                ManageRow(icon: "clock.arrow.circlepath", title: "Store credit", subtitle: "Balance & history")
            }.buttonStyle(.plain)
        }
    }
}

private struct OpenInvoiceCard: View {
    let invoice: Invoice
    let busy: Bool
    let onPay: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    NavigationLink { InvoiceDetailView(invoiceId: invoice.id, preview: invoice) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invoice.number).font(.subheadline.weight(.semibold).monospaced())
                                .foregroundStyle(.appForeground)
                            if let due = invoice.dueAt {
                                Text("due \(due.formatted(.dateTime.month().day().year()))")
                                    .font(.caption2).foregroundStyle(.appMuted)
                            }
                        }
                    }.buttonStyle(.plain)
                    Spacer()
                    Text(invoice.outstanding.formatted).font(.subheadline.weight(.bold)).foregroundStyle(.appForeground)
                }
                // In-app card payment is disabled on public App Store builds
                // (Guideline 3.1.3 — invoices are settled on the web there); the
                // invoice stays visible, only the pay action is withheld.
                if FeatureFlags.purchasingEnabled {
                    Button(action: onPay) {
                        HStack { if busy { ProgressView() }; Text(busy ? "Processing…" : "Pay now") }
                    }
                    .buttonStyle(.refxPrimary).disabled(busy)
                }
            }
        }
    }
}

private struct SubscriptionCard: View {
    let sub: SubscriptionListItem
    let onCancel: () -> Void
    let onResume: () -> Void
    @State private var confirmCancel = false

    private var stateColor: Color {
        switch sub.state {
        case .active, .trialing: return .appSuccess
        case .pastDue, .suspended: return .appWarning
        case .canceled, .expired, .unknown: return .appMuted
        }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(sub.product.name).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                    Spacer()
                    StatusChip(text: sub.state.label, color: stateColor)
                }
                HStack(spacing: 8) {
                    if let tier = sub.hardwareTier { Text(tier.name).font(.caption2).foregroundStyle(.appMuted) }
                    Text(sub.renewalLabel).font(.caption).foregroundStyle(.appAccentText)
                    Spacer()
                }
                if sub.cancelAtPeriodEnd {
                    Text("Cancels \(sub.currentPeriodEnd.formatted(.dateTime.month().day().year()))")
                        .font(.caption2).foregroundStyle(.appWarning)
                } else if sub.state == .active {
                    Text("Renews \(sub.currentPeriodEnd.formatted(.dateTime.month().day().year()))")
                        .font(.caption2).foregroundStyle(.appMuted)
                }
                if !sub.servers.isEmpty {
                    Text(sub.servers.map(\.name).joined(separator: ", "))
                        .font(.caption2).foregroundStyle(.appMuted).lineLimit(1)
                }
                actionRow
            }
        }
    }

    @ViewBuilder private var actionRow: some View {
        if sub.cancelAtPeriodEnd {
            Button("Resume subscription", action: onResume)
                .buttonStyle(.refxSecondary)
        } else if sub.state == .active || sub.state == .trialing || sub.state == .pastDue {
            Button("Cancel") { confirmCancel = true }
                .buttonStyle(.refxSecondary)
                .confirmationDialog("Cancel \(sub.product.name)?", isPresented: $confirmCancel, titleVisibility: .visible) {
                    Button("Cancel at period end", role: .destructive, action: onCancel)
                    Button("Keep subscription", role: .cancel) {}
                } message: {
                    Text("Your servers stay active until \(sub.currentPeriodEnd.formatted(.dateTime.month().day().year())).")
                }
        }
    }
}
