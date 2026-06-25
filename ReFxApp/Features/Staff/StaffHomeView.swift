import SwiftUI

/// Staff section. SUPPORT sees the support queue; ADMIN/OWNER get the full
/// platform-operations surface (overview, servers, users, nodes, audit, alerts)
/// plus link-outs to the config-heavy admin areas that live on the web. The API
/// enforces granular permissions regardless of what the UI shows.
struct StaffHomeView: View {
    let role: UserRole
    @EnvironmentObject private var config: AppConfig

    private var isAdmin: Bool { role.isAdmin }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isAdmin { overview }
                    operations
                    if isAdmin { platformConfig }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Staff")
        }
    }

    // MARK: Overview

    @ViewBuilder private var overview: some View {
        NavigationLink {
            StaffOverviewView()
        } label: {
            ManageRow(icon: "chart.bar.xaxis", title: "Platform overview",
                      subtitle: "Live KPIs, nodes & server states")
        }
        .buttonStyle(.plain)
    }

    // MARK: Native operations

    @ViewBuilder private var operations: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Operations", systemImage: "bolt.fill")
                .padding(.leading, 4)

            NavigationLink { StaffQueueView() } label: {
                ManageRow(icon: "ticket", title: "Support queue",
                          subtitle: "Triage, reply, assign tickets")
            }.buttonStyle(.plain)

            if isAdmin {
                NavigationLink { AdminServersView() } label: {
                    ManageRow(icon: "server.rack", title: "Server admin",
                              subtitle: "Find & control any server")
                }.buttonStyle(.plain)

                NavigationLink { UserAdminView() } label: {
                    ManageRow(icon: "person.2", title: "User admin",
                              subtitle: "Search, suspend, role, account view")
                }.buttonStyle(.plain)

                NavigationLink { NodeAdminView() } label: {
                    ManageRow(icon: "externaldrive.connected.to.line.below",
                              title: "Nodes", subtitle: "Health, ping, restart & update agents")
                }.buttonStyle(.plain)

                NavigationLink { PlatformAlertsView() } label: {
                    ManageRow(icon: "megaphone", title: "Platform alerts",
                              subtitle: "Post & manage dashboard banners")
                }.buttonStyle(.plain)

                NavigationLink { AuditLogView() } label: {
                    ManageRow(icon: "list.bullet.rectangle.portrait",
                              title: "Audit log", subtitle: "Recent staff & system actions")
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: Platform config (native + remaining web link-outs)

    @ViewBuilder private var platformConfig: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Platform config", systemImage: "slider.horizontal.3")
                .padding(.leading, 4)

            NavigationLink { AdminProductsView() } label: {
                ManageRow(icon: "cube.box", title: "Products & pricing",
                          subtitle: "Plans, hardware tiers, prices")
            }.buttonStyle(.plain)

            NavigationLink { AdminCouponsView() } label: {
                ManageRow(icon: "tag", title: "Coupons & gift cards",
                          subtitle: "Discounts and store credit")
            }.buttonStyle(.plain)

            NavigationLink { AdminRolesView() } label: {
                ManageRow(icon: "lock.shield", title: "Roles & permissions",
                          subtitle: "RBAC roles and access")
            }.buttonStyle(.plain)

            NavigationLink { AdminLocationsView() } label: {
                ManageRow(icon: "mappin.and.ellipse", title: "Locations",
                          subtitle: "Regions for grouping nodes")
            }.buttonStyle(.plain)

            ForEach(StaffWebLink.all) { link in
                Button {
                    WebLink.open(config.webOrigin, path: link.path)
                } label: {
                    StaffWebRow(icon: link.icon, title: link.title, subtitle: link.subtitle)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A config area that lives on the web admin (heavy CRUD better suited to a
/// larger screen). Tapping opens it in the system browser.
private struct StaffWebLink: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let path: String

    static let all: [StaffWebLink] = [
        .init(icon: "gamecontroller", title: "Game templates", subtitle: "Eggs & install configs", path: "admin/templates"),
        .init(icon: "creditcard", title: "Billing", subtitle: "Invoices, orders, payments", path: "admin/invoices"),
        .init(icon: "gearshape", title: "Settings", subtitle: "Email, Steam, gateways", path: "admin/settings"),
    ]
}

/// Glassy row for a web link-out — same shape as ManageRow but signals it opens
/// externally.
struct StaffWebRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.appSecondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.appForeground)
                Text(subtitle).font(.caption).foregroundStyle(.appMuted)
            }
            Spacer()
            Image(systemName: "arrow.up.forward.square").font(.caption).foregroundStyle(.appLabel)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
