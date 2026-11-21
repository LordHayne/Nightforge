import Foundation

@MainActor var failures = 0
/// Home has been asked to show a game that isn't on its rail (a message's Play, a game that ended): it may until
/// the player moves on from it.
@MainActor var shownOffRail = false
@MainActor func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures += 1
        if failures < 25 { print("✗ \(message)") }
    }
}

/// What has to hold after anything the player does.
@MainActor func checkRules(_ model: LibraryModel, after step: String) {
    let games = model.games
    check(games.isEmpty || games.indices.contains(model.selectedIndex), "selection \(model.selectedIndex) of \(games.count) games after \(step)")
    check(model.homeRail.allSatisfy(games.indices.contains), "Home's rail \(model.homeRail) points past \(games.count) games after \(step)")
    check(Set(model.homeRail).count == model.homeRail.count, "a game twice on Home's rail after \(step)")
    if case .detail(let id, _) = model.route {
        check(games.contains { $0.holds(id) }, "a game's page without its game after \(step)")
    }
    if model.route == .home, !model.homeOnAllGames, !model.homeRail.isEmpty, !shownOffRail {
        check(model.homeRail.contains(model.selectedIndex), "Home selects \(model.selectedIndex), not on its rail \(model.homeRail), after \(step)")
    }
    if model.route == .home { check(model.searchText.isEmpty, "a search open on Home after \(step)") }
    if !model.showingHidden {
        check(!games.contains { $0.inLibrary && model.isHidden($0) }, "a hidden game shown after \(step)")
    }
    if model.showingHidden { check(!model.hiddenGames.isEmpty, "the hidden list open with nothing hidden after \(step)") }
    // Home's sources decide what's on its rail.
    for index in model.homeRail where !model.showingHidden {
        check(games.indices.contains(index), "the rail's games exist after \(step)")
    }
    if model.quickMenu != nil { check(model.quickMenuGame != nil, "the quick menu open on a game that's gone after \(step)") }
    check(model.homePlace >= 0 && model.homePlace <= model.homeRail.count, "Home's place \(model.homePlace) after \(step)")
    if let target = model.backTarget { check(target != model.route, "back leads nowhere after \(step)") }
    if model.route == .library {
        check(games.isEmpty || model.gridLayout.position(of: model.selectedIndex) != nil, "the library's selection isn't in its grid after \(step)")
        check(Set(model.gridLayout.order) == Set(games.indices), "the grid leaves games out after \(step)")
    }
}

struct Listed { let id: Int; let name: String }

@MainActor func library() -> [Listed] {
    ["Doom", "Doom Eternal", "No Man's Sky", "Sky Force", "ABZU", "Ärger", "The Witness", "Control", "Portal 2", "Hades", "Celeste", "Inside"]
        .enumerated().map { Listed(id: 1000 + $0.offset, name: $0.element) }
}

