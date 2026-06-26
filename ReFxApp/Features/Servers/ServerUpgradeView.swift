import SwiftUI

@MainActor
final class ServerUpgradeViewModel: ObservableObject {
    @Published private(set) var state: LoadState<UpgradeOptions> = .idle
    @Published var selectedTierId: String?
    @Published var slots: Int = 1
    @Published var preview: UpgradePreview?
    @Published var previewing = false
    @Published var actionMessage: String?
    @Published var applying = false

    let serverId: String
    private var service: ServersService?

    init(serverId: String) { self.serverId = serverId }

    func bind(_ session: AppSession) { if service == nil { service = session.servers } }

    var options: UpgradeOptions? { state.value }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do {
            let opts = try await service.upgradeOptions(serverId)
            state = .loaded(opts)
            selectedTierId = opts.currentTierId
            slots = opts.slots
            preview = nil
        }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    /// Whether the current selection differs from the active plan.
    var hasChange: Bool {
        guard let opts = options else { return false }
        if opts.perSlot { return slots != opts.slots }
        return selectedTierId != opts.currentTierId && selectedTierId != nil
    }

    private var dto: UpgradeServerDTO {
        guard let opts = options else { return UpgradeServerDTO() }
        return opts.perSlot ? UpgradeServerDTO(slots: slots)
                            : UpgradeServerDTO(hardwareTierId: selectedTierId)
    }

    func selectTier(_ id: String) { selectedTierId = id; Task { await refreshPreview() } }
    func setSlots(_ n: Int) { slots = n; Task { await refreshPreview() } }

    func refreshPreview() async {
        guard let service, hasChange else { preview = nil; return }
        previewing = true; defer { previewing = false }
        do { preview = try await service.upgradePreview(serverId, dto) }
        catch { preview = nil }
    }

    /// Returns an invoice id to push (the `invoiced` case) so the caller can route to payment.
    func apply() async -> String? {
        guard let service, hasChange else { return nil }
        applying = true; actionMessage = nil
        defer { applying = false }
        do {
            let result = try await service.applyUpgrade(serverId, dto)
            switch result.kind {
            case .applied:
                actionMessage = "Your plan was updated."
                await load()
            case .scheduled:
                let when = result.effectiveAt.map { $0.formatted(.dateTime.month().day().year()) } ?? "the period end"
                actionMessage = "Downgrade scheduled for \(when)."
                await load()
            case .invoiced:
                await load()
                return result.invoiceId
            case .unknown:
                actionMessage = "Plan change submitted."
                await load()
            }
        }
        catch let error as APIError { actionMessage = error.userMessage }
        catch { actionMessage = "Couldn't apply the change." }
        return nil
    }

    func cancelPending() async {
        guard let service else { return }
        actionMessage = nil
        do { _ = try await service.cancelUpgrade(serverId); await load() }
        catch let error as APIError { actionMessage = error.userMessage }
        catch { actionMessage = "Couldn't cancel the change." }
    }
}

