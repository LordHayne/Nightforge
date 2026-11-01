import CoreGraphics
import Foundation

/// Full screen on the screen a Windows game plays on. Unity and Unreal games remember the
/// resolution of their last start, and under Wine full screen at another size than the screen's is
/// a smaller window: a game first played on the MacBook comes up as a window on the TV. So before
/// every start the remembered size becomes the screen's – as long as the game is set to full screen.
/// A game the player put in a window keeps its window; a lower full-screen resolution, on the other
/// hand, only ever gave a smaller window under Wine, so nothing is lost there.
///
/// Unity keeps its screen in the registry (HKCU\Software\<company>\<product>), Unreal in
/// GameUserSettings.ini. The registry rather than Unity's -screen-width/-screen-height arguments:
/// "Use Native" there lets the game take the screen the way Wine shows it, whatever Retina mode or
/// mirroring make of it, where arguments only carry fixed numbers. The prefix is the same for
/// every store, and arguments would also ride along in Steam's -applaunch, count as another way
/// in LaunchHealth and could clash with the player's own.
enum GameResolution {
    struct Size: Hashable, CustomStringConvertible {
        var width: Int
        var height: Int

        var description: String { "\(width)×\(height)" }
    }

    /// The screen as Wine shows it to games: in points, in pixels with Wine's Retina mode on.
    static func wineSize(points: Size, pixels: Size, retina: Bool) -> Size {
        retina ? pixels : points
    }

    /// The main display, where Wine opens full screen (GameDisplay has made the game's screen main
    /// by now). Mirrored, it's the mirror set's master, whose mode the whole set shows.
    static func mainScreen(retina: Bool) -> Size? {
        guard let mode = CGDisplayCopyDisplayMode(CGDisplayPrimaryDisplay(CGMainDisplayID())),
              mode.width > 0, mode.height > 0
        else { return nil }
        return wineSize(points: Size(width: mode.width, height: mode.height),
                        pixels: Size(width: mode.pixelWidth, height: mode.pixelHeight), retina: retina)
    }

    /// The sizes the main display can show, as Wine lists them: what a game may change the screen to.
    static func mainScreenModes(retina: Bool) -> Set<Size> {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(CGDisplayPrimaryDisplay(CGMainDisplayID()), options) as? [CGDisplayMode]
        else { return [] }
        return Set(modes.map { retina ? Size(width: $0.pixelWidth, height: $0.pixelHeight) : Size(width: $0.width, height: $0.height) })
    }

    /// Before a Windows game starts on Nightforge's engine. `retina`: Wine's Retina mode for it.
    /// Never while the game runs: Wine holds the registry then, and the game writes its own
    /// settings back when it ends.
    static func fit(_ game: Game, profile: GameProfile? = nil, retina: Bool, wine: URL,
                    places: SaveTransfer.Places = SaveTransfer.Places()) {
        guard let size = mainScreen(retina: retina) else { return }
        let marker = game.windowsFolderMarker.lowercased()
        guard !Engine.ownProcesses().contains(where: { $0.command.lowercased().contains(marker) }) else { return }
        var notes: [String] = []
        // user.reg on disk can lag the wineserver's copy by up to half a minute; the values a game
        // wrote when it ended a while ago are there.
        let registry = (try? String(contentsOf: places.prefix.appendingPathComponent("user.reg"), encoding: .utf8)) ?? ""
        for key in unityKeys(installDir: game.installDir) {
            let values = dwordValues(inRegistry: registry, key: key)
            let changes = unityChanges(values, size: size)
            guard !changes.isEmpty, Engine.importRegistry(registryImport(key: key, values: changes), wine: wine) else { continue }
            notes.append("\(key.split(separator: "\\").last ?? ""): \(unitySize(values).map { "\($0) → " } ?? "")\(size)")
        }
        // A game whose profile says where it keeps its resolution (its own format).
        if let saved = profile?.resolution,
           let base = saved.root.map({ SaveTransfer.windowsRoot($0, places) }) ?? game.installDir {
            let file = base.appendingPathComponent(saved.path).standardizedFileURL
            if file.path.hasPrefix(base.standardizedFileURL.path + "/"),
               let text = try? String(contentsOf: file, encoding: .utf8),
               let fitted = savedFitted(text, saved, size: size, modes: mainScreenModes(retina: retina)),
               (try? fitted.write(to: file, atomically: true, encoding: .utf8)) != nil {
                notes.append("\(file.lastPathComponent): \(size)")
            }
        }
        for file in unrealSettings(installDir: game.installDir, places: places) {
            guard let text = try? String(contentsOf: file, encoding: .utf8), let fitted = unrealFitted(text, size: size),
                  (try? fitted.write(to: file, atomically: true, encoding: .utf8)) != nil
            else { continue }
            notes.append("\(file.lastPathComponent): \(size)")
        }
        // In the game log, for problem reports and to see it happen.
        guard !notes.isEmpty else { return }
        let descriptor = open(GameLog.url.path, O_WRONLY | O_APPEND)
        guard descriptor >= 0 else { return }
        let log = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        log.write(Data(("info:  [nightforge] Full screen " + notes.joined(separator: ", ") + "\n").utf8))
    }

