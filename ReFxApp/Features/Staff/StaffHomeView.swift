import SwiftUI

/// Staff section (SUPPORT/ADMIN/OWNER). Support queue is open to all staff;
/// server/node/user admin are ADMIN+. The API enforces this regardless.
struct StaffHomeView: View {
    let role: UserRole

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    NavigationLink {
                        StaffQueueView()
                    } label: {
                        ManageRow(icon: "ticket", title: "Support queue",
                                  subtitle: "Triage, reply, assign")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AdminServersView()
                    } label: {
                        ManageRow(icon: "server.rack", title: "Server admin",
                                  subtitle: "Manage / restart any server")
                    }
                    .buttonStyle(.plain)

                    if role.isAdmin {
                        NavigationLink {
                            NodeAdminView()
                        } label: {
                            ManageRow(icon: "externaldrive.connected.to.line.below",
                                      title: "Node health", subtitle: "Ping, restart agent")
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            UserAdminView()
                        } label: {
                            ManageRow(icon: "person.2", title: "User admin",
                                      subtitle: "Suspend, role, search")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Staff")
        }
    }
}
