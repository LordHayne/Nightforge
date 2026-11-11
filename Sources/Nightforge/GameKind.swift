import Foundation

/// What sort of game this is, as far as its files say: the engine and its version, what it draws with,
/// the libraries it brings along. Two games of a sort tend to need the same things to start, so what one
/// start teaches is kept by sort as well as by game (StartEvidence) – nothing decides by it yet
/// (docs/ENTWURF-STARTREZEPT.md, stage 1).
struct GameKind: Codable, Equatable {
    /// "unreal", "unity", "other".
    var engine: String
    /// "4.26", "2017.4": major and minor, where the files say it.
    var engineVersion: String?
    /// "d3d11", "d3d12", … sorted.
    var apis: [String]
    /// "physx3", "steamworks", "bink", … sorted (`GameKind.middleware`).
    var middleware: [String]
    /// Another company's launcher the game starts through.
    var launcher: String?
    var antiCheat: Bool
    /// 32 or 64, where the program's header was read.
    var bits: Int?

    /// The engine with its major version ("unreal4", "unity2017"); nil where the version isn't known.
    var generation: String? {
        engineVersion?.split(separator: ".").first.map { engine + $0 }
    }

    /// The engine with its major version, and what it draws with: "unreal4|d3d11+d3d12".
    var coarse: String {
        [engine + (engineVersion?.split(separator: ".").first.map(String.init) ?? ""), apis.joined(separator: "+")]
            .joined(separator: "|")
    }

    /// … with the full version and the libraries: "unreal4.26|d3d11+d3d12|aftermath+physx3+steamworks".
    var fine: String {
        [engine + (engineVersion ?? ""), apis.joined(separator: "+"), middleware.joined(separator: "+")].joined(separator: "|")
    }

    /// Libraries by what they leave in a game folder or a program's import table: a name's beginning,
    /// for DLLs and for folders (Unreal keeps each under Engine/Binaries/ThirdParty/<Name>).
    static let middlewareNames: [(tag: String, prefixes: [String])] = [
        ("physx3", ["physx3"]),
        ("physx2", ["physxloader", "physxcore", "physxcooking", "nxcooking", "nxcharacter"]),
        ("apex", ["apexframework", "apex_"]),
        ("bink", ["bink2w", "binkw", "bink2"]),
        ("fmod", ["fmod"]),
        ("wwise", ["wwise", "aksoundengine"]),
        ("steamworks", ["steam_api", "steamworks"]),
        ("eos", ["eossdk"]),
        ("galaxy", ["galaxy.dll", "galaxy64.dll"]),
        ("dlss", ["nvngx_dlss"]),
        ("aftermath", ["gfsdk_aftermath"]),
        ("streamline", ["sl.interposer"]),
        ("xess", ["libxess"]),
        ("fsr", ["ffx_fsr", "amd_fidelityfx"]),
        ("cef", ["libcef"]),
        ("oodle", ["oo2core"]),
        ("discord", ["discord_game_sdk", "discord-rpc"]),
        ("openvr", ["openvr_api"]),
    ]

    /// The libraries among `names` – file and folder names from the game folder and DLL names from its
    /// programs' import tables, lower-cased. Only DLLs and folders count: a picture or a pack named like
    /// a library isn't one.
    static func middleware(in names: Set<String>) -> [String] {
        let candidates = names.filter { $0.hasSuffix(".dll") || !$0.contains(".") }
        return middlewareNames.filter { entry in
            candidates.contains { name in entry.prefixes.contains(where: name.hasPrefix) }
        }.map(\.tag).sorted()
    }

    /// Unreal's version from its program's version resource – every Unreal program carries the engine's
    /// there (ABZU 4.12.5, It Takes Two 4.26.0, Hogwarts Legacy 4.27.2, REANIMAL 5.4.4; 10.11.2026). Only 4
    /// and 5: another number is the game's own.
    static func unrealVersion(_ fileVersion: [Int]?) -> String? {
        guard let fileVersion, fileVersion.count >= 2, [4, 5].contains(fileVersion[0]), (0...99).contains(fileVersion[1])
        else { return nil }
        return "\(fileVersion[0]).\(fileVersion[1])"
    }

    /// Unity's version as its data files begin with it: "2017.4.30f1" → "2017.4", "6000.3.10f1" → "6000.3".
    static func unityVersion(inHead head: Data) -> String? {
        let text = String(decoding: head.map { $0 >= 0x20 && $0 < 0x7F ? $0 : 0x20 }, as: UTF8.self)
        guard let pattern = try? Regex("([0-9]{1,4})\\.([0-9]{1,2})\\.[0-9]{1,3}[abfp][0-9]{1,3}"),
              let found = text.firstMatch(of: pattern), found.output.count == 3,
              let major = found.output[1].substring, let minor = found.output[2].substring
        else { return nil }
        return "\(major).\(minor)"
    }
}

extension GameAnalysis {
    /// The game's sort, from what the look at its files found.
    var kind: GameKind {
        GameKind(engine: engine.rawValue, engineVersion: engineVersion, apis: apis.sorted().map(\.rawValue),
                 middleware: middleware.sorted(), launcher: launcher, antiCheat: !antiCheat.isEmpty,
                 bits: is64Bit.map { $0 ? 64 : 32 })
    }
}
