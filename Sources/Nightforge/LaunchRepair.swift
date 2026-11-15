import Foundation

/// What the curtain says while Nightforge mends a start that ended without a picture: a line, three
/// steps under it with the one it's at, and a sentence. The player sees that Nightforge works on it and
/// doesn't hang, without a word about ways or DLLs. Board "Vorhang bei Fehlstart", template B, the
/// player's pick of 15.11.2026 (docs/entwuerfe/fehlstart, docs/ENTWURF-STARTREZEPT.md 3.3).
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

    struct Step: Equatable {
        enum Mark: Equatable { case done, now, next }
        var label: String
        var mark: Mark
    }

    /// How long the honest end stands on the curtain before the library comes.
    static let endStands: TimeInterval = 3

    var title: String {
        switch self {
        case .looking: return L10n.t("One moment …")
        case .again, .onceMore, .closerLook, .rootAdded: return L10n.t("One more try …")
        case .otherWay: return L10n.t("One more try, another way …")
        case .settingUp: return L10n.t("Setting up the game …")
        case .gaveUp: return L10n.t("That didn't work.")
        case .rootDeclined: return L10n.t("The game doesn't start this way.")
        }
    }

    var detail: String {
        switch self {
        case .looking: return L10n.t("The game closed right away.")
        case .again: return L10n.t("Nightforge found the cause and starts the game once more.")
        case .onceMore: return L10n.t("The game closed right away. Nightforge starts it once more.")
        case .otherWay: return L10n.t("Nightforge remembers what runs.")
        case .settingUp: return L10n.t("A piece of Windows, only this once.")
        case .closerLook: return L10n.t("Nightforge takes a closer look and starts the game once more.")
        case .gaveUp: return L10n.t("Nightforge tried everything it knows. You'll be back in the library in a moment.")
        case .rootAdded: return L10n.t("The certificate is added. The game starts once more.")
        case .rootDeclined: return L10n.t("It doesn't run without the certificate. Nightforge asks again next time.")
        }
    }

    /// Started, what was found, what happens now. Only what has happened is marked done.
    var steps: [Step] {
        let started = Step(label: L10n.t("Started"), mark: .done)
        let lookedAt = Step(label: L10n.t("Looked into it"), mark: .done)
        switch self {
        case .looking:
            return [started, Step(label: L10n.t("Looking into it"), mark: .now), Step(label: L10n.t("New try"), mark: .next)]
        case .again:
            return [started, Step(label: L10n.t("Cause found"), mark: .done), Step(label: L10n.t("Starting again"), mark: .now)]
        case .onceMore:
            return [started, lookedAt, Step(label: L10n.t("Starting again"), mark: .now)]
        case .otherWay:
            return [started, lookedAt, Step(label: L10n.t("Another way"), mark: .now)]
        case .settingUp:
            return [started, Step(label: L10n.t("A piece was missing"), mark: .done), Step(label: L10n.t("Getting it"), mark: .now)]
        case .closerLook:
            return [started, lookedAt, Step(label: L10n.t("Taking a closer look"), mark: .now)]
        case .gaveUp:
            return [started, lookedAt, Step(label: L10n.t("Tried everything"), mark: .done)]
        case .rootAdded:
            return [started, Step(label: L10n.t("Certificate added"), mark: .done), Step(label: L10n.t("Starting again"), mark: .now)]
        case .rootDeclined:
            return [started, lookedAt, Step(label: L10n.t("Not added"), mark: .done)]
        }
    }

    /// What the curtain says for the decision after a failed start. nil: it says nothing of its own – the
    /// engine before has its own line (LaunchPhase.rollingBack), a proven way keeping its place and a way
    /// chosen by hand end the start as before.
    static func after(_ step: NextStart.Step) -> LaunchRepair? {
        switch step {
        case .again(_, let why):
            if why == [NextStart.engineBefore] { return nil }
            if why == [NextStart.closerLook] { return .closerLook }
            return why.contains("missing-runtime") ? .settingUp : .again
        case .way: return .otherWay
        case .giveUp: return .gaveUp
        case .keepsItsPlace, .noOtherWay: return nil
        }
    }
}
