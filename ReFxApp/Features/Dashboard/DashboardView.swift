import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var state: LoadState<DashboardSummary> = .idle
    private var service: DashboardService?

    func bind(_ session: AppSession) {
        if service == nil { service = session.dashboard }
    }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.summary()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func refresh() async { await load() }
}

/// Client-area home, mirroring the web `/dashboard`: welcome header, a
/// payment-required banner, active platform alerts, allocated-resource stat
/// cards, and a quick list of your servers.
struct DashboardView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var config: AppConfig
    @StateObject private var model = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                AsyncStateView(
                    state: model.state,
                    isEmpty: { _ in false },
                    retry: { Task { await model.load() } },
                    content: { summary in content(summary) },
                    skeleton: { skeleton })
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(greeting)
            .refreshable { await model.refresh() }
        }
        .task {
            model.bind(session)
            if model.state.value == nil { await model.load() }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                if Task.isCancelled { break }
                await model.refresh()
            }
        }
    }

    private var greeting: String {
        if let name = session.currentUser?.firstName, !name.isEmpty { return "Hi, \(name)" }
        return "Overview"
    }

    private func content(_ summary: DashboardSummary) -> some View {
        let active = summary.servers.filter {
            $0.state != .suspended && $0.state != .pendingPayment
        }.count
        let pending = summary.servers.filter { $0.state == .pendingPayment }.count
        let cpu = summary.servers.reduce(0.0) { $0 + ($1.cpuCores ?? 0) }
        let mem = summary.servers.reduce(0) { $0 + ($1.memoryMb ?? 0) }
        let disk = summary.servers.reduce(0) { $0 + ($1.diskMb ?? 0) }

        return VStack(spacing: 16) {
            if summary.billing.openInvoices > 0 || pending > 0 {
                PaymentBanner(openInvoices: summary.billing.openInvoices, pending: pending) {
                    WebLink.open(config.webOrigin, path: "billing")
                }
            }

            ForEach(summary.alerts.filter { $0.isActive }) { alert in
                AlertBanner(alert: alert)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(title: "Active servers", value: "\(active)",
                         systemImage: "server.rack")
                StatCard(title: "Total servers", value: "\(summary.servers.count)",
                         systemImage: "square.stack.3d.up")
                StatCard(title: "Allocated vCPU", value: cpu.clean,
                         systemImage: "cpu")
                StatCard(title: "Allocated RAM", value: Format.bytes(Double(mem) * 1_048_576),
                         systemImage: "memorychip")
            }

            if !summary.servers.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Your servers", systemImage: "server.rack") {
                        Text("\(Format.bytes(Double(disk) * 1_048_576)) disk")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.appMuted)
                    }
                    .padding(.horizontal, 4)
                    ForEach(summary.servers.prefix(8)) { server in
                        NavigationLink {
                            ServerDetailView(serverId: server.id, preview: server)
                        } label: { ServerRow(server: server) }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var skeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 64) }
        }
    }
}

struct PaymentBanner: View {
    let openInvoices: Int
    let pending: Int
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Payment required").font(.subheadline.weight(.semibold))
                Spacer()
            }
            Text(message).font(.caption).foregroundStyle(.appMuted)
            Button(action: action) {
                Label("Pay now", systemImage: "creditcard")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent).tint(.appWarning).controlSize(.small)
        }
        .foregroundStyle(.appWarning)
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .fill(Color.appWarning.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .strokeBorder(Color.appWarning.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var message: String {
        var parts: [String] = []
        if pending > 0 { parts.append("\(pending) server\(pending == 1 ? "" : "s") awaiting payment.") }
        if openInvoices > 0 { parts.append("\(openInvoices) open invoice\(openInvoices == 1 ? "" : "s").") }
        return parts.joined(separator: " ")
    }
}

struct AlertBanner: View {
    let alert: PlatformAlert
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.bubble").foregroundStyle(.appWarning)
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                Text(alert.body).font(.caption).foregroundStyle(.appMuted)
            }
            Spacer()
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .fill(Color.appWarning.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .strokeBorder(Color.appWarning.opacity(0.30), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

private extension Double {
    /// Drop a trailing ".0" for whole numbers (e.g. vCPU "2" not "2.0").
    var clean: String {
        self == rounded() ? String(Int(self)) : String(format: "%.1f", self)
    }
}
