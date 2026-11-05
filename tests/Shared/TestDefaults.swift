// UserDefaults for a test program, in a folder beside it that its run.sh removes along with it: cfprefsd
// keeps every named domain in the real ~/Library/Preferences whatever HOME says, and a domain removed
// there still leaves its file behind. A domain named by an absolute path is a file at that path instead.
// Compiled into the tests that keep settings: swiftc … tests/Shared/TestDefaults.swift tests/<Test>/main.swift
import Foundation
import ObjectiveC

enum TestDefaults {
    static let folder = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("defaults", isDirectory: true)

    /// A domain of its own, empty in every run.
    static func domain(_ name: String) -> String { folder.appendingPathComponent(name).path }

    static func suite(_ name: String) -> UserDefaults { UserDefaults(suiteName: domain(name))! }

    /// Nightforge keeps its settings in UserDefaults.standard, for a test program a domain named after it in
    /// ~/Library/Preferences. From here on it's `suite("standard")`: first thing in main().
    static func useWorkFolder() {
        let standard = suite("standard")
        let getter: @convention(block) (AnyObject) -> UserDefaults = { _ in standard }
        method_setImplementation(class_getClassMethod(UserDefaults.self, #selector(getter: UserDefaults.standard))!,
                                 imp_implementationWithBlock(getter))
    }
}
