import Foundation

/// A drive that is gone for good (lost, broken, formatted anew): the lists the stores keep of what
/// is installed where, without the games that were on it – or without one game's copy there. Then
/// they count as not installed and download again, onto the Mac or another drive. Only drives that
/// are not mounted count, and only these lists change: nothing is deleted in the Windows
/// environment, where the saves are.
enum ForgetDrive {
    /// Whether `path` lies on the drive `name`, which is not plugged in (a Mac path, or Windows'
    /// through Z: or a drive letter).
    static func isOn(_ path: String, drive name: String, bottle: Bottle, volumes: URL = URL(fileURLWithPath: "/Volumes")) -> Bool {
        LibraryScanner.missingVolume(forLibrary: path, in: bottle, volumes: volumes) == name
    }

    /// legendary's installed.json without the games (and add-ons) installed on the drive, or just
    /// `appName`'s; the names of their manifests in legendary's manifests/ folder go with them.
    /// nil when nothing is on the drive. The rest of the file is kept as it is.
    static func epic(installedJSON: Data, drive name: String, appName: String? = nil, bottle: Bottle,
                     volumes: URL = URL(fileURLWithPath: "/Volumes")) -> (json: Data, manifests: [String], removed: [String])? {
        guard var items = try? JSONSerialization.jsonObject(with: installedJSON) as? [String: [String: Any]] else { return nil }
        let original = items
        var manifests: [String] = []
        var removed: [String] = []
        for (app, item) in original.sorted(by: { $0.key < $1.key }) {
            guard appName == nil || app == appName || (item["is_dlc"] as? Bool == true && base(of: item, in: original) == appName),
                  let path = item["install_path"] as? String, isOn(path, drive: name, bottle: bottle, volumes: volumes)
            else { continue }
            items[app] = nil
            removed.append(app)
            // legendary's name for the manifest it keeps of an install: <app>_<platform>_<version>.manifest
            if let platform = item["platform"] as? String, let version = item["version"] as? String {
                let file = "\(app)_\(platform)_\(version).manifest"
                if EpicLibrary.isFolderName(file) { manifests.append(file) }
            }
        }
        guard !removed.isEmpty,
              let json = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return (json, manifests, removed)
    }

    /// The game an add-on belongs to, by the place it is installed in (legendary gives it its game's folder).
    private static func base(of addOn: [String: Any], in items: [String: [String: Any]]) -> String? {
        guard let path = addOn["install_path"] as? String else { return nil }
        return items.first { $0.value["is_dlc"] as? Bool != true && $0.value["install_path"] as? String == path }?.key
    }

    /// Nightforge's list of GOG installs without those on the drive (or just `id`'s), and which went.
    static func gog(_ installs: [String: GOGInstall], drive name: String, id: String? = nil, bottle: Bottle,
                    volumes: URL = URL(fileURLWithPath: "/Volumes")) -> (kept: [String: GOGInstall], removed: [GOGInstall]) {
        var kept = installs
        var removed: [GOGInstall] = []
        for (key, install) in installs where (id == nil || key == id) && isOn(install.path.path, drive: name, bottle: bottle, volumes: volumes) {
            kept[key] = nil
            removed.append(install)
        }
        return (kept, removed.sorted { $0.id < $1.id })
    }
}
