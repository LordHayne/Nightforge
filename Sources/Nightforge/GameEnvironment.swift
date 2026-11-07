import Foundation

/// Switches of Wine's and CrossOver's own that a game can need, set for that game alone: by its
/// profile ("environment") or, for an engine test, by a hidden setting without a switch in the app:
///
///     defaults write io.github.lordhayne.nightforge gameEnvironment.steam.2357570 -dict WINE_SIMULATE_WRITECOPY 1
///
/// (`gameEnvironment.<the game's key>`, read at each start; it wins over the profile). Only the
/// names in `allowed`, and only short plain values: a profile comes from the online list, and an
/// environment variable can load code into every program (DYLD_*) or point one somewhere else.
/// CrossOver sets these per game from a database of its own that isn't free; Recall, which runs
/// Overwatch on the same Wine, sets the first two at every start (2.11.2026).
///
/// One goes the other way: Engine.environment(wine:) gives every Windows program
/// CX_APPLEGPTK_LIBD3DSHARED_PATH, and "off" in its place takes that away for one game, by a test
/// or for good by its profile – Overwatch needs it, and a game it breaks would not:
///
///     defaults write io.github.lordhayne.nightforge gameEnvironment.steam.550 -dict CX_APPLEGPTK_LIBD3DSHARED_PATH off
///     defaults delete io.github.lordhayne.nightforge gameEnvironment.steam.550
///
/// A running Steam restarts for it, as for every switch. "off" is no path: dlopen fails and winecx
/// goes on as without the variable (init_non_native_support, dlls/ntdll/unix/loader.c).
enum GameEnvironment {
    /// The names a game may set, with what they do in winecx.
    static let allowed: [String: String] = [
        // CW Hack 22996 (dlls/ntdll/unix/virtual.c): NtProtectVirtualMemory reports write-copy
        // pages as Windows does once they're written – anti-tamper code checks that.
        "WINE_SIMULATE_WRITECOPY": "write-copy pages as Windows reports them",
        // CrossOver hack 5870 (dlls/kernelbase/volume.c): the volume doesn't say NTFS.
        "CX_HACK_FILESYSTEM_TYPE": "no NTFS in the volume information",
        // CW Hack 24905 (dlls/win32u/d3dkmt.c, vulkan.c): the graphics backend D3DKMT answers for.
        "CX_ACTIVE_GRAPHICS_BACKEND": "the graphics backend D3DKMT answers for",
        // Not read by winecx itself; Recall sets it beside the one above, so a test can match it.
        "CX_GRAPHICS_BACKEND": "the graphics backend CrossOver names",
        // dlls/ntdll/unix/virtual.c: a 32-bit program gets 4 GB of address space.
        "WINE_LARGE_ADDRESS_AWARE": "4 GB for a 32-bit program",
        // D3DMetal, and winecx's list of displays beside it (dlls/win32u/sysparams.c): the graphics card a
        // game sees, in hex ("0x10de" NVIDIA, "0x2684" an RTX 4090). D3DMetal shows an "AMD Compatibility
        // Mode" card, and NGX, DLSS's runtime, wants NVIDIA's (webmonarch's Satisfactory report).
        "D3DM_VENDOR_ID": "the graphics card's maker D3DMetal reports",
        "D3DM_DEVICE_ID": "the graphics card D3DMetal reports",
        // D3DMetal: DirectX ray tracing for a game that asks for it.
        "D3DM_SUPPORT_DXR": "DirectX ray tracing on D3DMetal",
        // CW Hack 22434 (dlls/ntdll/unix/loader.c): winecx loads what this names, so "off" is all
        // that gets past `sanitized`.
        rosettaLibrary: "off: Windows modules aren't registered with Rosetta",
    ]

    static let rosettaLibrary = "CX_APPLEGPTK_LIBD3DSHARED_PATH"

    /// The variables of `raw` that count: allowed names with values of letters, digits, '.', '_'
    /// and '-', at most 32 of them – no paths, no spaces, nothing for a shell.
    static func sanitized(_ raw: [String: String]?) -> [String: String] {
        (raw ?? [:]).filter { name, value in
            allowed[name] != nil && value.wholeMatch(of: #/[A-Za-z0-9._-]{1,32}/#) != nil && (name != rosettaLibrary || value == "off")
        }
    }

    /// What the game starts with on top of everything else: its profile's, with an engine test's over it.
    static func wanted(for game: GameID, profile: GameProfile?, defaults: UserDefaults = .standard) -> [String: String] {
        let test = (defaults.dictionary(forKey: testKey(game)) ?? [:]).compactMapValues { value -> String? in
            switch value {
            case let text as String: return text
            case let number as NSNumber: return number.stringValue
            default: return nil
            }
        }
        return (profile?.environment ?? [:]).merging(sanitized(test)) { _, test in test }
    }

    static func testKey(_ game: GameID) -> String { "gameEnvironment.\(game.key)" }

    /// "WINE_SIMULATE_WRITECOPY=1, …" for the game log.
    static func describe(_ environment: [String: String]) -> String {
        environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    }
}
