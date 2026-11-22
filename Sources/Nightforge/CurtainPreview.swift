import AppKit

/// Nightforge's own test switch for the loading screen: the real curtain (GameBackdrop) on the main screen for 45 s,
/// with no game started, to look at and record. Set before Nightforge starts:
///
///     defaults write io.github.lordhayne.nightforge gameTest.curtainPreview -string start
///
/// `start`: the curtain as at any start (the light on the seam, the line under the name, no words); `returning`: on
/// the way back from a game; `firsttime`: a long first start's sentence; `update`: an update's bar at 42 %; `wayout`:
/// the way out after 90 s. The switch stays until `defaults delete io.github.lordhayne.nightforge gameTest.curtainPreview`;
/// each start of Nightforge shows it once. No entry in the interface. A build made with NIGHTFORGE_RELEASE has no such
/// switch (as RosettaSupport.testsMissing): neither its key – 23 bytes, text in an optimized build, which the release
/// workflow looks for – nor anything that reads it.
@MainActor
enum CurtainPreview {
    /// The preview's curtain is up: nobody else owns it, and it isn't taken away as an orphan (CurtainEscape.Orphan).
    private(set) static var isUp = false

    #if NIGHTFORGE_RELEASE
    static func startIfAsked() {}
    #else
    static let key = "gameTest.curtainPreview"
    static let shownFor: TimeInterval = 45

    static func startIfAsked(defaults: UserDefaults = .standard) {
        guard let kind = defaults.string(forKey: key) else { return }
        isUp = true
        GameLog.note("Curtain preview (test switch): \(kind), \(Int(shownFor)) s")
        let name = "Black Myth: Wukong Benchmark Tool"
        let until = Date().addingTimeInterval(shownFor)
        let screen = NSScreen.main
        GameBackdrop.raise(name, on: screen) { Date() < until }
        if kind == "returning" { GameBackdrop.returning() }
        Task {
            // The second line comes only after the curtain has stood a moment (GameBackdrop.detailAfter).
            try? await Task.sleep(for: .seconds(GameBackdrop.detailAfter + 0.5))
            switch kind {
            case "update": GameBackdrop.setStatus(LaunchPhase.updating(0.42).title, detail: "18 MB/s", progress: 0.42)
            case "firsttime": GameBackdrop.setStatus(nil, detail: LaunchPhase.firstTimeSentence)
            case "wayout": GameBackdrop.setWayOut(CurtainEscape.tip(.storeQuiet, pad: nil))
            default: break
            }
            try? await Task.sleep(for: .seconds(shownFor - GameBackdrop.detailAfter - 0.5))
            GameBackdrop.hide(after: .zero)
            isUp = false
        }
    }
    #endif
}