@MainActor func fuzz(seed: UInt64, steps: Int) async {
    var random = WorldRandom(seed)
    let model = LibraryModel()
    let all = library()
    var present = Set<Int>()
    for (index, game) in all.enumerated() where index % 3 != 2 {
        ModelWorld.steamGame(game.id, game.name, lastPlayed: index % 2 == 0 ? 1_700_000_000 + index : 0)
        present.insert(game.id)
    }
    await ModelWorld.scan(model)
    checkRules(model, after: "the first scan (seed \(seed))")

    let words = ["", "", "d", "do", "sky", "zz", "ä", " ", "rdr2", "the w", "p2"]
    for number in 0..<steps {
        let games = model.games
        let selected = model.selected
        var step: String
        let routeBefore = model.route
        switch random.below(29) {
        case 0: let word = random.pick(words); model.searchText = word; step = "search “\(word)”"
        case 1: model.goHome(); step = "goHome"
        case 2: model.goLibrary(); step = "goLibrary"
        case 3: model.toggleLibrary(); step = "toggleLibrary"
        case 4: model.openDetail(); step = "openDetail"
        case 5: model.back(); step = "back"
        case 6: model.forward(); step = "forward"
        case 7: let by = random.pick([-5, -1, 1, 5]); model.move(by); step = "move \(by)"
        case 8: let by = random.pick([-2, -1, 1, 2]); model.moveRow(by); step = "moveRow \(by)"
        case 9: let first = random.below(2) == 0; model.jump(toStart: first); step = "jump \(first)"
        case 10:
            guard !games.isEmpty else { continue }
            // What can be clicked: on Home the rail.
            let index = model.route == .home ? (model.homeRail.isEmpty ? 0 : random.pick(model.homeRail)) : random.below(games.count)
            model.select(index); step = "select \(index)"
        case 11: let place = random.below(model.homeRail.count + 2); model.selectOnHome(place: place); step = "Home place \(place)"
        case 12: if let selected { model.toggleHidden(selected) }; step = "toggleHidden"
        case 13: if let selected { model.togglePinned(selected) }; step = "togglePinned"
        case 14: if let selected { model.toggleLater(selected) }; step = "toggleLater"
        case 15: if let selected { model.removeFromHome(selected) }; step = "removeFromHome"
        case 16: model.toggleShowingHidden(); step = "toggleShowingHidden"
        case 17: model.filters.sort = model.filters.sort.next; step = "next sort"
        case 18: model.filters.store = random.pick([nil, .steam, .gog, .epic]); step = "store filter"
        case 19:
            let filter = random.pick(LibraryFilters.Filter.allCases)
            if model.filters.on.contains(filter) { model.filters.on.remove(filter) } else { model.filters.on.insert(filter) }
            step = "filter \(filter)"
        case 20:
            if model.laterCount > 0 { model.filters.later.toggle() }
            step = "Play Later list"
        case 21: model.clearFilters(); step = "clearFilters"
        case 22: model.openLaunchers(); step = "openLaunchers"
        case 23: model.gridColumns = 1 + random.below(7); step = "columns \(model.gridColumns)"
        case 24:
            if model.quickMenu == nil, !games.isEmpty {
                model.openQuickMenu(at: model.route == .home ? (model.homeRail.isEmpty ? 0 : random.pick(model.homeRail)) : random.below(games.count))
            } else {
                model.closeQuickMenu()
            }
            step = "quick menu"
        case 25:
            guard !model.allGames.isEmpty else { continue }
            let game = random.pick(model.allGames); model.reveal(game); step = "reveal \(game.name)"
            shownOffRail = model.route == .home
        case 27:
            let source = random.pick(HomeSources.Source.allCases), on = random.below(2) == 0
            model.setHomeSource(source, on); step = "Home source \(source) \(on)"
        case 28:
            let pinned = model.pinnedHomeGames
            guard !pinned.isEmpty else { continue }
            let game = random.pick(pinned), by = random.pick([-1, 1]), before = pinned.map(\.id)
            model.movePin(game, by: by)
            let after = model.pinnedHomeGames.map(\.id)
            check(Set(before) == Set(after) && after.count == before.count, "moving a pin keeps all of them: \(before) → \(after)")
            if let place = before.firstIndex(of: game.id), before.indices.contains(place + by) {
                check(after.firstIndex(of: game.id) == place + by, "and moves it one place (seed \(seed)): \(before) → \(after)")
            } else {
                check(before == after, "past the end nothing changes: \(before) → \(after)")
            }
            step = "move pin \(by)"
        default:
            // A game comes or goes between two looks.
            let game = random.pick(all)
            if present.remove(game.id) != nil {
                ModelWorld.removeSteamGame(game.id, game.name)
                step = "\(game.name) gone"
            } else {
                ModelWorld.steamGame(game.id, game.name, lastPlayed: random.below(2) == 0 ? 1_700_000_000 + random.below(1000) : 0)
                present.insert(game.id)
                step = "\(game.name) back"
            }
            await ModelWorld.scan(model)
        }
        if number % 40 == 0 { await ModelWorld.settle(5) }
        if !step.hasPrefix("reveal"), model.route != routeBefore || (step.hasPrefix("move ") && !step.hasPrefix("move pin")) || step.hasPrefix("jump") || step.hasPrefix("Home place") || step.hasPrefix("select") { shownOffRail = false }
        checkRules(model, after: "\(step) (seed \(seed), step \(number))")
    }
    for game in all { ModelWorld.removeSteamGame(game.id, game.name) }
    await ModelWorld.scan(model)
    checkRules(model, after: "all games gone (seed \(seed))")
    check(model.games.isEmpty && model.homeRail.isEmpty, "nothing left to show (seed \(seed))")
}

@main struct Main {
    static func main() async {
        await ModelWorld.begin()
        for seed in UInt64(1)...6 { await fuzz(seed: seed, steps: 500) }
        await MainActor.run {
            if failures == 0 { print("✓ The library's pages and selection under random use (3000 steps)") } else { print("✗ \(failures) failures") }
            exit(failures == 0 ? 0 : 1)
        }
    }
}
