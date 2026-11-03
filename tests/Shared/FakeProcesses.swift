// A process list for a test program to hand to ProcessList: no `ps -ax` is run, so a `ps` that hangs on the Mac
// (3.11.2026: after a Wine process was stopped in the middle of a debugger, every `ps -ax` hung for good) doesn't
// stop a series. Where a test needs real processes – ones it started itself – their rows are read one pid at a time
// (libproc and the process's own arguments), never by listing everybody.
// Compiled into the tests that look at processes: swiftc … tests/Shared/FakeProcesses.swift tests/<Test>/main.swift
import Foundation

enum FakeProcesses {
    struct Row {
        var pid: pid_t
        var parent: pid_t = 1
        var cpu = 0.0
        var command: String
    }

    /// No process at all.
    static func installEmpty() { ProcessList.source = { _ in "" } }

    /// Exactly these rows, asked for each time (a game that has ended is left out by the caller).
    static func install(_ rows: @escaping () -> [Row]) {
        ProcessList.source = { columns in render(rows(), columns: columns) }
    }

    static func uninstall() { ProcessList.source = nil }

    /// `ps -axo <columns>` for the rows: pid=, ppid=, pcpu=, command= in the order asked.
    static func render(_ rows: [Row], columns: String) -> String {
        let names = columns.split(separator: ",").map(String.init)
        return rows.map { row in
            names.map { name -> String in
                switch name {
                case "pid=": return String(row.pid)
                case "ppid=": return String(row.parent)
                case "pcpu=": return String(format: "%.1f", row.cpu)
                default: return row.command
                }
            }.joined(separator: " ")
        }.joined(separator: "\n") + (rows.isEmpty ? "" : "\n")
    }

    /// The rows of these processes, and, with `descendants`, of everything they started – each asked for by its own pid.
    /// A pid that is gone is left out.
    static func rows(of pids: [pid_t], descendants: Bool = false) -> [Row] {
        var seen = Set<pid_t>()
        var queue = pids
        var rows: [Row] = []
        while let pid = queue.first {
            queue.removeFirst()
            guard seen.insert(pid).inserted, let row = row(of: pid) else { continue }
            rows.append(row)
            if descendants { queue += children(of: pid) }
        }
        return rows
    }

    static func row(of pid: pid_t) -> Row? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_status != UInt32(SZOMB),
              let command = commandLine(of: pid)
        else { return nil }
        return Row(pid: pid, parent: pid_t(info.pbi_ppid), command: command)
    }

    static func children(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 256)
        let count = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        return count > 0 ? Array(buffer.prefix(Int(count))) : []
    }

    /// What `ps` shows as the command: the arguments, from KERN_PROCARGS2 (argc, the program's path, padding, the arguments).
    static func commandLine(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0, size > 4 else { return nil }
        let argc = bytes.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        var index = 4
        while index < size, bytes[index] != 0 { index += 1 }       // the program's path
        while index < size, bytes[index] == 0 { index += 1 }       // its padding
        var words: [String] = []
        while words.count < argc, index < size {
            var end = index
            while end < size, bytes[end] != 0 { end += 1 }
            words.append(String(decoding: bytes[index..<end], as: UTF8.self))
            index = end + 1
        }
        return words.joined(separator: " ")
    }
}
