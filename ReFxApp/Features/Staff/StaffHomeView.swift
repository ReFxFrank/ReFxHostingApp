import SwiftUI

/// Staff section. SUPPORT sees the support queue; ADMIN/OWNER get the full
/// platform-operations surface (overview, servers, users, nodes, audit, alerts)
/// plus the native platform-config area (products, coupons, roles, locations,
/// templates, billing, settings). The API enforces granular permissions
/// regardless of what the UI shows.
struct StaffHomeView: View {
    let role: UserRole

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
        VStack(spacing: 10) {
            NavigationLink {
                StaffOverviewView()
            } label: {
                ManageRow(icon: "chart.bar.xaxis", title: "Platform overview",
                          subtitle: "Live KPIs, nodes & server states")
            }
            .buttonStyle(.plain)

            NavigationLink {
                GrowthView()
            } label: {
                ManageRow(icon: "chart.line.uptrend.xyaxis", title: "Growth",
                          subtitle: "Signups, channels & MRR")
            }
            .buttonStyle(.plain)
        }
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
                NavigationLink { BugTriageView() } label: {
                    ManageRow(icon: "ladybug", title: "Bug triage",
                              subtitle: "Review, assign & resolve bug reports")
                }.buttonStyle(.plain)
            }

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

                NavigationLink { NetworkOverviewView() } label: {
                    ManageRow(icon: "network", title: "Network",
                              subtitle: "Fleet latency, loss & throughput")
                }.buttonStyle(.plain)

                NavigationLink { DatabaseHostsView() } label: {
                    ManageRow(icon: "cylinder.split.1x2", title: "Database hosts",
                              subtitle: "MySQL/MariaDB provisioning hosts")
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

    // MARK: Platform config (fully native)

    @ViewBuilder private var platformConfig: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Platform config", systemImage: "slider.horizontal.3")
                .padding(.leading, 4)

            NavigationLink { AdminProductsView() } label: {
                ManageRow(icon: "cube.box", title: "Products & pricing",
                          subtitle: "Plans, hardware tiers, prices")
            }.buttonStyle(.plain)

            NavigationLink { AdminTemplatesView() } label: {
                ManageRow(icon: "gamecontroller", title: "Game templates",
                          subtitle: "Eggs, variables & runtime")
            }.buttonStyle(.plain)

            NavigationLink { AdminCouponsView() } label: {
                ManageRow(icon: "tag", title: "Coupons & gift cards",
                          subtitle: "Discounts and store credit")
            }.buttonStyle(.plain)

            NavigationLink { AdminBillingView() } label: {
                ManageRow(icon: "creditcard", title: "Billing",
                          subtitle: "Summary, invoices, orders, payments")
            }.buttonStyle(.plain)

            NavigationLink { AdminRolesView() } label: {
                ManageRow(icon: "lock.shield", title: "Roles & permissions",
                          subtitle: "RBAC roles and access")
            }.buttonStyle(.plain)

            NavigationLink { AdminLocationsView() } label: {
                ManageRow(icon: "mappin.and.ellipse", title: "Locations",
                          subtitle: "Regions for grouping nodes")
            }.buttonStyle(.plain)

            NavigationLink { StaffMembersView() } label: {
                ManageRow(icon: "person.3", title: "Team members",
                          subtitle: "Public “meet the team” page")
            }.buttonStyle(.plain)

            NavigationLink { HomepageAlertsView() } label: {
                ManageRow(icon: "megaphone.fill", title: "Homepage alerts",
                          subtitle: "Storefront banners")
            }.buttonStyle(.plain)

            NavigationLink { StatusIncidentsView() } label: {
                ManageRow(icon: "exclamationmark.triangle", title: "Status incidents",
                          subtitle: "Publish incidents & webhooks")
            }.buttonStyle(.plain)

            NavigationLink { SupportSettingsView() } label: {
                ManageRow(icon: "lifepreserver", title: "Support settings",
                          subtitle: "Canned replies, KB, categories")
            }.buttonStyle(.plain)

            NavigationLink { AdminSettingsView() } label: {
                ManageRow(icon: "gearshape", title: "Settings",
                          subtitle: "Email, Steam, payment gateways")
            }.buttonStyle(.plain)
        }
    }
}
