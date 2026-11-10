import Foundation

/// All that decides how a game starts, as one value: the graphics layer, the arguments, the DLLs it
/// gets or doesn't, the runtimes set up for it. Today these come together from the profile, the ladder
/// and what earlier starts taught (LaunchHealth, LearnedFixes, Engine.gameDllOverrides); the recipe is
/// what a start is recorded with (StartEvidence), so that what worked can be told from what was only
/// tried. Nothing decides by it yet (docs/ENTWURF-STARTREZEPT.md, stage 1).
struct StartRecipe: Codable, Equatable {
    var graphics: String
    var arguments: [String]
    var dllOverrides: [String: String]
    var runtimes: [String]
    /// Rosetta's AVX is offered to the game.
    var avx: Bool
    var windowsVersion: String?

    /// The recipe of a start on `layer`. `arguments`: the way's own and the switch past the game's
    /// launcher window; the profile's come on top where they belong to this layer.
    static func of(layer: GraphicsLayer, arguments: [String], profile: GameProfile?, learnedRuntimes: [String],
                   avx: Bool, d3dMetalEngine: Bool) -> StartRecipe {
        StartRecipe(graphics: layer.rawValue,
                    arguments: arguments + (profile?.arguments(on: layer) ?? []),
                    dllOverrides: Engine.gameDllOverrides(layer, profile: profile, d3dMetalEngine: d3dMetalEngine),
                    runtimes: Array(Set((profile?.winetricks ?? []) + learnedRuntimes)).sorted(),
                    avx: avx,
                    windowsVersion: profile?.windowsVersion)
    }
}