    // MARK: - Unity

    /// The registry keys of the Unity programs in a game folder: Software\<company>\<product>, as
    /// <Program>_Data/app.info names them.
    static func unityKeys(installDir: URL) -> [String] {
        let fm = FileManager.default
        let top = (try? fm.contentsOfDirectory(at: installDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        // Next to the program, which some games keep one folder down.
        let folders = top + top.flatMap { folder in
            folder.lastPathComponent.hasSuffix("_Data") ? []
                : (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        }
        let keys = folders.filter { $0.lastPathComponent.hasSuffix("_Data") }.compactMap { data in
            (try? String(contentsOf: data.appendingPathComponent("app.info"), encoding: .utf8)).flatMap(unityKey(appInfo:))
        }
        return Array(Set(keys)).sorted()
    }

    /// "Team17\nOvercooked2" → Software\Team17\Overcooked2. Nil for names a .reg file can't carry
    /// safely (Wine's regedit reads REGEDIT4 files as ANSI) and for keys a game has no business in.
    static func unityKey(appInfo text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count >= 2 else { return nil }
        let names = lines.prefix(2)
        guard names.allSatisfy({ name in
            !name.isEmpty && name.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value < 0x7f && !"\\[]".unicodeScalars.contains($0) }
        }) else { return nil }
        let key = "Software\\" + names.joined(separator: "\\")
        return Engine.isAllowedRegistryKey("HKEY_CURRENT_USER\\" + key) ? key : nil
    }

    /// "Screenmanager Resolution Width_h182942802" → "Screenmanager Resolution Width". Unity puts a
    /// hash of the name behind it, the same in every game; Nightforge only uses the names it finds.
    static func unityBase(_ name: String) -> String {
        guard let marker = name.range(of: "_h", options: .backwards) else { return name }
        let hash = name[marker.upperBound...]
        return !hash.isEmpty && hash.allSatisfy(\.isASCII) && hash.allSatisfy(\.isNumber) ? String(name[..<marker.lowerBound]) : name
    }

    /// What a Unity game's remembered screen needs for full screen at `size`: only when it's set to
    /// full screen (Unity 2018 and later: "Fullscreen mode" 0 exclusive, 1 full-screen window, 3 a
    /// window; before: "Is Fullscreen mode" 1), only values the game wrote itself, only those that
    /// differ. "Use Native" makes Unity take the screen's own size, the width and height count where
    /// a Unity has no such value.
    static func unityChanges(_ values: [String: UInt32], size: Size) -> [String: UInt32] {
        func names(_ base: String) -> [String] { values.keys.filter { unityBase($0) == base }.sorted() }
        let fullScreen: Bool
        if let mode = names("Screenmanager Fullscreen mode").first {
            fullScreen = values[mode]! <= 1
        } else if let mode = names("Screenmanager Is Fullscreen mode").first {
            fullScreen = values[mode]! == 1
        } else {
            return [:]
        }
        guard fullScreen, size.width > 0, size.height > 0 else { return [:] }
        var changes: [String: UInt32] = [:]
        let wanted: [(String, UInt32)] = [("Screenmanager Resolution Width", UInt32(size.width)),
                                          ("Screenmanager Resolution Height", UInt32(size.height)),
                                          ("Screenmanager Resolution Use Native", 1)]
        for (base, value) in wanted {
            for name in names(base) where values[name] != value { changes[name] = value }
        }
        return changes
    }

    /// The size a Unity game remembers, for the log.
    static func unitySize(_ values: [String: UInt32]) -> Size? {
        func value(_ base: String) -> UInt32? { values.first { unityBase($0.key) == base }?.value }
        guard let width = value("Screenmanager Resolution Width"), let height = value("Screenmanager Resolution Height") else { return nil }
        return Size(width: Int(width), height: Int(height))
    }

    /// A .reg file's section setting `values` as DWORDs under HKEY_CURRENT_USER\`key`.
    static func registryImport(key: String, values: [String: UInt32]) -> String {
        "[HKEY_CURRENT_USER\\\(key)]\n" + values.keys.sorted()
            .map { Engine.regString($0) + "=dword:" + String(format: "%08x", values[$0]!) }.joined(separator: "\n")
    }

    /// The DWORD values of `key` ("Software\Team17\Overcooked2", any case) in a Wine registry file
    /// (user.reg): keys and names there are escaped (`\\`, `\"`, `\x…`).
    static func dwordValues(inRegistry text: String, key: String) -> [String: UInt32] {
        var values: [String: UInt32] = [:]
        var inKey = false
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("[") {
                if inKey { break }  // a key's values all follow its header
                let (name, end) = registryString(line.dropFirst(), until: "]")
                inKey = end != nil && name.caseInsensitiveCompare(key) == .orderedSame
                continue
            }
            guard inKey, line.hasPrefix("\"") else { continue }
            let (name, end) = registryString(line.dropFirst(), until: "\"")
            guard let end, line[end...].hasPrefix("=dword:"),
                  let value = UInt32(line[end...].dropFirst("=dword:".count).trimmingCharacters(in: .whitespaces), radix: 16)
            else { continue }
            values[name] = value
        }
        return values
    }

    /// The escaped text up to an unescaped `end`, and where the rest begins (nil without `end`).
    private static func registryString(_ text: Substring, until end: Character) -> (String, Substring.Index?) {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            index = text.index(after: index)
            if character == end { return (result, index) }
            guard character == "\\", index < text.endIndex else {
                result.append(character)
                continue
            }
            let escaped = text[index]
            index = text.index(after: index)
            switch escaped {
            case "x":
                // Up to four hex digits: a character outside ASCII.
                var digits = ""
                while digits.count < 4, index < text.endIndex, text[index].isHexDigit {
                    digits.append(text[index])
                    index = text.index(after: index)
                }
                if let code = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(code) { result.unicodeScalars.append(scalar) }
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            default: result.append(escaped)
            }
        }
        return (result, nil)
    }

