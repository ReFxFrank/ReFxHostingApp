import SwiftUI

/// Glance-first home: every server with a live state pill + key resource. Down /
/// suspended / crashed servers are surfaced loudly at the top.
struct ServersListView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = ServersListViewModel()

    var body: some View {
        NavigationStack {
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No servers yet",
                emptyMessage: "Servers you own or help manage will appear here.",
                retry: { Task { await model.load() } },
                content: { _ in serverList },
                skeleton: { skeletonList })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .navigationTitle("Servers")
            .toolbar { attentionBadge }
            .searchable(text: $model.searchText, prompt: "Search servers")
            .onSubmit(of: .search) { Task { await model.load() } }
            .refreshable { await model.refresh() }
        }
        .task {
            model.bind(session.servers)
            if model.state.value == nil { await model.load() }
            // Live-refresh while visible so state pills don't go stale (the web
            // panel refetches on a similar interval). Cancelled on disappear.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                if Task.isCancelled { break }
                await model.refresh()
            }
        }
    }

    private var serverList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if model.attentionCount > 0 {
                    AttentionBanner(count: model.attentionCount)
                }
                ForEach(model.sortedServers) { server in
                    NavigationLink {
                        ServerDetailView(serverId: server.id, preview: server)
                    } label: {
                        ServerRow(server: server)
                    }
                    .buttonStyle(.plain)
                    .task { await model.loadMoreIfNeeded(currentItem: server) }
                }
            }
            .padding(16)
        }
    }

    private var skeletonList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        SkeletonBlock(height: 18)
                        SkeletonBlock(height: 12)
                    }
                    .padding()
                    .cardSurface()
                }
            }
            .padding(16)
        }
    }

    @ToolbarContentBuilder
    private var attentionBadge: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if model.attentionCount > 0 {
                Label("\(model.attentionCount)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.appDestructive)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

struct AttentionBanner: View {
    let count: Int
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("\(count) server\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") attention")
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(.appDestructive)
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .fill(Color.appDestructive.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .strokeBorder(Color.appDestructive.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

struct ServerRow: View {
    let server: Server

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(server.name).font(.headline).foregroundStyle(.appForeground)
                        .lineLimit(1)
                    Text(server.gameName).font(.caption).foregroundStyle(.appMuted)
                        .lineLimit(1)
                }
                Spacer()
                StatePill(state: server.state)
            }
            HStack(spacing: 16) {
                if let connection = server.connectionString {
                    Label(connection, systemImage: "network")
                        .font(.caption.monospaced()).foregroundStyle(.appMuted)
                        .lineLimit(1)
                }
                Spacer()
                if let mem = server.memoryMb {
                    Label("\(mem) MB", systemImage: "memorychip")
                        .font(.caption).foregroundStyle(.appMuted)
                }
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(elevated: server.state.needsAttention)
        .overlay(alignment: .leading) {
            if server.state.needsAttention {
                Rectangle().fill(Color.appDestructive)
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(server.name), \(server.gameName), \(server.state.label)\(server.connectionString.map { ", \($0)" } ?? "")")
        .accessibilityHint("Opens server details")
    }
}
