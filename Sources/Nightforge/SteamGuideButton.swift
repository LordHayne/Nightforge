import Foundation

/// The PS / Xbox button outside a game: Steam opens Big Picture for it ("Guide button focuses
/// Steam", on unless turned off), and the background Steam's 1280×800 window comes up behind
/// Nightforge, where the player is. Turned off before Steam starts. In a game the button still
/// toggles Steam's overlay: Steam hands the press to the game's overlay without asking this
/// setting (steamui, Oct 2026: only its Big Picture branch reads it). Nightforge's Windows games
/// have no overlay anyway (Engine.steamDLLOverrides); Steam for Mac's games keep theirs.
///
/// Steam keeps it per account in userdata/<id>/config/localconfig.vdf, at the top of
/// "UserLocalConfigStore" (setting controller_guide_button_focus_steam, stored as
/// "Controller_CheckGuideButton"). It reads that when it starts and writes it back when it quits,
/// so it's only changed while that Steam isn't running.
enum SteamGuideButton {
    static let key = "Controller_CheckGuideButton"

    /// Turns the setting off for every account that has signed in to this Steam. Accounts that never
    /// have get it with the restart after their sign-in (SetupModel.finish).
    static func turnOff(steamRoot: URL) {
        let users = steamRoot.appendingPathComponent("userdata", isDirectory: true)
        for user in (try? FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [] {
            let config = user.appendingPathComponent("config/localconfig.vdf")
            guard let data = try? Data(contentsOf: config),
                  let changed = turnedOff(String(decoding: data, as: UTF8.self)) else { continue }
            try? Data(changed.utf8).write(to: config, options: .atomic)
        }
    }

    /// `text` (a localconfig.vdf) with the setting off – the rest exactly as Steam wrote it – or nil
    /// when it's off already or the file isn't one.
    static func turnedOff(_ text: String) -> String? {
        let chars = Array(text.unicodeScalars)
        var i = 0
        var depth = 0
        var rootOpen: Int?
        var expectingValue = false
        var keyIsOurs = false
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                // A quoted string; Steam escapes quotes inside with a backslash (its JSON values).
                let start = i + 1
                i = start
                while i < chars.count, chars[i] != "\"" { i += chars[i] == "\\" ? 2 : 1 }
                guard i < chars.count else { return nil }
                let content = String(String.UnicodeScalarView(chars[start..<i]))
                i += 1
                guard depth == 1 else { continue }
                if expectingValue {
                    expectingValue = false
                    guard keyIsOurs else { continue }
                    if content == "0" { return nil }
                    return String(String.UnicodeScalarView(chars[..<start])) + "0" + String(String.UnicodeScalarView(chars[(i - 1)...]))
                }
                expectingValue = true
                keyIsOurs = content.lowercased() == key.lowercased()
            } else if c == "{" {
                if depth == 0, rootOpen == nil { rootOpen = i }
                depth += 1
                expectingValue = false
                i += 1
            } else if c == "}" {
                depth -= 1
                // The root's end: the setting isn't there yet, so it goes in first thing after its brace.
                if depth == 0, let rootOpen {
                    let after = rootOpen + 1
                    let line = "\n\t\"\(key)\"\t\t\"0\""
                    return String(String.UnicodeScalarView(chars[..<after])) + line + String(String.UnicodeScalarView(chars[after...]))
                }
                guard depth >= 0 else { return nil }
                i += 1
            } else {
                i += 1
            }
        }
        return nil
    }
}
