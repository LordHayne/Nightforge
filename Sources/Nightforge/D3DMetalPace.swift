import Foundation

/// Nightforge's frame limit on D3DMetal (wrapper/d3dmetal-pace.m in hide-steam-dock.dylib, docs/ENTWURF-D3DMETAL-FPS.md).
/// Apple's D3DMetal 3.0 has no switch for one; the library has each frame shown no sooner than 1/limit seconds after
/// the last, as DXMT does. It takes hold only where three things agree: D3DM_MAX_FPS in the process's environment
/// (Steam's, or a store game's own start), D3DMetal loaded, and the permit written here for this one start.
///
/// A game with an anti-cheat or a cheat protection of its own (NextStart.handsOff: Overwatch) gets nothing loaded
/// or changed in its process – the user's rule. So it never gets D3DM_MAX_FPS (`Engine.prepareLaunchEnvironment`,
/// `directLaunchEnvironment`), and its start takes the permit away. A Steam that still has the variable from the game
/// before restarts for it; where it can't (another game runs in it), the missing permit keeps the library out.
enum D3DMetalPace {
    static var permitFile: URL { Engine.supportDir.appendingPathComponent("d3dmetal-pace") }

    /// What the permit says, nil for none: the limit and the game's folder as Wine names it ("C:\…", "Z:\Volumes\…").
    static func permit(limit: Int, gameFolder: String, handsOff: Bool, d3dMetal: Bool) -> String? {
        guard !handsOff, d3dMetal, (1...1000).contains(limit), gameFolder.count >= 4,
              gameFolder.dropFirst().first == ":" else { return nil }
        let folder = gameFolder.hasSuffix("\\") ? String(gameFolder.dropLast()) : gameFolder
        return "\(limit)\n\(folder)\n"
    }

    /// Before every start of a Windows game in Nightforge's prefix: the permit for this one, or none.
    static func prepare(limit: Int, installDir: URL, handsOff: Bool, d3dMetal: Bool, file: URL = permitFile) {
        if let text = permit(limit: limit, gameFolder: Engine.windowsPath(of: installDir), handsOff: handsOff, d3dMetal: d3dMetal) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? text.write(to: file, atomically: true, encoding: .utf8)) == nil { try? FileManager.default.removeItem(at: file) }
        } else {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
