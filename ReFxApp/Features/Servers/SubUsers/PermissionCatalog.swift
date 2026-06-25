import SwiftUI

/// Curated, grouped list of per-server permissions a sub-user can be granted,
/// using the exact permission strings the API enforces.
enum PermissionCatalog {
    struct Group: Identifiable {
        let id = UUID()
        let title: String
        let items: [Item]
    }
    struct Item: Identifiable {
        let key: String
        let label: String
        var id: String { key }
    }

    static let groups: [Group] = [
        Group(title: "Power", items: [
            .init(key: "control.start", label: "Start"),
            .init(key: "control.stop", label: "Stop"),
            .init(key: "control.restart", label: "Restart"),
            .init(key: "control.power", label: "Force kill"),
            .init(key: "control.reinstall", label: "Reinstall"),
        ]),
        Group(title: "Console", items: [
            .init(key: "console.read", label: "View console"),
            .init(key: "console.command", label: "Send commands"),
        ]),
        Group(title: "Files", items: [
            .init(key: "files.read", label: "View files"),
            .init(key: "files.write", label: "Edit files"),
            .init(key: "files.archive", label: "Archive files"),
            .init(key: "files.delete", label: "Delete files"),
        ]),
        Group(title: "Backups", items: [
            .init(key: "backup.read", label: "View backups"),
            .init(key: "backup.create", label: "Create backups"),
            .init(key: "backup.restore", label: "Restore backups"),
            .init(key: "backup.download", label: "Download backups"),
            .init(key: "backup.delete", label: "Delete backups"),
        ]),
        Group(title: "Databases", items: [
            .init(key: "database.read", label: "View databases"),
            .init(key: "database.create", label: "Manage databases"),
            .init(key: "database.delete", label: "Delete databases"),
        ]),
        Group(title: "Schedules", items: [
            .init(key: "schedule.read", label: "View schedules"),
            .init(key: "schedule.create", label: "Create schedules"),
            .init(key: "schedule.update", label: "Edit schedules"),
            .init(key: "schedule.delete", label: "Delete schedules"),
        ]),
        Group(title: "Settings", items: [
            .init(key: "settings.read", label: "View settings"),
            .init(key: "settings.update", label: "Edit settings"),
            .init(key: "startup.update", label: "Edit startup"),
        ]),
        Group(title: "Sub-users", items: [
            .init(key: "user.read", label: "View sub-users"),
            .init(key: "user.create", label: "Add sub-users"),
            .init(key: "user.update", label: "Edit sub-users"),
            .init(key: "user.delete", label: "Remove sub-users"),
        ]),
    ]
}

/// A Form section list of permission toggles bound to a selected key set.
struct PermissionEditor: View {
    @Binding var selection: Set<String>

    var body: some View {
        ForEach(PermissionCatalog.groups) { group in
            Section(group.title) {
                ForEach(group.items) { item in
                    Toggle(item.label, isOn: Binding(
                        get: { selection.contains(item.key) },
                        set: { on in
                            if on { selection.insert(item.key) } else { selection.remove(item.key) }
                        }))
                    .tint(.appPrimary)
                }
            }
            .listRowBackground(Color.appCard)
        }
    }
}