struct ServerUpgradeView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: ServerUpgradeViewModel
    @State private var payInvoiceId: String?

    init(serverId: String) {
        _model = StateObject(wrappedValue: ServerUpgradeViewModel(serverId: serverId))
    }

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { _ in false },
                emptyTitle: "Unavailable",
                retry: { Task { await model.load() } },
                content: { content($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 72) } } })
            .padding(16)
            .readableWidth()
        }
        .screenBackground()
        .navigationTitle("Change plan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(forInvoice: $payInvoiceId)
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    @ViewBuilder private func content(_ opts: UpgradeOptions) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let message = model.actionMessage {
                Text(message).font(.footnote).foregroundStyle(.appPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let pending = opts.pendingChange {
                PendingChangeBanner(pending: pending,
                                    onPay: { if let id = pending.invoiceId { payInvoiceId = id } },
                                    onCancel: { Task { await model.cancelPending() } })
            } else {
                currentPlanCard(opts)
                if opts.perSlot { slotPicker(opts) } else { tierPicker(opts) }
                previewCard(opts)
                confirmButton(opts)
            }
        }
    }

    private func currentPlanCard(_ opts: UpgradeOptions) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Current plan").font(.caption).foregroundStyle(.appMuted)
                Text(String(format: "%d vCPU · %dGB RAM · %dGB disk",
                            opts.cpuCores, opts.memoryMb / 1024, opts.diskMb / 1024))
                    .font(.subheadline.weight(.medium)).foregroundStyle(.appForeground)
                if opts.perSlot {
                    Text("\(opts.slots) slots · \(opts.perSlotAmount.formatted) each")
                        .font(.caption2).foregroundStyle(.appMuted)
                }
            }
        }
    }

    private func tierPicker(_ opts: UpgradeOptions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Choose a tier", systemImage: "cpu")
            ForEach(opts.tiers) { tier in
                TierOption(tier: tier,
                           currency: opts.currency,
                           isCurrent: tier.id == opts.currentTierId,
                           isSelected: tier.id == model.selectedTierId,
                           onTap: { model.selectTier(tier.id) })
            }
        }
    }

    private func slotPicker(_ opts: UpgradeOptions) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Slots", systemImage: "person.3")
                HStack {
                    Text("\(model.slots) slots").font(.title3.weight(.semibold)).foregroundStyle(.appForeground)
                    Spacer()
                    Stepper("", value: Binding(get: { model.slots },
                                               set: { model.setSlots($0) }),
                            in: opts.minSlots...opts.maxSlots, step: opts.slotStep)
                        .labelsHidden()
                }
                Text("\(opts.perSlotAmount.formatted) per slot · \(opts.minSlots)–\(opts.maxSlots) range")
                    .font(.caption2).foregroundStyle(.appMuted)
            }
        }
    }

    @ViewBuilder private func previewCard(_ opts: UpgradeOptions) -> some View {
        if model.hasChange {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("New plan").font(.caption).foregroundStyle(.appMuted)
                        Spacer()
                        if model.previewing { ProgressView().controlSize(.small) }
                    }
                    if let preview = model.preview {
                        HStack {
                            Text("Recurring").font(.caption).foregroundStyle(.appMuted)
                            Spacer()
                            Text("\(preview.newRecurring.formatted)\(intervalSuffix(preview.interval))")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                        }
                        if preview.isIncrease {
                            row("Increase", "+" + preview.delta.formatted, .appWarning)
                            row("Due today (prorated)",
                                preview.dueToday(prorationFactor: opts.prorationFactor).formatted, .appForeground, bold: true)
                        } else if preview.isDowngrade {
                            row("Decrease", "−" + preview.delta.formatted, .appSuccess)
                            Text("Takes effect at your next renewal; no charge today.")
                                .font(.caption2).foregroundStyle(.appMuted)
                        } else {
                            Text("No change in price.").font(.caption2).foregroundStyle(.appMuted)
                        }
                    } else if !model.previewing {
                        Text("Select a different plan to see pricing.").font(.caption2).foregroundStyle(.appMuted)
                    }
                }
            }
        }
    }

    private func confirmButton(_ opts: UpgradeOptions) -> some View {
        Button {
            Task { if let invoiceId = await model.apply() { payInvoiceId = invoiceId } }
        } label: {
            HStack { if model.applying { ProgressView() }; Text(confirmTitle) }
        }
        .buttonStyle(.refxPrimary)
        .disabled(!model.hasChange || model.applying || model.previewing)
    }

    private var confirmTitle: String {
        guard let preview = model.preview else { return "Confirm change" }
        if preview.isDowngrade { return "Schedule downgrade" }
        if preview.isIncrease { return "Upgrade & pay" }
        return "Confirm change"
    }

    private func row(_ label: String, _ value: String, _ color: Color, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.appMuted)
            Spacer()
            Text(value).font(bold ? .subheadline.weight(.bold) : .caption).foregroundStyle(color)
        }
    }

    private func intervalSuffix(_ interval: String) -> String {
        BillingInterval(rawValue: interval)?.shortSuffix ?? ""
    }
}

private struct TierOption: View {
    let tier: UpgradeOptions.Tier
    let currency: String
    let isCurrent: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? .appPrimary : .appMuted)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tier.name).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                        if tier.isRecommended { StatusChip(text: "Recommended", color: .appSuccess) }
                        if isCurrent { StatusChip(text: "Current", color: .appMuted) }
                    }
                    Text(String(format: "%.1f vCPU · %dGB RAM · %dGB disk",
                                tier.cpuCores, tier.memoryMb / 1024, tier.diskMb / 1024))
                        .font(.caption2).foregroundStyle(.appMuted)
                    if let players = tier.recommendedPlayers {
                        Text("~\(players) players").font(.caption2).foregroundStyle(.appMuted)
                    }
                }
                Spacer()
                if let price = tier.price(currency: currency) {
                    Text(price.formatted).font(.caption.weight(.semibold)).foregroundStyle(.appAccentText)
                }
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? Color.appPrimary.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct PendingChangeBanner: View {
    let pending: UpgradeOptions.PendingChange
    let onPay: () -> Void
    let onCancel: () -> Void
    @State private var confirmCancel = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: pending.isUpgrade ? "creditcard" : "clock")
                        .foregroundStyle(.appWarning)
                    Text(pending.isUpgrade ? "Upgrade awaiting payment" : "Downgrade scheduled")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                }
                if pending.isUpgrade {
                    Text("Pay the open invoice to apply your new plan.")
                        .font(.caption).foregroundStyle(.appMuted)
                    if pending.invoiceId != nil {
                        Button("Pay invoice", action: onPay).buttonStyle(.refxPrimary)
                    }
                } else if let when = pending.effectiveAt {
                    Text("Applies \(when.formatted(.dateTime.month().day().year())) at your next renewal.")
                        .font(.caption).foregroundStyle(.appMuted)
                }
                Button("Cancel pending change") { confirmCancel = true }
                    .buttonStyle(.refxSecondary)
            }
        }
        .confirmationDialog("Cancel the pending plan change?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel change", role: .destructive, action: onCancel)
            Button("Keep it", role: .cancel) {}
        }
    }
}

private extension View {
    /// Pushes the native invoice screen when an `invoiced` upgrade needs payment.
    func navigationDestination(forInvoice id: Binding<String?>) -> some View {
        navigationDestination(isPresented: Binding(
            get: { id.wrappedValue != nil },
            set: { if !$0 { id.wrappedValue = nil } }
        )) {
            if let invoiceId = id.wrappedValue { InvoiceDetailView(invoiceId: invoiceId) }
        }
    }
}
