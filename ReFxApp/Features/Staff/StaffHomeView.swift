import SwiftUI

/// Staff section placeholder for Phase 1 (visible only to SUPPORT/ADMIN/OWNER).
/// Phase 3 fills this in: support queue triage, server admin (restart any
/// customer server), node health/ping/restart-agent, user admin — against
/// `admin.controller.ts`, `nodes.controller.ts`, `support.controller.ts`.
struct StaffHomeView: View {
    let role: UserRole

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StaffStubRow(icon: "ticket", title: "Support queue",
                                 subtitle: "Triage, reply, assign")
                    StaffStubRow(icon: "server.rack", title: "Server admin",
                                 subtitle: "Restart any customer server")
                    if role.isAdmin {
                        StaffStubRow(icon: "externaldrive.connected.to.line.below",
                                     title: "Node health", subtitle: "Ping, restart agent")
                        StaffStubRow(icon: "person.2", title: "User admin",
                                     subtitle: "Roles, suspend, credit")
                    }
                } footer: {
                    Text("Staff remote ops arrive in Phase 3.")
                }
                .listRowBackground(Color.appCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Staff")
        }
    }
}

private struct StaffStubRow: View {
    let icon: String, title: String, subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.appPrimary).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.appForeground)
                Text(subtitle).font(.caption).foregroundStyle(.appMuted)
            }
            Spacer()
            Text("Soon").font(.caption2).foregroundStyle(.appMuted)
        }
        .padding(.vertical, 4)
    }
}
