/// A and B answering a Windows game's question (wrapper/pad-answer.c), for the plain dialogs a
/// game stops at before its first picture. Everything else has the touchpad as a mouse (PadPointer).
enum PadAnswer {
    enum Choice: String { case ok, cancel }

    /// The pad's A and B go to the question only while a Windows game stands at one, this build has the
    /// helper, and the overlay hasn't taken them.
    static func takes(asking: Bool, helperThere: Bool, overlay: Bool) -> Bool {
        asking && helperThere && !overlay
    }

    static func arguments(_ choice: Choice) -> [String] { [choice.rawValue] }

    /// The helper's exit code: 0 it pressed; else the question isn't one of those it can answer.
    static func needsPointer(exit: Int32) -> Bool { exit != 0 }
}
