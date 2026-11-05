// The one check that asks the real `ps -ax`: what ProcessList, Engine.processTable and GameProcesses.table get
// from it, with this program in the list. The other series hand ProcessList a list of their own
// (tests/Shared/FakeProcesses.swift). Run by the CI; on a Mac only when asked: tests/ProcessListLive/run.sh
import Foundation

@main
struct ProcessListLive {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("✗ " + message)
        }
    }

    static func main() {
        let me = getpid()
        guard let text = ProcessList.ps("pid=,command=") else {
            print("✗ ps -ax didn't answer within \(ProcessList.timeout) s – on this Mac it may be hanging")
            exit(1)
        }
        check(text.split(separator: "\n").contains { $0.split(separator: " ").first.flatMap { pid_t($0) } == me }, "ps -ax lists this program (\(me))")
        check(Engine.processTable().contains { $0.pid == me }, "Engine.processTable has this program in it")
        check(GameProcesses.table().contains { $0.pid == me }, "GameProcesses.table has this program in it")
        check(ProcessList.ps("pid=,ppid=,command=")?.contains("\(me) ") == true, "the columns come as asked")
        print(failures == 0 ? "✓ ProcessList (the real ps)" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
