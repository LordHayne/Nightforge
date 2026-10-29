// Checks Steam's update as Nightforge fetches it ahead (SteamPackages, SteamPrefetch): the packages
// Valve's two client manifests name (fetched 29.10.2026) against the ones Steam's bootstrapper
// asked for in the live run the same evening ("Package file … missing or incorrect size",
// tests/SteamBootstrapTest/run5-2026-10-29-bootstrap.txt), a manifest that names anything but a
// file, and how finished downloads go into Steam's package folder: tests/SteamPackagesTest/run.sh
import Foundation

@main
struct SteamPackagesTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    static let win32 = (try? String(contentsOf: folder.appendingPathComponent("steam_client_win32-2026-10-29.vdf"), encoding: .utf8)) ?? ""
    static let win64 = (try? String(contentsOf: folder.appendingPathComponent("steam_client_win64-2026-10-29.vdf"), encoding: .utf8)) ?? ""
    static let run5 = (try? String(contentsOf: folder.deletingLastPathComponent()
        .appendingPathComponent("SteamBootstrapTest/run5-2026-10-29-bootstrap.txt"), encoding: .utf8)) ?? ""

    static func main() {
        check(!win32.isEmpty && !win64.isEmpty && !run5.isEmpty, "the manifests and the log are there")
        asSteamAsked()
        notAFile()
        placing()
        detail()
        print(failures == 0 ? "✓ SteamPackages" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// The names Steam asked for in each of its two update steps, in the live run.
    static func asked() -> [[String]] {
        var steps: [[String]] = []
        for line in run5.split(whereSeparator: \.isNewline) {
            if line.contains("Downloaded new manifest") { steps.append([]) }
            guard let range = line.range(of: "Package file "), let end = line.range(of: " missing or incorrect size") else { continue }
            steps[steps.count - 1].append(String(line[range.upperBound..<end.lowerBound]))
        }
        return steps.filter { !$0.isEmpty }
    }

    /// The 32-bit step asked for exactly what its manifest names; the 64-bit step for all of its
    /// own but the four the 32-bit step had brought already (the same files).
    static func asSteamAsked() {
        let steps = asked()
        check(steps.count == 2, "two steps asked for packages: \(steps.count)")
        guard steps.count == 2 else { return }
        let first = SteamPackages.packages(manifest: win32)
        let second = SteamPackages.packages(manifest: win64)
        check(Set(first.map(\.name)) == Set(steps[0]), "win32: as asked – \(Set(first.map(\.name)).symmetricDifference(steps[0]))")
        check(first.count == 19, "win32: 19 packages, \(first.count)")
        let kept = Set(second.map(\.name)).intersection(first.map(\.name))
        check(Set(second.map(\.name)) == Set(steps[1]).union(kept), "win64: as asked, plus what win32 brought – \(Set(second.map(\.name)).symmetricDifference(Set(steps[1]).union(kept)))")
        check(kept.count == 4 && steps[1].count == 14, "win64: 14 asked for, 4 already there")
        check(SteamPackages.packages(manifest: crlf(win32)) == first, "with Windows line ends too")

        for package in first + second {
            // "….zip.vz.<sha1>_<size>": the size Steam checks is in the name.
            if package.name.contains(".zip.vz.") {
                check(package.name.hasSuffix("_\(package.size)"), "\(package.name): its size")
            }
            check(package.sha256?.count == 64, "\(package.name): a SHA-256")
        }
        let cef = first.first { $0.name.hasPrefix("bins_cef_win32") }
        check(cef?.name.hasPrefix("bins_cef_win32_win7-64.zip.vz.") == true && cef?.size == 105_972_111, "the 64-bit Windows variant: \(cef?.name ?? "none")")
        let steamrow = first.first { $0.name.hasPrefix("steam_win32") }
        check(steamrow?.name.hasPrefix("steam_win32_steamrow.zip.vz.") == true, "the global realm's: \(steamrow?.name ?? "none")")
        let movies = first.first { $0.name.hasPrefix("steamui_websrc_movies_all") }
        check(movies == SteamPackages.Package(name: "steamui_websrc_movies_all.zip.f556f4b9c7e087e07c0fef2da2b1d9f27f734cff", size: 9_210_097,
              sha256: movies?.sha256), "no compressed file: the zip itself, its size from the manifest")
        check(SteamPackages.Client.win32.manifest.absoluteString == "https://cdn.steamstatic.com/client/steam_client_win32"
              && SteamPackages.Client.win64.manifest.absoluteString == "https://client-update.steamstatic.com/steam_client_win64",
              "the manifests where the bootstrappers fetch them")
    }

    /// Only plain file names come out: nothing that leads out of the package folder.
    static func notAFile() {
        let odd = """
            "win64"
            {
            \t"version"\t\t"1"
            \t"up"\t{ "file" "../steam.exe" "size" "10" }
            \t"slash"\t{ "file" "bin/x.zip" "size" "10" }
            \t"hidden"\t{ "file" ".x.zip" "size" "10" }
            \t"nosize"\t{ "file" "a.zip" }
            \t"zero"\t{ "file" "b.zip" "size" "0" }
            \t"fine"\t{ "file" "c.zip" "size" "10" }
            }
            """
        check(SteamPackages.packages(manifest: odd).map(\.name) == ["c.zip"], "only the plain file: \(SteamPackages.packages(manifest: odd).map(\.name))")
        check(SteamPackages.packages(manifest: "").isEmpty && SteamPackages.packages(manifest: "<html>").isEmpty, "no manifest: nothing")
    }

    /// Finished downloads go in as hard links, never over a file that's there; half-done ones don't.
    static func placing() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("steam-packages-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let staged = root.appendingPathComponent("staged")
        let package = root.appendingPathComponent("Steam/package")
        let prefetch = SteamPrefetch(folder: staged)
        check(prefetch.place(.win32, into: package) == 0 && !fm.fileExists(atPath: package.path), "nothing fetched: nothing placed")
        let progress = prefetch.progress(.win32)
        check(progress.done == 0 && progress.total == 0 && !progress.over, "nothing started: no progress")

        let win32 = staged.appendingPathComponent("win32")
        try? fm.createDirectory(at: win32, withIntermediateDirectories: true)
        try? fm.createDirectory(at: package, withIntermediateDirectories: true)
        try? Data("a".utf8).write(to: win32.appendingPathComponent("a.zip.vz.1_1"))
        try? Data("bb".utf8).write(to: win32.appendingPathComponent("b.zip.vz.2_2"))
        try? Data("c".utf8).write(to: win32.appendingPathComponent("c.zip.vz.3_1.part"))
        try? Data("Steam's".utf8).write(to: package.appendingPathComponent("b.zip.vz.2_2"))
        check(prefetch.place(.win32, into: package) == 1, "one placed")
        func inode(_ url: URL) -> Int? { (try? fm.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int) ?? nil }
        let placed = package.appendingPathComponent("a.zip.vz.1_1")
        check(inode(placed) != nil && inode(placed) == inode(win32.appendingPathComponent("a.zip.vz.1_1")), "a hard link, nothing copied")
        check((try? String(contentsOf: package.appendingPathComponent("b.zip.vz.2_2"), encoding: .utf8)) == "Steam's", "Steam's own file stays")
        check(!fm.fileExists(atPath: package.appendingPathComponent("c.zip.vz.3_1.part").path)
              && !fm.fileExists(atPath: package.appendingPathComponent("c.zip.vz.3_1").path), "a half-done download stays out")
        check(prefetch.place(.win64, into: package) == 0, "no win64 fetched: nothing")

        prefetch.discard()
        check(!fm.fileExists(atPath: staged.path), "discarded: the downloads are gone")
        check(fm.fileExists(atPath: placed.path), "what went into Steam's folder stays")
    }

    /// The line under "Installing Steam" while the fetched update is still coming down.
    static func detail() {
        let line = SetupDetail.steamUpdate(done: 120_000_000, total: 247_000_000, bytesPerSecond: 20_000_000)
        check(line == L10n.t("Downloading Steam's update: %@", SetupDetail.transfer(done: 120_000_000, total: 247_000_000, bytesPerSecond: 20_000_000)),
              "with how far and how fast: \(line)")
    }

    static func crlf(_ text: String) -> String { text.replacingOccurrences(of: "\n", with: "\r\n") }
}
