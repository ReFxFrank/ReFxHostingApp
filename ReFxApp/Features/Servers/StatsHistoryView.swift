import SwiftUI
import Charts

@MainActor
final class StatsHistoryViewModel: ObservableObject {
    @Published private(set) var samples: [ServerStat] = []
    @Published private(set) var isLoading = false
    @Published var range: StatsRange = .h1
    @Published var errorMessage: String?

    let serverId: String
    private var service: ServersService?

    init(serverId: String) { self.serverId = serverId }

    func bind(_ session: AppSession) { if service == nil { service = session.servers } }

    func load() async {
        guard let service else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { samples = try await service.statsHistory(serverId, range: range) }
        catch let error as APIError { errorMessage = error.userMessage }
        catch { errorMessage = "Couldn't load history." }
    }
}

/// Resource history charts (CPU / memory / players) over a selectable window.
struct StatsHistoryView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: StatsHistoryViewModel

    init(serverId: String) { _model = StateObject(wrappedValue: StatsHistoryViewModel(serverId: serverId)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Range", selection: $model.range) {
                    ForEach(StatsRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.appDestructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if model.isLoading && model.samples.isEmpty {
                    SkeletonBlock(height: 200)
                } else if model.samples.isEmpty {
                    Text("No samples yet for this window.")
                        .font(.subheadline).foregroundStyle(.appMuted)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    chartCard("CPU", unit: "%", tint: .appPrimary) { $0.cpuPct }
                    chartCard("Memory", unit: "MB", tint: .appSuccess) { Double($0.memUsedMb) }
                    if model.samples.contains(where: { $0.players != nil }) {
                        chartCard("Players", unit: "", tint: .appWarning) { Double($0.players ?? 0) }
                    }
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Resource history")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.bind(session); if model.samples.isEmpty { await model.load() } }
        .onChange(of: model.range) { _ in Task { await model.load() } }
    }

    private func chartCard(_ title: String, unit: String, tint: Color,
                           value: @escaping (ServerStat) -> Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                Spacer()
                if let last = model.samples.last {
                    Text(caption(value(last), unit: unit)).font(.caption.monospacedDigit())
                        .foregroundStyle(.appMuted)
                }
            }
            Chart(model.samples) { sample in
                AreaMark(x: .value("Time", sample.recordedAt),
                         y: .value(title, value(sample)))
                    .foregroundStyle(tint.opacity(0.18))
                LineMark(x: .value("Time", sample.recordedAt),
                         y: .value(title, value(sample)))
                    .foregroundStyle(tint)
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: .automatic(includesZero: true))
            .frame(height: 160)
        }
        .padding(Theme.cardPadding)
        .cardSurface()
    }

    private func caption(_ v: Double, unit: String) -> String {
        let n = v >= 100 ? String(Int(v)) : String(format: "%.1f", v)
        return unit.isEmpty ? n : "\(n) \(unit)"
    }
}
