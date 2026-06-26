import SwiftUI

@MainActor
final class CreditViewModel: ObservableObject {
    @Published private(set) var state: LoadState<CreditBalance> = .idle
    private var service: BillingService?

    func bind(_ session: AppSession) { if service == nil { service = session.billing } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.credit()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }
}

struct CreditView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = CreditViewModel()

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { _ in false },
                emptyTitle: "No credit",
                retry: { Task { await model.load() } },
                content: { content($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 56) } } })
            .padding(16)
            .readableWidth()
        }
        .screenBackground()
        .navigationTitle("Store credit")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    @ViewBuilder private func content(_ credit: CreditBalance) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Available balance").font(.caption).foregroundStyle(.appMuted)
                    Text(credit.balance.formatted).font(.largeTitle.weight(.bold)).foregroundStyle(.appForeground)
                    Text("Credit is applied automatically at checkout.")
                        .font(.caption2).foregroundStyle(.appMuted)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("History", systemImage: "clock.arrow.circlepath")
                if credit.transactions.isEmpty {
                    Text("No credit activity yet.").font(.caption).foregroundStyle(.appMuted)
                } else {
                    ForEach(credit.transactions) { tx in
                        CreditRow(tx: tx)
                    }
                }
            }
        }
    }
}

private struct CreditRow: View {
    let tx: CreditTransaction

    var body: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tx.reason.label).font(.caption.weight(.medium)).foregroundStyle(.appForeground)
                    if let note = tx.note, !note.isEmpty {
                        Text(note).font(.caption2).foregroundStyle(.appMuted).lineLimit(1)
                    }
                    Text(tx.createdAt.formatted(.dateTime.month().day().year()))
                        .font(.caption2).foregroundStyle(.appMuted)
                }
                Spacer()
                Text(tx.signedLabel)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tx.isCredit ? .appSuccess : .appForeground)
            }
        }
    }
}
