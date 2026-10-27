import Foundation

/// What the Steam store says about a game, from the catalog Steam keeps on the Mac
/// (`appcache/appinfo.vdf`, SteamCatalog): its tags and genres, when it came out, its Metacritic
/// score. The line above a game's title ("RPG / 2023") and its page show them.
struct StoreFacts: Hashable {
    /// Store tags, most voted first, and Steam's own genres (IDs).
    var tags: [Int] = []
    var genres: [Int] = []
    var primaryGenre: Int?
    /// When it came out.
    var released: Date?
    var metascore: Int?

    /// The first tag that names a kind of game ("Survival" – not "Multiplayer", "Indie" or
    /// "Zombies"), else Steam's genre; nil when neither says.
    var genre: String? {
        if let name = tags.lazy.compactMap(Self.tagName).first { return name }
        return ([primaryGenre].compactMap { $0 } + genres).lazy.compactMap(Self.genreName).first
    }

    var year: Int? {
        released.map { Self.calendar.component(.year, from: $0) }
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Steam's genres (`common/genres`); Indie, Free to Play and Early Access say nothing about the game.
    static func genreName(_ id: Int) -> String? {
        switch id {
        case 1: return "Action"
        case 2: return L10n.t("Strategy")
        case 3: return L10n.t("RPG")
        case 4: return L10n.t("Casual")
        case 9: return L10n.t("Racing")
        case 18: return L10n.t("Sports")
        case 25: return L10n.t("Adventure")
        case 28: return "Simulation"
        case 29: return "MMO"
        default: return nil
        }
    }

    /// The store tags that name a kind of game, with Steam's names (`LocalizedTagNames2_english`
    /// in Steam's localconfig.vdf). Themes, settings and modes ("Sci-fi", "Co-op") aren't here.
    static func tagName(_ id: Int) -> String? {
        switch id {
        case 19: return "Action"
        case 21: return L10n.t("Adventure")
        case 122: return L10n.t("RPG")
        case 9: return L10n.t("Strategy")
        case 599: return "Simulation"
        case 597: return L10n.t("Casual")
        case 699: return L10n.t("Racing")
        case 701: return L10n.t("Sports")
        case 1625: return L10n.t("Platformer")
        case 1628: return "Metroidvania"
        case 1645: return "Tower Defense"
        case 1646: return "Hack and Slash"
        case 1662: return "Survival"
        case 1663: return "FPS"
        case 1664: return "Puzzle"
        case 1666: return L10n.t("Card Game")
        case 1667: return "Horror"
        case 1670: return "4X"
        case 1676: return L10n.t("RTS")
        case 1687: return L10n.t("Stealth")
        case 1695: return "Open World"
        case 1698: return "Point & Click"
        case 1716: return "Roguelike"
        case 1718: return "MOBA"
        case 1720: return "Dungeon Crawler"
        case 1721: return L10n.t("Psychological Horror")
        case 1738: return L10n.t("Hidden Object")
        case 1741: return L10n.t("Turn-Based Strategy")
        case 1743: return L10n.t("Fighting")
        case 1752: return L10n.t("Rhythm")
        case 1754: return "MMORPG"
        case 1770: return L10n.t("Board Game")
        case 1773: return "Arcade"
        case 1774: return "Shooter"
        case 3799: return "Visual Novel"
        case 3810: return "Sandbox"
        case 3813: return L10n.t("Real Time Tactics")
        case 3814: return "Third-Person Shooter"
        case 3959: return "Roguelite"
        case 3978: return "Survival Horror"
        case 4106: return "Action-Adventure"
        case 4158: return "Beat ’em up"
        case 4231: return L10n.t("Action RPG")
        case 4255: return "Shoot ’em up"
        case 4328: return L10n.t("City Builder")
        case 4364: return L10n.t("Grand Strategy")
        case 4434: return "JRPG"
        case 4474: return "CRPG"
        case 4885: return "Bullet Hell"
        case 5300: return L10n.t("God Game")
        case 5537: return L10n.t("Puzzle Platformer")
        case 5547: return "Arena Shooter"
        case 5900: return "Walking Simulator"
        case 7178: return L10n.t("Party Game")
        case 9204: return "Immersive Sim"
        case 9271: return L10n.t("Trading Card Game")
        case 10235: return L10n.t("Life Sim")
        case 14139: return L10n.t("Turn-Based Tactics")
        case 16598: return L10n.t("Space Sim")
        case 21725: return L10n.t("Tactical RPG")
        case 29482: return "Souls-like"
        case 32322: return "Deckbuilder"
        case 42804: return "Action Roguelike"
        case 87918: return L10n.t("Farming Sim")
        case 176981: return "Battle Royale"
        case 220585: return L10n.t("Colony Sim")
        case 255534: return L10n.t("Automation")
        case 353880: return "Looter Shooter"
        case 620519: return "Hero Shooter"
        case 916648: return L10n.t("Creature Collector")
        case 1023537: return "Boomer Shooter"
        case 1084988: return "Auto Battler"
        case 1091588: return "Roguelike Deckbuilder"
        case 1100687: return L10n.t("Driving Sim")
        case 1199779: return "Extraction Shooter"
        default: return nil
        }
    }
}
