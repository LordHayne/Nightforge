import Foundation

/// Which of a game's programs starts it. The store names one; the player can pick another in the
/// game's options, a profile can name one, and a game with a DirectX 12 program of its own beside
/// the store's starts that one on D3DMetal – Control: Control.exe hands over to Control_DX11.exe,
/// which DXMT and DXVK can't run, while Control_DX12.exe runs on D3DMetal
/// (GameAnalysis.d3d12Program). The other layers have no DirectX 12 and keep the store's program.
/// Epic's and GOG's games Nightforge starts itself; Steam's get the choice through Steam's launch
/// options (SteamProgram).
enum GameProgram {
    /// The program to start: `chosen` (the options' choice, "" = automatic), else `profile`'s, else
    /// on D3DMetal the game's DirectX 12 program, else the store's `store`. A choice that isn't a
    /// file inside the game folder (an update renamed it, a typo) counts as none.
    static func resolve(store: URL, installDir: URL, layer: GraphicsLayer, chosen: String, profile: String?) -> URL {
        if let program = inGame(chosen, installDir) ?? profile.flatMap({ inGame($0, installDir) }) { return program }
        if layer == .d3dmetal, let d3d12 = GameAnalysis.d3d12Program(near: store, in: installDir),
           let program = inGame(d3d12, installDir) {
            return program
        }
        return store
    }

    /// `relative` ("Control_DX12.exe", "bin\x64\Game.exe") inside the game folder, if it's a file there.
    private static func inGame(_ relative: String, _ installDir: URL) -> URL? {
        guard !relative.isEmpty else { return nil }
        let base = installDir.standardizedFileURL
        let file = base.appendingPathComponent(relative.replacingOccurrences(of: "\\", with: "/")).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard file.path.hasPrefix(base.path + "/"), FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        return file
    }
}
