import Foundation

/// The server management sections, mirroring the web client area's
/// `serverTabs` (components/layout/nav-config). Conditional sections follow the
/// same rules as the web sidebar (Minecraft/Mods/Modpacks = Minecraft only,
/// Workshop = Steam-Workshop games, Voice = TeamSpeak, Console/Switch hidden for
/// voice servers).
enum ServerSection: String, CaseIterable, Identifiable {
    case console, files, databases, backups, schedules
    case minecraft, mods, modpacks, workshop, voice
    case switchGame, upgrade, settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .console: return "Console"
        case .files: return "Files"
        case .databases: return "Databases"
        case .backups: return "Backups"
        case .schedules: return "Schedules"
        case .minecraft: return "Minecraft"
        case .mods: return "Mods"
        case .modpacks: return "Modpacks"
        case .workshop: return "Workshop"
        case .voice: return "Voice"
        case .switchGame: return "Switch Game"
        case .upgrade: return "Upgrade"
        case .settings: return "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .console: return "Live console & commands"
        case .files: return "Browse and edit configs"
        case .databases: return "MySQL databases"
        case .backups: return "Create & restore snapshots"
        case .schedules: return "Automated tasks"
        case .minecraft: return "Version & loader"
        case .mods: return "Plugins & mods"
        case .modpacks: return "Install a modpack"
        case .workshop: return "Steam Workshop content"
        case .voice: return "TeamSpeak admin"
        case .switchGame: return "Change the game"
        case .upgrade: return "Change your plan (web)"
        case .settings: return "Startup, variables, reinstall"
        }
    }

    var icon: String {
        switch self {
        case .console: return "terminal"
        case .files: return "folder"
        case .databases: return "cylinder.split.1x2"
        case .backups: return "archivebox"
        case .schedules: return "clock.arrow.circlepath"
        case .minecraft: return "cube"
        case .mods: return "puzzlepiece.extension"
        case .modpacks: return "shippingbox"
        case .workshop: return "wrench.and.screwdriver"
        case .voice: return "waveform"
        case .switchGame: return "arrow.triangle.2.circlepath"
        case .upgrade: return "arrow.up.circle"
        case .settings: return "gearshape"
        }
    }

    /// Opens the web panel instead of an in-app screen (billing-sensitive).
    var isWebLinkOut: Bool { self == .upgrade }

    /// Web path segment for a link-out (relative to the server page).
    var webPath: String { rawValue == "switchGame" ? "switch-game" : rawValue }

    func isApplicable(to server: Server) -> Bool {
        let slug = server.template?.slug ?? ""
        let isMinecraft = slug == "minecraft" || slug.hasPrefix("minecraft-")
        let isVoice = slug.hasPrefix("teamspeak")
        switch self {
        case .minecraft, .modpacks, .mods: return isMinecraft
        case .workshop: return server.template?.supportsWorkshop == true
        case .voice: return isVoice
        case .console, .switchGame: return !isVoice
        default: return true
        }
    }

    /// Sections applicable to a server, in the web sidebar order.
    static func sections(for server: Server) -> [ServerSection] {
        allCases.filter { $0.isApplicable(to: server) }
    }
}
