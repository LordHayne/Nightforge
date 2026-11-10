import Foundation

/// What a Windows minidump says about a crash: the exception, the module it happened in, and the
/// modules whose code the crashed thread was coming from. Unreal and Unity write one beside their crash
/// report (UE4Minidump.dmp, crash.dmp). Read as a file – nothing is attached to and nothing runs. It
/// Takes Two, 10.11.2026: eight reports said only "access violation reading 0"; their dumps all said
/// PhysXUpdateLoader64 → nvapi64 → 0, which named the fix.
struct CrashDump: Equatable {
    struct Frame: Equatable {
        /// The module's file name, lower-cased ("nvapi64.dll").
        var module: String
        var offset: UInt64
    }

    /// 0xC0000005 access violation, 0xC000001D illegal instruction, …
    var code: UInt32
    var address: UInt64
    /// Where `address` lies; nil for a jump to nowhere (address 0) or into memory no module owns.
    var module: Frame?
    /// Addresses on the crashed thread's stack that point into modules, nearest first: mostly return
    /// addresses, so the callers – with a stale one now and then, as no unwinding is done.
    var stack: [Frame]
    /// Every loaded module's file name, lower-cased.
    var modules: [String]

    static let accessViolation: UInt32 = 0xC000_0005
    static let illegalInstruction: UInt32 = 0xC000_001D

    /// The modules the crash came through, nearest first, each once in a row: where it happened, then
    /// the stack's.
    var chain: [String] {
        var names: [String] = []
        for name in ([module].compactMap { $0 } + stack).map(\.module) where names.last != name { names.append(name) }
        return names
    }

    /// "0xc0000005 at 0x0, from nvapi64.dll+0x1120 ← physxupdateloader64.dll+0x113c ← ntdll.dll+0x53158"
    var summary: String {
        let hex = { (value: UInt64) in "0x" + String(value, radix: 16) }
        var frames = ([module].compactMap { $0 } + stack)
        var seen: [Frame] = []
        for frame in frames where seen.last?.module != frame.module { seen.append(frame) }
        frames = Array(seen.prefix(4))
        let path = frames.map { "\($0.module)+\(hex($0.offset))" }.joined(separator: " ← ")
        return "\(hex(UInt64(code))) at \(hex(address))" + (path.isEmpty ? "" : (module == nil ? ", from " : ", in ") + path)
    }

    /// Dumps beyond this are full-memory ones: not read.
    static let sizeLimit = 64 << 20

    static func read(_ file: URL) -> CrashDump? {
        guard let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= sizeLimit,
              let data = try? Data(contentsOf: file, options: .mappedIfSafe)
        else { return nil }
        return read(data)
    }

    static func read(_ data: Data) -> CrashDump? {
        let bytes = Bytes(data)
        // MINIDUMP_HEADER: "MDMP", version, stream count, directory.
        guard bytes.u32(0) == 0x504D_444D, let count = bytes.u32(8), let directory = bytes.u32(12), count <= 4096 else { return nil }
        var streams: [UInt32: Int] = [:]
        for index in 0..<Int(count) {
            let at = Int(directory) + index * 12
            guard let type = bytes.u32(at), let place = bytes.u32(at + 8) else { return nil }
            if streams[type] == nil { streams[type] = Int(place) }
        }
        // Exception stream (6): thread, record (code at +8, address at +24), the thread's context.
        guard let exception = streams[6], let thread = bytes.u32(exception), let code = bytes.u32(exception + 8),
              let address = bytes.u64(exception + 24), let context = bytes.u32(exception + 8 + 152 + 4)
        else { return nil }

        // Module list (4): 108 bytes each – base, size, and the name as a length and UTF-16 text.
        var modules: [(base: UInt64, size: UInt64, name: String)] = []
        if let list = streams[4], let moduleCount = bytes.u32(list), moduleCount <= 8192 {
            for index in 0..<Int(moduleCount) {
                let at = list + 4 + index * 108
                guard let base = bytes.u64(at), let size = bytes.u32(at + 8), let nameAt = bytes.u32(at + 20),
                      let length = bytes.u32(Int(nameAt)), length <= 2048,
                      let text = bytes.slice(Int(nameAt) + 4, Int(length))
                else { continue }
                let path = String(decoding: stride(from: 0, to: text.count - 1, by: 2).map {
                    UInt16(text[text.startIndex + $0]) | UInt16(text[text.startIndex + $0 + 1]) << 8
                }, as: UTF16.self)
                let name = path.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) ?? path
                modules.append((base, UInt64(size), name.lowercased()))
            }
        }
        func frame(_ value: UInt64, base allowed: Bool) -> Frame? {
            guard let module = modules.first(where: { value >= $0.base && value - $0.base < $0.size }),
                  allowed || value != module.base
            else { return nil }
            return Frame(module: module.name, offset: value - module.base)
        }

        // The stack pointer from the context – x64's at 0x98, x86's at 0xC4 (system info, stream 7: 9 or 0) –
        // and the thread's saved stack from the thread list (3): 48 bytes each, the stack's start at +24.
        let architecture = streams[7].flatMap { bytes.u16($0) } ?? 9
        let wide = architecture != 0
        let pointer = wide ? bytes.u64(Int(context) + 0x98) : bytes.u32(Int(context) + 0xC4).map(UInt64.init)
        var stack: [Frame] = []
        if let pointer, let list = streams[3], let threadCount = bytes.u32(list), threadCount <= 8192 {
            for index in 0..<Int(threadCount) {
                let at = list + 4 + index * 48
                guard bytes.u32(at) == thread, let start = bytes.u64(at + 24), let length = bytes.u32(at + 32),
                      let place = bytes.u32(at + 36)
                else { continue }
                let width = wide ? 8 : 4
                let first = pointer >= start ? Int(min(pointer - start, UInt64(length))) : 0
                var position = first
                while position + width <= Int(length), position < first + stackDepth, stack.count < 16 {
                    let value = wide ? bytes.u64(Int(place) + position) : bytes.u32(Int(place) + position).map(UInt64.init)
                    // A module's own base on the stack is a handle, not a return address.
                    if let value, let found = frame(value, base: false) { stack.append(found) }
                    position += width
                }
                break
            }
        }
        return CrashDump(code: code, address: address, module: frame(address, base: true), stack: stack,
                         modules: modules.map(\.name))
    }

    /// How far up the stack the look goes, in bytes.
    private static let stackDepth = 0x800

    /// Little-endian reads that answer nil past the end.
    private struct Bytes {
        let data: Data
        init(_ data: Data) { self.data = data }

        func slice(_ at: Int, _ count: Int) -> Data? {
            guard at >= 0, count >= 0, at <= data.count - count else { return nil }
            return data.subdata(in: data.startIndex + at..<data.startIndex + at + count)
        }
        func u16(_ at: Int) -> UInt16? {
            slice(at, 2).map { UInt16($0[$0.startIndex]) | UInt16($0[$0.startIndex + 1]) << 8 }
        }
        func u32(_ at: Int) -> UInt32? {
            slice(at, 4).map { bytes in (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[bytes.startIndex + $1]) << (8 * UInt32($1)) } }
        }
        func u64(_ at: Int) -> UInt64? {
            slice(at, 8).map { bytes in (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[bytes.startIndex + $1]) << (8 * UInt64($1)) } }
        }
    }
}
