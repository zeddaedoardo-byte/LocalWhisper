import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        StaleProcessSweeper.sweep(processNames: ["whisper-server", "llama-server"])
        installSignalHandlers()
        atexit {
            WhisperServerWorker.terminateAllRunningServers()
            LLMServerWorker.terminateAllRunningServers()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        WhisperServerWorker.terminateAllRunningServers()
    }

    private func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { signal in
            WhisperServerWorker.terminateAllRunningServers()
            LLMServerWorker.terminateAllRunningServers()
            Darwin.signal(signal, SIG_DFL)
            raise(signal)
        }
        signal(SIGTERM, handler)
        signal(SIGINT, handler)
        signal(SIGHUP, handler)
    }
}
