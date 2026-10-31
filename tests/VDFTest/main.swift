// Checks VDF, the reader for Steam's KeyValues files (appmanifest_*.acf, libraryfolders.vdf,
// localconfig.vdf): case, escapes, comments, broken files, and that libraryfolders.vdf comes back
// as Steam wrote it: tests/VDFTest/run.sh
import Foundation

@main
struct VDFTest {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() throws {
        // An appmanifest as Steam writes it: keys in any case, read in any case.
        let manifest = """
        "AppState"
        {
        \t"appid"\t\t"1623730"
        \t"Name"\t\t"Palworld"
        \t"StateFlags"\t\t"4"
        \t"InstalledDepots"
        \t{
        \t\t"1623731"
        \t\t{
        \t\t\t"manifest"\t\t"5126406069316542813"
        \t\t}
        \t}
        }
        """
        let state = VDF.parse(manifest)?["appstate"]
        check(state?["APPID"]?.string == "1623730" && state?["name"]?.string == "Palworld", "keys are read in any case")
        check(state?["installeddepots"]?["1623731"]?["manifest"]?.string == "5126406069316542813", "nested objects")
        check(state?["installeddepots"]?.object?.count == 1 && state?["installeddepots"]?.string == nil, "an object is no string")
        check(state?["name"]?.object == nil && state?["name"]?["x"] == nil, "a string has no keys")
        check(state?["buildid"] == nil, "a missing key is nil")

