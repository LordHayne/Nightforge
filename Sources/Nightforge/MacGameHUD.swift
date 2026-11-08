import Foundation

/// The performance HUD for Mac versions: Steam for Mac starts them, so the MTL_HUD_ENABLED that
/// Windows games get never reaches them. Apple's own switch is `MetalForceHudEnabled` in the app's
/// user defaults, read at its next start (tech talk 110339). Nightforge sets it for the game it
/// starts while the HUD is on and takes back only what it set itself once the HUD is off (8.11.).
enum MacGameHUD {
    static let key = "MetalForceHudEnabled"
    /// The games' defaults domains Nightforge turned the HUD on in.
    static let setKey = "hud.macDomains"

    /// The bundle IDs of the apps in a game's folder: the folder itself when it is an app, else the
    /// apps at most two folders down (Valheim.app, or Game/Game.app).
    static func bundleIDs(in folder: URL) -> [String] {
        if folder.pathExtension == "app" { return Bundle(url: folder)?.bundleIdentifier.map { [$0] } ?? [] }
        let fm = FileManager.default
        var apps: [URL] = []
        for item in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            if item.pathExtension == "app" {
                apps.append(item)
            } else {
                apps += ((try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "app" }
            }
        }
        return Array(Set(apps.compactMap { Bundle(url: $0)?.bundleIdentifier })).sorted()
    }

    /// Before a Mac version starts: the HUD on for its apps when the switch is on, off again in every
    /// app Nightforge turned it on in when it isn't.
    static func prepare(folder: URL, on: Bool = Prefs.performanceHUD, defaults: UserDefaults = .standard,
                        domain: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) }) {
        var set = Set(defaults.stringArray(forKey: setKey) ?? [])
        if on {
            for id in bundleIDs(in: folder) where domain(id)?.object(forKey: key) == nil || set.contains(id) {
                domain(id)?.set(true, forKey: key)
                set.insert(id)
            }
        } else {
            for id in set { domain(id)?.removeObject(forKey: key) }
            set.removeAll()
        }
        defaults.set(set.sorted(), forKey: setKey)
    }
}
