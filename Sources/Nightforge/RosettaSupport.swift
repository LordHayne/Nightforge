import Foundation

/// Windows games need Rosetta, because Wine is x86_64. Apple keeps it for everything through macOS 27;
/// after that only for some older games, and doesn't say which (docs/ENTWURF-ARM64.md). So past macOS 27
/// a Mac without it isn't one to offer the install on: Nightforge says so plainly, and says nothing about
/// what comes later.
enum RosettaSupport {
    static let lastMajorWithRosetta = 27

    /// Past macOS 27 and x86_64 code doesn't run. Up to macOS 27 `translates` isn't even asked: a Rosetta
    /// missing there is one Apple still installs (SetupModel's `.needsRosetta`).
    static func isGone(macOSMajor: Int, translates: () -> Bool) -> Bool {
        macOSMajor > lastMajorWithRosetta && !translates()
    }

    static var isGoneHere: Bool {
        isGone(macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) { Engine.isRosettaInstalled }
    }

    static var notice: String {
        L10n.t("Windows games can't run on this version of macOS: Rosetta, which they need, isn't available here.")
    }
}
