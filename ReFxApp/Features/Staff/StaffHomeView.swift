import SwiftUI

/// Staff section (SUPPORT/ADMIN/OWNER). Support queue is open to all staff;
/// server/node/user admin are ADMIN+. The API enforces this regardless.
struct StaffHomeView: View {
    let role: UserRole

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        StaffQueueView()
                    } label: {
                        StaffMenuRow(icon: "ticket", title: "Support queue",
                                     subtitle: "Triage, reply, assign")
                    }
                    NavigationLink {
                        AdminServersView()
                    } label: {
                        StaffMenuRow(icon: "server.rack", title: "Server admin",
                                     subtitle: "Manage / restart any server")
                    }
                    if role.isAdmin {
                        NavigationLink {
                            NodeAdminView()
                        } label: {
                            StaffMenuRow(icon: "externaldrive.connected.to.line.below",
                                         title: "Node health", subtitle: "Ping, restart agent")
                        }
                        NavigationLink {
                            UserAdminView()
                        } label: {
                            StaffMenuRow(icon: "person.2", title: "User admin",
                                         subtitle: "Suspend, role, search")
                        }
                    }
                }
                .listRowBackground(Color.appCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Staff")
        }
    }
}

struct StaffMenuRow: View {
    let icon: String, title: String, subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.appPrimary).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.appForeground)
                Text(subtitle).font(.caption).foregroundStyle(.appMuted)
            }
        }
        .padding(.vertical, 4)
    }
}
