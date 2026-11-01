// Checks the graphics presets: what each sets at a start, the order "Most compatible" tries the
// ways in, and that options saved before the presets keep their meaning: tests/GraphicsPresetTest/run.sh
import Foundation

@main
struct GraphicsPresetTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func decode(_ json: String) -> GameOptions? {
        try? JSONDecoder().decode(GameOptions.self, from: Data(json.utf8))
    }

    static func profile(_ json: String) -> GameProfile? {
        try? JSONDecoder().decode(GameProfile.self, from: Data(json.utf8))
    }

    static func ids(_ analysis: GameAnalysis, _ preset: GraphicsPreset, profile json: String? = nil, d3dMetal: Bool = false) -> [String] {
        let profile = json.flatMap(profile)
        return LaunchHealth.ladder(LaunchHealth.attempts(for: analysis, profile: profile, d3dMetal: d3dMetal, vulkanLayer: true),
                                   preset: preset, profile: profile).map(\.id)
    }

    static func main() {
        // MARK: Options saved before the presets
        let untouched = decode(#"{"metalHUD":true,"extraArgs":"-skipintro","graphics":"automatic","metalFX":"automatic"}"#)
        check(untouched?.preset == .automatic && untouched?.metalHUD == true && untouched?.extraArgs == "-skipintro",
              "old options without expert changes read as Automatic, HUD and launch options kept")
        check(decode(#"{"graphics":"dxvk"}"#)?.preset == .custom, "a layer picked by hand reads as Custom")
        check(decode(#"{"fps":40}"#).map { $0.preset == .custom && $0.frameLimit == 40 } == true, "a frame limit picked by hand reads as Custom")
        check(decode(#"{"metalFX":"off"}"#)?.preset == .custom, "MetalFX switched off by hand reads as Custom")
        check(decode(#"{"frameLimit":60,"upscaling":true}"#).map { $0.preset == .custom && $0.frameLimit == 60 && $0.upscaling == .on } == true,
              "0.1.4's fields still read, as Custom")
        check(decode(#"{"hdr":true,"version":"windows"}"#)?.preset == .automatic, "HDR and the version aren't part of a preset")
        check(decode(#"{"preset":"turbo","graphics":"automatic"}"#)?.preset == .automatic,
              "a preset from a newer Nightforge reads like the old options, not as a lost setting")
        var stored = GameOptions()
        stored.choose(.compatible)
        stored.extraArgs = "-dx11"
        let data = (try? JSONEncoder().encode(stored)) ?? Data()
        check((try? JSONDecoder().decode(GameOptions.self, from: data)) == stored, "a preset survives saving")

        // MARK: Picking a preset
        var picked = GameOptions()
        picked.graphics = .dxvk
        picked.frameLimit = 30
        picked.upscaling = .off
        picked.preset = .custom
        picked.metalHUD = true
        picked.choose(.fastest)
        check(picked.preset == .fastest && picked.graphics == .automatic && picked.frameLimit == nil && picked.upscaling == .automatic,
              "a preset puts the expert options back to automatic")
        check(picked.metalHUD, "… and leaves the rest alone")
        var reset = GameOptions()
        reset.choose(.automatic)
        check(reset == GameOptions(), "Automatic is the default, saved as nothing at all")

        let game = GameID.steam(999_999_901)
        GameOptionsStore.save(GameOptions(), for: game)
        GameOptionsStore.choose(.compatible, for: game)
        check(GameOptionsStore.load(game).preset == .compatible, "a preset picked after a failed start is stored")
        GameOptionsStore.save(GameOptions(), for: game)
        check(UserDefaults.standard.data(forKey: "options.\(game.key)") == nil, "back to Automatic leaves nothing behind")

        // MARK: What a start uses
        func preset(_ preset: GraphicsPreset) -> GameOptions {
            var options = GameOptions()
            options.choose(preset)
            return options
        }
        let balanced = preset(.balanced).resolved(refreshRate: 120, profile: nil)
        check(balanced.frameLimit == 60 && balanced.upscaling == .on && balanced.graphics == .automatic,
              "Balanced on 120 Hz: MetalFX, 60 FPS, the layer automatic")
        check(preset(.balanced).resolved(refreshRate: 60, profile: nil).frameLimit == 60, "Balanced on 60 Hz: 60 FPS")
        check(preset(.balanced).resolved(refreshRate: 144, profile: nil).frameLimit == 72, "Balanced on 144 Hz: 72 FPS")
        let fastest = preset(.fastest).resolved(refreshRate: 120, profile: nil)
        check(fastest.frameLimit == 0 && fastest.upscaling == .on, "Fastest: MetalFX, no limit")
        let compatible = preset(.compatible).resolved(refreshRate: 120, profile: nil)
        check(compatible.frameLimit == 60 && compatible.upscaling == .off && compatible.graphics == .automatic,
              "Most compatible: no MetalFX, 60 FPS, the layer from its own order")
        check(preset(.automatic).resolved(refreshRate: 120, profile: nil) == GameOptions(), "Automatic stays automatic")
        var custom = GameOptions()
        custom.preset = .custom
        custom.graphics = .dxvk
        custom.frameLimit = 40
        check(custom.resolved(refreshRate: 120, profile: nil) == custom, "Custom is what the expert options say")

        let noMetalFX = profile(#"{"metalFX": false, "frameLimit": 40}"#)
        check(preset(.balanced).resolved(refreshRate: 120, profile: noMetalFX).upscaling == .off,
              "a game whose profile rules MetalFX out goes without, even on Balanced")
        check(preset(.fastest).resolved(refreshRate: 120, profile: noMetalFX).upscaling == .off, "… and on Fastest")
        check(preset(.balanced).resolved(refreshRate: 120, profile: noMetalFX).frameLimit == 40, "a profile's frame limit stands for Balanced")
        check(preset(.compatible).resolved(refreshRate: 120, profile: noMetalFX).frameLimit == 60, "Most compatible keeps its 60 FPS")

        // Balanced, Fastest and Most compatible fix the limit: nothing to learn against them.
        let paced = GameID.steam(999_999_902)
        for fixed in [GraphicsPreset.balanced, .fastest, .compatible] {
            let pacing = FramePacing.automaticLimit(game: paced, options: preset(fixed).resolved(refreshRate: 120, profile: nil),
                                                    profile: nil, refreshRate: 120)
            check(!pacing.learning, "\(fixed.rawValue): FramePacing doesn't learn")
        }
        let automaticPacing = FramePacing.automaticLimit(game: paced, options: preset(.automatic).resolved(refreshRate: 120, profile: nil),
                                                         profile: nil, refreshRate: 120)
        check(automaticPacing.limit == (Prefs.sharpAndSmooth ? 60 : 0), "Automatic: the display's even rate")
        check(automaticPacing.learning == Prefs.sharpAndSmooth, "… which Automatic learns from")

        // What FramePacing learned stands at the next start – until the display or the layer changes.
        // (Kept in this test program's own defaults under a game ID no store has; removed again.)
        let automatic = preset(.automatic).resolved(refreshRate: 120, profile: nil)
        let pacingKey = "framePacing.\(paced.key)"
        func kept() -> FramePacing.State? {
            UserDefaults.standard.data(forKey: pacingKey).flatMap { try? JSONDecoder().decode(FramePacing.State.self, from: $0) }
        }
        if Prefs.sharpAndSmooth {
            let context = FramePacing.Context(refreshRate: 120, upscaling: automatic.effectiveUpscaling(), graphics: automatic.graphics)
            UserDefaults.standard.set(try? JSONEncoder().encode(FramePacing.State(context: context, limit: 40)), forKey: pacingKey)
            let learned = FramePacing.automaticLimit(game: paced, options: automatic, profile: nil, refreshRate: 120)
            check(learned.limit == 40 && learned.learning, "the limit it learned: \(learned.limit)")
            check(FramePacing.automaticLimit(game: paced, options: automatic, profile: nil, refreshRate: 60).limit == 60,
                  "another display starts over")
            check(FramePacing.automaticLimit(game: paced, options: automatic, profile: profile(#"{"frameLimit": 30}"#), refreshRate: 120) == (30, false),
                  "a profile's limit stands and isn't learned against")

            FramePacing.recordStart(game: paced, options: automatic, profile: nil, refreshRate: 120, logMark: 7, limit: 40, learning: true)
            check(kept()?.limit == 40 && kept()?.mark == 7 && kept()?.ranWith == 40, "a start is noted with its limit, the learned one kept")
            FramePacing.recordStart(game: paced, options: automatic, profile: nil, refreshRate: 120, logMark: 9, limit: 50, learning: false)
            check(kept()?.mark == 9 && kept()?.ranWith == nil, "a limit the player chose says nothing about the game")
            FramePacing.recordStart(game: paced, options: automatic, profile: nil, refreshRate: 60, logMark: 11, limit: 60, learning: true)
            check(kept()?.limit == nil && kept()?.context.refreshRate == 60, "a start on another display starts over")
            check(FramePacing.automaticLimit(game: paced, options: automatic, profile: nil, refreshRate: 120).limit == 60,
                  "back on the first display: the even rate again")
            UserDefaults.standard.removeObject(forKey: pacingKey)
        }

        // MARK: The order "Most compatible" tries the ways in
        let d3d11 = GameAnalysis(apis: [.d3d11])
        check(ids(d3d11, .automatic) == ["dxmt", "dxvk"], "Automatic: DXMT first")
        check(ids(d3d11, .balanced) == ids(d3d11, .automatic) && ids(d3d11, .fastest) == ids(d3d11, .automatic),
              "Balanced and Fastest keep Automatic's order (and what it learned)")
        check(ids(d3d11, .compatible) == ["dxvk", "dxmt"], "Most compatible: DXVK, the way that works with more games, first")
        check(ids(GameAnalysis(apis: [.d3d9]), .compatible) == ["wined3d", "dxvk"], "DirectX 9: Wine's own Direct3D first")
        check(ids(GameAnalysis(apis: [.vulkan]), .compatible) == ids(GameAnalysis(apis: [.vulkan]), .automatic),
              "Vulkan has one way: nothing to reorder")
        check(ids(GameAnalysis(apis: [.d3d12]), .compatible, d3dMetal: true) == ["d3dmetal"], "DirectX 12 only: D3DMetal, the one way it runs")
        // Palworld: tested with DXMT, DXVK shows a black world.
        let unreal = GameAnalysis(apis: [.d3d11, .d3d12], engine: .unreal)
        check(ids(unreal, .compatible, profile: #"{"graphics": "dxmt", "source": "mac"}"#).first == "dxmt -dx11",
              "a layer a profile was tested with stays first: \(ids(unreal, .compatible, profile: #"{"graphics": "dxmt", "source": "mac"}"#))")
        // The Last Caretaker: DirectX 11 fails on every layer, DirectX 12 through D3DMetal runs.
        let caretaker = ids(unreal, .compatible, profile: #"{"graphics": "d3dmetal", "source": "mac"}"#, d3dMetal: true)
        check(caretaker == ["d3dmetal", "dxvk -dx11", "dxmt -dx11"], "D3DMetal tested: first, then the safest of the rest: \(caretaker)")
        check(Set(ids(unreal, .compatible)) == Set(ids(unreal, .automatic)), "the same ways, only in another order")

        print(failures == 0 ? "✓ all checks passed" : "\(failures) checks failed")
        exit(failures == 0 ? 0 : 1)
    }
}
