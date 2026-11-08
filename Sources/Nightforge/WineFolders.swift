/// The folders of a Wine install that depend on the processor it's built for: <wine>/lib/wine/<folder>,
/// and the same names in the graphics, D3DMetal and engine fix downloads. In one place so that an engine
/// for another processor is one change here, not one per path (docs/ENTWURF-ARM64.md).
enum WineFolders {
    /// The Unix halves of Wine's modules.
    static let unix = "x86_64-unix"
    /// 64-bit Windows modules.
    static let windows = "x86_64-windows"
    /// 32-bit Windows modules.
    static let windows32 = "i386-windows"
}
