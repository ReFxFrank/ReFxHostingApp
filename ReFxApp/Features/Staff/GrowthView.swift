import SwiftUI

@MainActor
final class GrowthViewModel: ObservableObject {
    @Published private(set) var state: LoadState<GrowthReport> = .idle
    @Published var days = 30
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.growth(days: days)) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }
}

struct GrowthView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = GrowthViewModel()

    private let ranges = [7, 30, 90]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Picker("Range", selection: $model.days) {
                    ForEach(ranges, id: \.self) { Text("\($0)d").tag($0) }
                }
                .pickerStyle(.segmented)

                AsyncStateView(
                    state: model.state,
                    isEmpty: { _ in false },
                    emptyTitle: "No data",
                    retry: { Task { await model.load() } },
                    content: { content($0) },
                    skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 80) } } })
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Growth")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.days) { _ in Task { await model.load() } }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private func content(_ g: GrowthReport) -> some View {
        VStack(spacing: 12) {
            GlassCard {
                HStack(spacing: 12) {
                    total("\(g.totals.signups)", "Signups")
                    total("\(g.totals.payers)", "Payers")
                    total(Money(minorUnits: g.totals.revenueMinor, currency: "USD").formatted, "Revenue")
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader("Channels", systemImage: "arrow.triangle.branch")
                    ForEach(g.channels) { c in
                        HStack {
                            Text(c.channel).font(.callout).foregroundStyle(.appForeground).lineLimit(1)
                            Spacer()
                            Text("\(c.signups) signups · \(c.payers) paid")
                                .font(.caption2).foregroundStyle(.appMuted)
                            Text(Money(minorUnits: c.revenueMinor, currency: "USD").formatted)
                                .font(.caption.monospacedDigit()).foregroundStyle(.appSuccess)
                        }
                    }
                }
            }
            if !g.landings.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Top landings", systemImage: "arrow.down.right.circle")
                        ForEach(g.landings) { l in
                            HStack {
                                Text(l.landing).font(.caption.monospaced()).foregroundStyle(.appForeground).lineLimit(1)
                                Spacer()
                                Text("\(l.signups)").font(.caption.monospacedDigit()).foregroundStyle(.appMuted)
                            }
                        }
                    }
                }
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader("Referrals", systemImage: "gift")
                    HStack(spacing: 12) {
                        total("\(g.referral.signups)", "Referred")
                        total("\(g.referral.converted)", "Converted")
                        total(Money(minorUnits: g.referral.creditIssuedMinor, currency: "USD").formatted, "Credit")
                    }
                }
            }
        }
    }

    private func total(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(.appForeground)
            Text(label).font(.caption2).foregroundStyle(.appMuted)
        }
        .frame(maxWidth: .infinity)
    }
}
