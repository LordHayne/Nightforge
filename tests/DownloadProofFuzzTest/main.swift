// The ring, the Downloads panel and the proof line under random downloads: never a claim that isn't so, and damaged
// numbers in a Steam manifest never reach a percentage. DownloadHintsTest has the fixed cases: tests/DownloadProofFuzzTest/run.sh
import Foundation

@main
struct DownloadProofFuzzTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    typealias Proof = DownloadProof
    static let clock = Date(timeIntervalSince1970: 1_800_000_000)

    static func standing() {
        var random = SystemRandomNumberGenerator()
        for _ in 0..<20_000 {
            let listed = Bool.random(using: &random), fetching = Bool.random(using: &random), holding = Bool.random(using: &random)
            let lid = Bool.random(using: &random)
            let list = (0..<Int.random(in: 0...3, using: &random)).map { _ in
                KeepAwake.Download(name: "G", provider: [Provider.steam, .epic, .gog, .battlenet].randomElement(using: &random)!,
                                   platform: Bool.random(using: &random) ? .windows : .mac, builtIn: Bool.random(using: &random), paused: Bool.random(using: &random))
            }
            let word = DownloadStanding.of(listed: listed, fetching: fetching, holding: holding, downloads: list, lidMatters: lid)
            if !listed { check(word == .silent, "nothing listed, and it says something") }
            if word == .awake || word == .awakeLidOpen { check(listed && fetching && holding, "\"stays awake\" with nothing holding it") }
            if word == .awakeLidOpen { check(lid, "asks for the lid where it doesn't matter") }
            if listed, fetching { check(!word.mayDoze, "the ring grey while something fetches") }
            if listed, !fetching { check(word.mayDoze, "the ring lit with nothing fetching") }
            if case .storeStopped = word { check(list.contains { !$0.paused } && !fetching, "a store gone with nothing it should be fetching") }
            check((word.ringWord == nil) == (word.sentence == nil), "a word without its sentence, or the other way: \(word)")
            if failures > 0 { return }
        }
    }

    static func fraction(_ random: inout SystemRandomNumberGenerator) -> Double? {
        switch Int.random(in: 0...9, using: &random) {
        case 0: return nil
        case 1: return 0
        case 2: return 1
        case 3: return .nan  // what 0/0 and "nan" in a damaged file come to
        default: return .random(in: 0...1, using: &random)
        }
    }

    static func outcomes() {
        var random = SystemRandomNumberGenerator()
        let ids = ["a", "b", "c", "d"]
        let sizes: [Int64] = [0, 1, 50_000_000, 200_000_000, 12_000_000_000, Game.largestSize]
        for _ in 0..<40_000 {
            var before: [String: Proof.Mark] = [:], after: [String: Proof.Mark] = [:]
            for id in ids where Bool.random(using: &random) {
                before[id] = Proof.Mark(name: id, fraction: fraction(&random), size: sizes.randomElement(using: &random)!)
            }
            for id in ids where Bool.random(using: &random) {
                let done = Bool.random(using: &random)
                after[id] = Proof.Mark(name: id, fraction: done ? 1 : fraction(&random), size: sizes.randomElement(using: &random)!, finished: done)
            }
            let wall = TimeInterval.random(in: 0...7200, using: &random)
            let slept = Bool.random(using: &random) ? 0 : TimeInterval.random(in: 0...wall, using: &random)
            let stretch = Proof.Stretch(began: clock, awakeAtStart: 500, before: before)
            let proof = Proof.outcome(stretch, ended: clock.addingTimeInterval(wall), awakeAtEnd: 500 + wall - slept, after: after)
            guard let proof else { continue }

            check(wall >= Proof.shortestDark, "a proof for a moment in the dark: \(wall)")
            check(slept < Proof.sleptAfter, "says it kept going when the Mac slept: \(slept)")
            let moved = ids.filter { id in
                guard let was = before[id], let now = after[id], let reached = now.fraction else { return false }
                return reached > (was.fraction ?? 0)
            }
            check(!moved.isEmpty, "a proof with nothing that moved")
            if let bytes = proof.bytes { check(Double(bytes) >= Proof.leastBytes, "a number below what's worth a sentence: \(bytes)") }
            switch proof.kind {
            case .ranOn: check(moved.count == 1 && after[moved[0]]?.finished == false, "\"kept going\" for one that didn't, or for several")
            case .severalRanOn: check(moved.count > 1, "\"downloads\" for one")
            case .finished(let name): check(moved == [name] && after[name]?.finished == true, "\"finished\" for one that hasn't")
            }
            check(!proof.message.isEmpty, "a proof with no words")
            if failures > 0 { return }
        }
    }

    static func moments() {
        let flags = [false, true]
        for game in flags { for curtain in flags { for overlay in flags { for first in flags { for locked in flags { for front in flags {
            let moment = Proof.moment(gameOn: game, curtain: curtain, overlay: overlay, firstStart: first, locked: locked, inFront: front)
            if moment == .show { check(!game && !curtain && !overlay && !first && !locked && front, "shown at a bad moment") }
            if game || curtain || overlay { check(moment == .drop, "a game's start keeps a message for later") }
            if !game, !curtain, !overlay, first || locked || !front { check(moment == .wait, "dropped though nothing replaced it") }
        } } } } } }
    }

    /// The numbers come straight from Steam's manifest: "nan" and "inf" are numbers to `Double(_:)`.
    static func damagedNumbers() {
        var random = SystemRandomNumberGenerator()
        let numbers: [Double] = [0, 1, 1_000, 5e9, -1, .infinity, -.infinity, .nan, 1e308]
        for _ in 0..<5_000 {
            let state = UpdateState(flags: 2, toDownload: numbers.randomElement(using: &random)!, downloaded: numbers.randomElement(using: &random)!,
                                    toStage: numbers.randomElement(using: &random)!, staged: numbers.randomElement(using: &random)!)
            if let share = state.fraction {
                check(share.isFinite && share >= 0 && share <= 1, "a progress no bar or percentage can show: \(share) from \(state)")
                if share.isFinite { _ = Int(share * 100) }  // as the library and the curtain turn it into text
            }
            _ = state.pending
            if failures > 0 { return }
        }
        var progress = UpdateProgress()
        for number in numbers {
            progress.add(UpdateState(flags: 256, toDownload: number, downloaded: number, toStage: number, staged: number), at: clock)
            if let share = progress.fraction { check(share.isFinite, "a followed update with a progress of \(share)") }
        }
    }

    static func main() {
        TestDefaults.useWorkFolder()
        standing()
        outcomes()
        moments()
        damagedNumbers()
        print(failures == 0 ? "✓ What the downloads may say" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
