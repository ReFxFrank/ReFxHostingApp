import SwiftUI

@MainActor
final class PaymentMethodsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[PaymentMethod]> = .idle
    @Published var actionError: String?
    private var service: BillingService?

    func bind(_ session: AppSession) { if service == nil { service = session.billing } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.paymentMethods()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func setDefault(_ method: PaymentMethod) async { await mutate { try await $0.setDefaultPaymentMethod(method.id) } }
    func delete(_ method: PaymentMethod) async { await mutate { try await $0.deletePaymentMethod(method.id) } }

    private func mutate(_ work: (BillingService) async throws -> Void) async {
        guard let service else { return }
        actionError = nil
        do { try await work(service); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Action failed. Try again." }
    }
}

struct PaymentMethodsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = PaymentMethodsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let actionError = model.actionError {
                    Text(actionError).font(.footnote).foregroundStyle(.appDestructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                AsyncStateView(
                    state: model.state,
                    isEmpty: { $0.isEmpty },
                    emptyTitle: "No payment methods",
                    emptyMessage: "Your card is saved automatically the first time you pay an invoice with Stripe.",
                    retry: { Task { await model.load() } },
                    content: { methods in
                        VStack(spacing: 10) {
                            ForEach(methods) { method in
                                PaymentMethodCard(method: method,
                                                  onMakeDefault: { Task { await model.setDefault(method) } },
                                                  onDelete: { Task { await model.delete(method) } })
                            }
                        }
                    },
                    skeleton: { VStack(spacing: 10) { ForEach(0..<2, id: \.self) { _ in SkeletonBlock(height: 72) } } })

                addCardNote
            }
            .padding(16)
            .readableWidth()
        }
        .screenBackground()
        .navigationTitle("Payment methods")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private var addCardNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(.appSecondary)
            Text("To add a card, pay an open invoice and choose card checkout — your card is saved for future payments and can be set as default here.")
                .font(.caption2).foregroundStyle(.appMuted)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct PaymentMethodCard: View {
    let method: PaymentMethod
    let onMakeDefault: () -> Void
    let onDelete: () -> Void
    @State private var confirmDelete = false

    private var icon: String { method.gateway == "paypal" ? "p.circle" : "creditcard" }

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(.appSecondary).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(method.displayLabel).font(.subheadline.weight(.medium)).foregroundStyle(.appForeground)
                    if let expiry = method.expiryLabel {
                        Text("Expires \(expiry)").font(.caption2).foregroundStyle(.appMuted)
                    }
                }
                Spacer()
                if method.isDefault { StatusChip(text: "Default", color: .appPrimary) }
            }
        }
        .contextMenu {
            if !method.isDefault {
                Button { onMakeDefault() } label: { Label("Set as default", systemImage: "checkmark.circle") }
            }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Remove", systemImage: "trash") }
        }
        .confirmationDialog("Remove \(method.displayLabel)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
    }
}
