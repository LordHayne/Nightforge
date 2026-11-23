import Foundation

/// The Dock out of sight for a game in console mode (Nightforge in its full screen): macOS's own setting "Automatically
/// hide and show the Dock", set while games are played and put back afterwards. Nightforge's full screen hides the Dock
/// only while Nightforge itself is in front (FullScreen); a game in a window, or Steam in front over the page, showed it
/// (21./22.11.2026). The user allowed this system setting on 22.11.2026, on these terms:
/// - the value before is kept, and put back when console mode ends, when Nightforge quits, and – after a crash – at the
///   next start (`restoreKey` is written before the setting is changed, so a crash in between is covered as well);
/// - a value the player set that way already is never touched, and not put back either;
/// - a line in the log each time (the caller writes `Outcome.logLine`).
/// The Dock reads the setting only when it starts, so it is restarted after a change; under the curtain or behind
/// Nightforge's full screen nobody sees that.
enum DockAutoHide {
    /// Reading and changing the setting, and restarting the Dock; tests give their own.
    struct System {
        /// The setting now; nil when it was never set (the Dock's default: shown).
        var read: () -> Bool?
        var write: (Bool) -> Void
        var restartDock: () -> Void
    }

    /// One step at a time, in the order asked: `restore` at a start after a crash and `engage` at a game started right
    /// after it, each in a task of its own, could overtake each other – restore then put the setting back after engage had
    /// found its note and left it, and the Dock stayed in sight for that first game (audit K2, 23.11.2026).
    private static let steps = DispatchQueue(label: "nightforge.dock-autohide", qos: .utility)

    /// Runs `work` after every step asked for before it, away from the caller's thread.
    static func serially(_ work: @escaping @Sendable () -> Void) {
        steps.async(execute: work)
    }

    /// `serially`, and waits for it: at quit, where an `engage` asked for just before would otherwise run after the
    /// Dock was put back, and the Dock stayed hidden once Nightforge was gone (W1 of the cross-read, 23.11.2026).
    /// Never from a step itself (it would wait for itself).
    static func seriallyAndWait<T>(_ work: () -> T) -> T {
        steps.sync(execute: work)
    }

    /// Set while Nightforge has the setting on for console mode: what to put back (always false so far).
    static let restoreKey = "console.dockAutoHideBefore"

    enum Outcome: Equatable {
        /// Switched on for console mode.
        case set
        /// On already, by the player: left alone, and left on afterwards.
        case playersAlready
        /// On already, by Nightforge.
        case oursAlready
        /// Put back to shown.
        case putBack
        /// Nightforge had it on, and the player switched it off meanwhile: nothing to put back.
        case playerChanged
        /// Nothing of Nightforge's to put back.
        case nothing

        /// For the log; nil where nothing happened.
        var logLine: String? {
            switch self {
            case .set: return "Console mode: the Dock hides itself while games are played (macOS's setting, put back afterwards); the Dock restarts to read it (killall Dock)"
            case .playersAlready: return "Console mode: the Dock hides itself already, the player's own setting – left as it is"
            case .putBack: return "Console mode over: the Dock's setting is back as it was (shown); the Dock restarts to read it (killall Dock)"
            case .playerChanged: return "Console mode over: the player changed the Dock's setting meanwhile – left as it is"
            case .oursAlready, .nothing: return nil
            }
        }
    }

    /// Console mode starts a game: the Dock hides itself from now on, unless the player has it so already.
    static func engage(_ system: System, defaults: UserDefaults = .standard) -> Outcome {
        if defaults.object(forKey: restoreKey) != nil { return .oursAlready }
        if system.read() == true { return .playersAlready }
        // Kept first: a crash right after the change still finds what to put back.
        defaults.set(false, forKey: restoreKey)
        system.write(true)
        system.restartDock()
        return .set
    }

    /// Console mode ends, Nightforge quits, or starts after a crash: what Nightforge changed is put back.
    static func restore(_ system: System, defaults: UserDefaults = .standard) -> Outcome {
        guard let before = defaults.object(forKey: restoreKey) as? Bool else { return .nothing }
        defer { defaults.removeObject(forKey: restoreKey) }
        guard system.read() == true, before == false else { return .playerChanged }
        system.write(before)
        system.restartDock()
        return .putBack
    }

    /// The Mac's own setting (`defaults read com.apple.dock autohide`), and the Dock started anew to read it.
    static var live: System { System(
        read: {
            CFPreferencesAppSynchronize("com.apple.dock" as CFString)
            return CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool
        },
        write: { hides in
            CFPreferencesSetAppValue("autohide" as CFString, hides as CFBoolean, "com.apple.dock" as CFString)
            CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        },
        restartDock: {
            // launchd starts the Dock again at once.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = ["Dock"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        })
    }
}
