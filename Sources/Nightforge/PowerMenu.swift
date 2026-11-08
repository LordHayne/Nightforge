import Foundation

/// Ending the evening with the pad: the Mac to sleep, Nightforge closed. Today that takes the menu
/// bar, ⌘Q or the Dock. The rules; where the entries show is the player's choice (board EinAus).
enum PowerMenu {
    enum Entry: Equatable, Hashable, Identifiable {
        case sleepMac, quitNightforge
        var id: Self { self }
    }

    /// Not with a game on: the overlay ends those. A running download keeps the Mac awake on
    /// purpose (Downloads), so no sleep in the middle of it.
    static func entries(gameOn: Bool, downloading: Bool) -> [Entry] {
        guard !gameOn else { return [] }
        return downloading ? [.quitNightforge] : [.sleepMac, .quitNightforge]
    }

    /// `pmset sleepnow` needs no administrator (man pmset: only changing settings does).
    static let sleepCommand = URL(fileURLWithPath: "/usr/bin/pmset")
    static let sleepArguments = ["sleepnow"]

    static func sleepMac() throws {
        let process = Process()
        process.executableURL = sleepCommand
        process.arguments = sleepArguments
        try process.run()
    }
}
