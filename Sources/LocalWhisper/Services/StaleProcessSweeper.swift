import Foundation
import Darwin

// Kills leftover child processes from previous app sessions that survived a
// non-graceful shutdown (crash, SIGKILL, force-quit, panic). Each worker keeps
// an in-memory PID registry, but that registry is lost if the parent dies
// before its signal/atexit handlers run — the child is then reparented to
// launchd and lingers until the next reboot, occasionally double-binding the
// loopback port alongside the freshly spawned server.
enum StaleProcessSweeper {
    // Run at app launch BEFORE any worker spawns its server. Calling it later
    // would also kill the just-spawned legitimate child.
    static func sweep(processNames: [String]) {
        let self_pid = getpid()
        for name in processNames {
            for pid in findPIDs(matching: name) where pid != self_pid {
                kill(pid, SIGTERM)
            }
        }
        usleep(500_000)
        for name in processNames {
            for pid in findPIDs(matching: name) where pid != self_pid {
                kill(pid, SIGKILL)
            }
        }
    }

    private static func findPIDs(matching name: String) -> [pid_t] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", name]
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return []
        }
        task.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: { $0.isNewline })
            .compactMap { pid_t($0) }
    }
}
