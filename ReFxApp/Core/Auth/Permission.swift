import Foundation

/// Per-server permission strings (mirror `packages/shared/src/permissions.ts`).
/// Used to hide controls a sub-user can't use. The API is the final authority —
/// always expect a possible 403 regardless of what's shown.
enum Permission {
    static let controlStart = "control.start"
    static let controlStop = "control.stop"
    static let controlRestart = "control.restart"
    static let controlPower = "control.power"
    static let controlReinstall = "control.reinstall"
    static let controlResize = "control.resize"

    static let consoleRead = "console.read"
    static let consoleCommand = "console.command"

    static let filesRead = "files.read"
    static let filesWrite = "files.write"
    static let filesArchive = "files.archive"
    static let filesDelete = "files.delete"
    static let filesSFTP = "files.sftp"

    static let backupRead = "backup.read"
    static let backupCreate = "backup.create"
    static let backupRestore = "backup.restore"
    static let backupDownload = "backup.download"
    static let backupDelete = "backup.delete"

    static let allocationRead = "allocation.read"
    static let scheduleRead = "schedule.read"
    static let scheduleCreate = "schedule.create"
    static let scheduleUpdate = "schedule.update"
    static let subuserRead = "subuser.read"
    static let startupUpdate = "startup.update"
    static let settingsRead = "settings.read"
    static let settingsUpdate = "settings.update"
}
