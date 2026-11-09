import Foundation

/// What a game's own words say about a start that failed, where they decide the next way. Trying the
/// ways in order costs a whole start each; the game often says which one it can't be.
enum StartFailure: Equatable {
    /// It won't take a switch Nightforge added (Hogwarts Legacy and -dx11, 9.11.2026): a way without one.
    case refusedSwitch
    /// It needs DirectX 12: D3DMetal, the one way that has it.
    case needsD3D12

    /// The first thing in a start's crash messages that points to a way; nil when none does.
    static func read(_ messages: [String]) -> StartFailure? {
        messages.lazy.compactMap(reading).first
    }

    private static func reading(_ message: String) -> StartFailure? {
        let text = message.lowercased()
        if text.contains("mutually exclusive"), text.contains("-d3d") { return .refusedSwitch }
        let d3d12 = ["requires directx 12", "requires direct3d 12", "requires d3d12", "d3d12 is required", "dx12 is required",
                     "directx 12 is required", "shader model 6"]
        return d3d12.contains(where: text.contains) ? .needsD3D12 : nil
    }

    func answered(by attempt: LaunchAttempt) -> Bool {
        switch self {
        case .refusedSwitch: return attempt.arguments.isEmpty
        case .needsD3D12: return attempt.graphics == .d3dmetal
        }
    }
}

extension LaunchHealth {
    /// What a game's files say to try first, where no profile or report names a layer. A game with
    /// DirectX 12 that nothing can hold to 11 picks for itself, and DXMT and DXVK have no DirectX 12;
    /// one whose files say nothing at all gets the layer that runs both. (Guardians of the Galaxy,
    /// Control and GTA V Enhanced ended on DXMT, 2. and 9.11.2026.)
    static func fromFiles(_ analysis: GameAnalysis, d3dMetal: Bool) -> GraphicsLayer? {
        guard d3dMetal else { return nil }
        if analysis.apis.isEmpty { return .d3dmetal }
        return analysis.apis.contains(.d3d12) && analysis.preferD3D11Arguments.isEmpty ? .d3dmetal : nil
    }

    /// Whether a game's question on this way may be no choice of the player's: the game can draw with
    /// DirectX 12, this layer has none, and "no suitable adapter" is a question too (Guardians of the
    /// Galaxy, 9.11.2026). Unity's window before the game, where Quit means quit, isn't one of those.
    static func layerCannotDraw(_ analysis: GameAnalysis?, layer: GraphicsLayer) -> Bool {
        guard let analysis, analysis.engine != .unity else { return false }
        return analysis.apis.contains(.d3d12) && layer != .d3dmetal
    }

    /// The line for the log: the ways, the one now, and why that one.
    static func plan(_ name: String, attempts: [LaunchAttempt], index: Int, confirmed: Bool, analysis: GameAnalysis,
                     profile: GameProfile?, hint: GraphicsLayer?, highball: Bool) -> String {
        let way = attempts[index]
        return "Start plan for \(name): \(attempts.map(\.id).joined(separator: ", ")); now \(way.id), "
            + why(way, index: index, confirmed: confirmed, analysis: analysis, profile: profile, hint: hint, highball: highball)
    }

    private static func why(_ way: LaunchAttempt, index: Int, confirmed: Bool, analysis: GameAnalysis, profile: GameProfile?,
                            hint: GraphicsLayer?, highball: Bool) -> String {
        if confirmed { return "it has worked on this Mac" }
        if index > 0 { return "the ways before it didn't work" }
        if profile?.graphics == way.graphics { return "a profile tested on a Mac names it" }
        if hint == way.graphics { return "reports name it (\(highball ? "Highball" : "AppleGamingWiki"))" }
        if analysis.onlyD3D12 { return "its files show DirectX 12 only" }
        if fromFiles(analysis, d3dMetal: true) == way.graphics {
            return analysis.apis.isEmpty ? "its files show nothing, and D3DMetal runs DirectX 11 and 12"
                : "its files show DirectX 12 and no switch to hold it to 11 is known"
        }
        if !way.arguments.isEmpty { return "\(analysis.engine.rawValue) is held to DirectX 11" }
        return "the usual first way for \(analysis.summary.isEmpty ? "this game" : analysis.summary)"
    }
}