        // Escapes, comments, platform conditionals and unquoted words.
        let odd = VDF.parse(#"""
        // written by hand
        "path"    "C:\\Program Files (x86)\\Steam"
        "quote"   "say \"hi\""
        "lines"   "a\nb\tc"
        "osx"     "1" [$OSX]
        bare      word
        "after"   "comment" // trailing
        """#)
        check(odd?["path"]?.string == #"C:\Program Files (x86)\Steam"#, "backslashes: \(odd?["path"]?.string ?? "nil")")
        check(odd?["quote"]?.string == #"say "hi""#, "quotes inside a value")
        check(odd?["lines"]?.string == "a\nb\tc", "\\n and \\t")
        check(odd?["osx"]?.string == "1" && odd?["bare"]?.string == "word", "conditionals skipped, unquoted words read")
        check(odd?["after"]?.string == "comment", "a comment after a value")
        check(VDF.parse(#""name" "Ünïcødé – ゲーム 🎮""#)?["name"]?.string == "Ünïcødé – ゲーム 🎮", "any Unicode in a value")
        check(VDF.parse(#""a" "1" "A" "2""#)?["a"]?.string == "2", "the same key twice: the last one counts")

        // What a broken or cut-off file gives.
        check(VDF.parse("")?.object?.isEmpty == true, "an empty file is an empty object")
        check(VDF.parse("{ \"a\" \"1\" }") == nil, "a brace with no key is no KeyValues file")
        check(VDF.parse(#""a" { { }"#) == nil, "a brace where a key belongs")
        check(VDF.parse(#""a" "1" "b""#)?["a"]?.string == "1", "a key cut off before its value is dropped")
        check(VDF.parse(#""a" { "b" "1""#)?["a"]?["b"]?.string == "1", "a file cut off inside an object keeps what it read")
        check(VDF.parse(#""a" "1" } "b" "2""#)?["b"] == nil, "reading stops at a stray closing brace")
        check(VDF.parse(#""a" }"#)?.object?.isEmpty == true, "a brace where a value belongs ends the object")
        check(VDF.parse(#""a" "unterminated"#)?["a"]?.string == "unterminated", "a value cut off before its quote")
        check(VDF.parse(#""a" "ends in \"#)?["a"]?.string == "ends in \\", "a lone backslash at the very end")

        // From a file.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nightforge-vdf-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("appmanifest_1.acf")
        try Data(manifest.utf8).write(to: file)
        check(VDF.parse(contentsOf: file)?["appstate"]?["name"]?.string == "Palworld", "read from a file")
        check(VDF.parse(contentsOf: folder.appendingPathComponent("missing.acf")) == nil, "a missing file is nil")
        try Data([0x22, 0x6E, 0x22, 0x20, 0x22, 0xFF, 0xFE, 0x22]).write(to: file)  // "n" "<not UTF-8>"
        check(VDF.parse(contentsOf: file)?["n"]?.string?.isEmpty == false, "bytes that aren't UTF-8 don't stop the file")
        try FileManager.default.removeItem(at: folder)

        // libraryfolders.vdf as written: order and case stay, and it is written back the way Steam lays it out.
        let folders = """
        "libraryfolders"
        {
        \t"0"
        \t{
        \t\t"path"\t\t"C:\\\\Program Files (x86)\\\\Steam"
        \t\t"label"\t\t""
        \t\t"apps"
        \t\t{
        \t\t\t"228980"\t\t"1069733"
        \t\t}
        \t}
        \t"1"
        \t{
        \t\t"Path"\t\t"/Volumes/T7/Steam \\"Games\\""
        \t}
        }

        """
        guard let nodes = VDF.nodes(folders) else {
            check(false, "libraryfolders.vdf reads as nodes")
            return finish()
        }
        check(nodes.count == 1 && nodes[0].key == "libraryfolders", "one top-level key")
        let libraries = nodes[0].children
        check(libraries.map(\.key) == ["0", "1"], "libraries in their order")
        check(libraries[1]["path"]?.string == #"/Volumes/T7/Steam "Games""# && libraries[1].children[0].key == "Path",
              "a key is found in any case and keeps its own")
        check(libraries[0]["apps"]?["228980"]?.string == "1069733", "nested nodes")
        check(libraries[0]["label"]?.string == "", "an empty value")
        check(libraries[0]["missing"] == nil && libraries[0]["path"]?["x"] == nil && libraries[0]["apps"]?.string == nil,
              "what isn't there, isn't")
        check(libraries[0]["path"]?.children == [], "a string has no children")
        check(VDF.text(nodes) == folders, "written back exactly as Steam wrote it:\n\(VDF.text(nodes))")
        check(VDF.nodes(VDF.text(nodes)) == nodes, "and reads the same again")

        // Changing it: a new library, written in Steam's layout with its escapes.
        var changed = nodes
        changed[0].children.append(VDFNode(key: "2", value: .object([VDFNode(key: "path", value: .string(#"D:\Games"#))])))
        let written = VDF.text(changed)
        check(written.hasSuffix("\t\"2\"\n\t{\n\t\t\"path\"\t\t\"D:\\\\Games\"\n\t}\n}\n"), "an added library: \(written)")
        check(VDF.nodes(written)?[0].children.last?["path"]?.string == #"D:\Games"#, "and it reads back")
        var string = VDFNode(key: "k", value: .string("v"))
        string.children = [VDFNode(key: "a", value: .string("b"))]
        check(string["a"]?.string == "b", "setting children makes a string an object")

        // A file that can't be written back safely is no file at all.
        check(VDF.nodes("")?.isEmpty == true, "an empty file has no nodes")
        check(VDF.nodes(#""a" "1" }"#) == nil, "a stray closing brace at the top")
        check(VDF.nodes(#"{ "a" "1" }"#) == nil, "a brace with no key")
        check(VDF.nodes(#""a" { "b" "1""#) == nil, "an object that never closes")
        check(VDF.nodes(#""a""#) == nil, "a key with no value")
        check(VDF.nodes(#""a" }"#) == nil, "a brace where a value belongs")
        check(VDF.nodes(#""a" { { } }"#) == nil, "a nested brace with no key")
        check(VDF.nodes(#""a" "1" // note"#) == [VDFNode(key: "a", value: .string("1"))], "comments aren't kept, but don't hurt")

        finish()
    }

    static func finish() {
        print(failures == 0 ? "✓ VDF" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