    // MARK: - A profile's own format

    /// A game's own resolution file (`GameProfile.resolution`) set to `size`: only when it's set to
    /// full screen at a size the screen doesn't have (`modes`) – there the game can't get its mode
    /// ("Failed to change display mode") or ends up in a corner. A window, or a size the screen
    /// has, stays as the player chose. Nil when nothing changes.
    static func savedFitted(_ text: String, _ saved: GameProfile.SavedResolution, size: Size, modes: Set<Size>) -> String? {
        guard size.width > 0, size.height > 0 else { return nil }
        let on = Set((saved.fullscreenOn ?? ["1"]).map { $0.lowercased() })
        func needs(width: String?, height: String?, fullscreen: String?) -> Bool {
            guard let width = width.flatMap(Int.init), let height = height.flatMap(Int.init) else { return false }
            let stored = Size(width: width, height: height)
            return (fullscreen.map { on.contains($0.lowercased()) } ?? true) && stored != size && !modes.contains(stored)
        }
        if let fields = saved.fields {
            // The first line with values; the line end it had stays.
            var lines = text.components(separatedBy: "\n")
            guard let index = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
            let carriage = lines[index].hasSuffix("\r")
            var values = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace).map(String.init)
            guard max(fields.width, fields.height, fields.fullscreen ?? 0) < values.count,
                  needs(width: values[fields.width], height: values[fields.height], fullscreen: fields.fullscreen.map { values[$0] })
            else { return nil }
            values[fields.width] = String(size.width)
            values[fields.height] = String(size.height)
            lines[index] = values.joined(separator: " ") + (carriage ? "\r" : "")
            return lines.joined(separator: "\n")
        }
        if let section = saved.section, let keys = saved.keys {
            var current: String?
            var found: [String: String] = [:]
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    current = String(trimmed.dropFirst().dropLast())
                    continue
                }
                guard current?.caseInsensitiveCompare(section) == .orderedSame, let equals = trimmed.firstIndex(of: "=") else { continue }
                let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
                if found[key] == nil { found[key] = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces) }
            }
            guard needs(width: found[keys.width], height: found[keys.height], fullscreen: keys.fullscreen.map { found[$0] ?? "" })
            else { return nil }
            return Engine.mergingIni(text, section: section, values: [keys.width: String(size.width), keys.height: String(size.height)])
        }
        return nil
    }

    // MARK: - Unreal

    /// The GameUserSettings.ini files of an Unreal game: under %LOCALAPPDATA% (or Documents\My
    /// Games) in <Project>\Saved\Config\Windows (UE5) or WindowsNoEditor (UE4). The project is the
    /// folder holding Binaries\Win64, or what the -Shipping program is named after.
    static func unrealSettings(installDir: URL, places: SaveTransfer.Places) -> [URL] {
        let fm = FileManager.default
        let inside = installDir.standardizedFileURL.path + "/"
        var projects = Set<String>()
        if let files = fm.enumerator(at: installDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let file as URL in files {
                // <Project>/Binaries/Win64/<Project>-Win64-Shipping.exe
                if files.level > 4 { files.skipDescendants(); continue }
                let name = file.lastPathComponent
                guard name.lowercased().hasSuffix("-shipping.exe") else { continue }
                if let prefix = name.split(separator: "-").first { projects.insert(String(prefix)) }
                let project = file.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                if project.standardizedFileURL.path.hasPrefix(inside),
                   project.lastPathComponent.caseInsensitiveCompare("Engine") != .orderedSame {
                    projects.insert(project.lastPathComponent)
                }
            }
        }
        let roots = [SaveTransfer.windowsRoot("WinAppDataLocal", places),
                     SaveTransfer.windowsRoot("WinMyDocuments", places)?.appendingPathComponent("My Games", isDirectory: true)]
        var found: [URL] = []
        for root in roots.compactMap({ $0 }) {
            for project in projects.sorted() {
                let config = root.appendingPathComponent("\(project)/Saved/Config", isDirectory: true)
                let platforms = (try? fm.contentsOfDirectory(atPath: config.path)) ?? []
                for platform in platforms.sorted() where platform.lowercased().hasPrefix("windows") {
                    let file = config.appendingPathComponent("\(platform)/GameUserSettings.ini")
                    if fm.fileExists(atPath: file.path) { found.append(file) }
                }
            }
        }
        return found
    }

    /// GameUserSettings.ini with its remembered resolution set to `size`, in every section where the
    /// game is set to full screen (FullscreenMode 0 exclusive, 1 full-screen window; 2 is a window).
    /// Games with their own settings class keep these in its section ([/Script/Game.GameSettings]).
    /// Only values the game wrote itself. Nil when nothing changes.
    static func unrealFitted(_ text: String, size: Size) -> String? {
        guard size.width > 0, size.height > 0 else { return nil }
        var sections: [(name: String, values: [String: String])] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                sections.append((String(trimmed.dropFirst().dropLast()), [:]))
                continue
            }
            guard !sections.isEmpty, let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if sections[sections.count - 1].values[key] == nil { sections[sections.count - 1].values[key] = value }
        }
        var result = text
        for (name, values) in sections {
            guard let mode = values["FullscreenMode"].flatMap(Int.init), mode == 0 || mode == 1 else { continue }
            let resolution: [String: String] = ["ResolutionSizeX": "\(size.width)", "ResolutionSizeY": "\(size.height)",
                                                "LastUserConfirmedResolutionSizeX": "\(size.width)",
                                                "LastUserConfirmedResolutionSizeY": "\(size.height)"]
            var wanted = resolution.filter { values[$0.key] != nil && values[$0.key] != $0.value }
            // True makes Unreal size the picture by DesiredScreenWidth/Height instead.
            if values["bUseDesiredScreenHeight"]?.lowercased() == "true" { wanted["bUseDesiredScreenHeight"] = "False" }
            guard !wanted.isEmpty else { continue }
            result = Engine.mergingIni(result, section: name, values: wanted)
        }
        return result == text ? nil : result
    }
}
