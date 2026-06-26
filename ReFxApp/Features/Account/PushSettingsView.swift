import SwiftUI
import UserNotifications
import UIKit

/// Notification settings: shows the current authorization state and lets the
/// user enable (or jump to iOS Settings if previously denied). Real-time
/// delivery additionally needs the APNs entitlement + backend, so the copy is
/// honest about that until they're in place.
struct PushSettingsView: View {
    @ObservedObject private var push = PushManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GlassCard {
                    HStack(spacing: 12) {
                        Image(systemName: statusIcon).font(.title3).foregroundStyle(statusColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(statusTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                            Text(statusSubtitle).font(.caption).foregroundStyle(.appMuted)
                        }
                        Spacer()
                    }
                }

                actionButton

                diagnostics

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle").foregroundStyle(.appSecondary)
                    Text("Alerts cover server status, billing, and support replies. Instant push is rolling out; until then the app delivers best-effort alerts when it refreshes in the background.")
                        .font(.caption2).foregroundStyle(.appMuted)
                }
                .padding(Theme.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await push.refreshStatus() }
    }

    private var diagnostics: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Diagnostics", systemImage: "stethoscope")
                diagRow("Permission", permissionLabel, ok: push.authorizationStatus == .authorized || push.authorizationStatus == .provisional)
                diagRow("APNs token", push.deviceToken == nil ? "Not received" : "Received", ok: push.deviceToken != nil)
                diagRow("Server sync", push.serverSynced ? "Synced" : (push.lastError == nil ? "Pending" : "Failed"), ok: push.serverSynced)
                if let error = push.lastError {
                    Text(error).font(.caption2).foregroundStyle(.appDestructive)
                }
                if let token = push.deviceToken {
                    HStack(spacing: 8) {
                        Text(token.prefix(16) + "…").font(.caption2.monospaced()).foregroundStyle(.appMuted).lineLimit(1)
                        Spacer()
                        Button {
                            Clipboard.copySecret(token)
                        } label: { Label("Copy token", systemImage: "doc.on.doc").font(.caption2) }
                            .foregroundStyle(.appPrimary)
                    }
                }
                Button("Re-register this device") { Task { await push.requestAndRegister() } }
                    .buttonStyle(.refxSecondary(fullWidth: false))
            }
        }
    }

    private func diagRow(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.caption).foregroundStyle(ok ? .appSuccess : .appMuted)
            Text(label).font(.caption).foregroundStyle(.appMuted)
            Spacer()
            Text(value).font(.caption.weight(.medium)).foregroundStyle(.appForeground)
        }
    }

    private var permissionLabel: String {
        switch push.authorizationStatus {
        case .authorized: return "Authorized"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        case .denied: return "Denied"
        default: return "Not set"
        }
    }

    @ViewBuilder private var actionButton: some View {
        switch push.authorizationStatus {
        case .notDetermined:
            Button("Enable notifications") { Task { await push.requestAndRegister() } }
                .buttonStyle(.refxPrimary)
        case .denied:
            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.refxSecondary)
        default:
            EmptyView()
        }
    }

    private var statusTitle: String {
        switch push.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "Notifications on"
        case .denied: return "Notifications off"
        default: return "Notifications not set up"
        }
    }
    private var statusSubtitle: String {
        switch push.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "You'll receive alerts on this device."
        case .denied: return "Turn them on in iOS Settings to get alerts."
        default: return "Enable to get server, billing & support alerts."
        }
    }
    private var statusIcon: String {
        switch push.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "bell.fill"
        case .denied: return "bell.slash.fill"
        default: return "bell"
        }
    }
    private var statusColor: Color {
        switch push.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .appSuccess
        case .denied: return .appWarning
        default: return .appSecondary
        }
    }
}
