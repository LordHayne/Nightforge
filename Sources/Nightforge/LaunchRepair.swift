import Foundation

/// What the curtain says while Nightforge mends a start that ended without a picture: one line, a short
/// sentence only where it's true once or where the start ends. The player's rule of 15.11.2026 (board
/// "Vorhang nach der Regel", docs/entwuerfe/vorhang-regel): template B's three steps stood two or three
/// seconds, too short to read ("man sieht die neue Anzeige nur kurz"), so what Nightforge found and does
/// goes to the log (`logLine`), not on the screen.
enum LaunchRepair: Equatable {
    /// The game is gone; Nightforge reads what it left.
    case looking
    /// The table changed the recipe: the same way once more (NextStart.Step.again).
    case again
    /// A proven way's one quiet start more (LaunchHealth.startsAgainQuietly): no cause known, so none said.
    case onceMore
    /// On to another way of the ladder (NextStart.Step.way).
    case otherWay
    /// Wine said what's missing: it's set up, then the same way once more.
    case settingUp
    /// Nothing explains the end: the same way once more with Wine's debug channels (CloserLook).
    case closerLook
    /// Every way tried: said on the curtain for `endStands` before the library.
    case gaveUp
    /// The player said yes to the root the game needed: the same way once more (NextStart.after(rootTrusted:)).
    case rootAdded
    /// … no: the start ends here, said for `endStands`.
    case rootDeclined
    /// A way that had worked ended without a picture again and has had its tries: it keeps its place
    /// (NextStart.Step.keepsItsPlace), and the start ends here, said for `endStands`.
    case keptPlace
    /// Graphics chosen by hand, or nothing known about the game: no other way to try (NextStart.Step.noOtherWay).
    case noOtherWay

    /// How long the honest end stands on the curtain before the library comes.
    static let endStands: TimeInterval = 3

    /// Whatever Nightforge mends, one more try is what the player sees.
    var title: String {
        switch self {
        case .looking, .again, .onceMore, .otherWay, .closerLook, .rootAdded: return L10n.t("One more try …")
        case .settingUp: return L10n.t("Setting up …")
        case .gaveUp, .keptPlace, .noOtherWay: return L10n.t("That didn't work.")
        case .rootDeclined: return L10n.t("The game doesn't start this way.")
        }
    }

    /// No start follows it: the line says the end. Every other one promises a try, and one comes
    /// (the coordinator's rule of 15.11.2026: "Sagt der Vorhang „Noch ein Versuch …“, muss einer kommen").
    var endsStart: Bool {
        switch self {
        case .gaveUp, .rootDeclined, .keptPlace, .noOtherWay: return true
        case .looking, .again, .onceMore, .otherWay, .settingUp, .closerLook, .rootAdded: return false
        }
    }

    var detail: String? {
        switch self {
        case .settingUp: return L10n.t("Only the first time.")
        case .gaveUp, .keptPlace, .noOtherWay: return L10n.t("You'll be back in the library in a moment.")
        case .rootDeclined: return L10n.t("It doesn't run without the certificate.")
        case .looking, .again, .onceMore, .otherWay, .closerLook, .rootAdded: return nil
        }
    }

    /// What left the screen, for the log: what Nightforge found and does now.
    var logLine: String {
        switch self {
        case .looking: return "the game closed right away, Nightforge looks into it"
        case .again: return "the cause found, the same way once more"
        case .onceMore: return "no cause known, a proven way once more"
        case .otherWay: return "on to another way, Nightforge remembers what runs"
        case .settingUp: return "a piece of Windows was missing, it's set up, then the same way once more"
        case .closerLook: return "nothing explains the end, a closer look with the next start"
        case .gaveUp: return "every way tried, back to the library"
        case .rootAdded: return "the certificate is added, the game starts once more"
        case .rootDeclined: return "the certificate isn't added, the start ends; asked again next time"
        case .keptPlace: return "a way that had worked ended without a picture again, it keeps its place; no further try, back to the library"
        case .noOtherWay: return "no other way to try (graphics chosen by hand, or nothing known about the game), back to the library"
        }
    }

    /// Whether the curtain says "One more try …" as soon as a start has ended without a picture, before Nightforge
    /// has read why (`looking`). Not where the end may turn out to be the player's own, with no start after it: a
    /// way that had worked ending early for the first time (`provenFirstShortEnd` – quit early, by the look of it;
    /// its one quiet start more says `onceMore` once it's sure the game is gone), and an end at a question of the
    /// game's own that the player answered (`endedAtOwnQuestion`). Up to 17.11.2026 the line stood there too, for
    /// as long as Nightforge read, and then the page came. Where such an end is a failed start after all, the try
    /// is said once it's decided (`after`).
    static func saysLooking(provenFirstShortEnd: Bool, endedAtOwnQuestion: Bool) -> Bool {
        !provenFirstShortEnd && !endedAtOwnQuestion
    }

    /// What the curtain says for the decision after a failed start. nil: it says nothing of its own – the
    /// engine before has its own line (LaunchPhase.rollingBack). A proven way keeping its place and a way
    /// chosen by hand ended the start without a word up to 15.11.2026, right after "One more try …"
    /// (`looking`): they say the end now, as every way tried does.
    static func after(_ step: NextStart.Step) -> LaunchRepair? {
        switch step {
        case .again(_, let why):
            if why == [NextStart.engineBefore] { return nil }
            if why == [NextStart.closerLook] { return .closerLook }
            return why.contains("missing-runtime") ? .settingUp : .again
        case .way: return .otherWay
        case .giveUp: return .gaveUp
        case .keepsItsPlace: return .keptPlace
        case .noOtherWay: return .noOtherWay
        }
    }
}
