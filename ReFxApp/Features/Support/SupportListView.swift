import SwiftUI

/// Support tab placeholder for Phase 1. The full helpdesk (ticket list, thread,
/// reply, create) lands in Phase 2/3 against `support.controller.ts`
/// (`GET/POST /support/tickets`, `/support/tickets/:id/messages`).
struct SupportListView: View {
    @EnvironmentObject private var config: AppConfig

    var body: some View {
        NavigationStack {
            ComingSoonView(
                icon: "lifepreserver",
                title: "Support",
                message: "Open and reply to support tickets here. Coming in the next update.",
                actionTitle: "Open helpdesk on the web",
                action: { WebLink.open(config.webOrigin, path: "support") })
            .navigationTitle("Support")
        }
    }
}

struct ComingSoonView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 48)).foregroundStyle(.appPrimary)
            Text(title).font(.title2.bold()).foregroundStyle(.appForeground)
            Text(message).font(.subheadline).foregroundStyle(.appMuted)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent).tint(.appPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}
