import AppKit
@main struct IDMMac {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        delegate.start()
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: MainWindowController?
    func applicationDidFinishLaunching(_ notification: Notification) { start() }
    func start() {
        guard controller == nil else { return }
        do { let args = ProcessInfo.processInfo.arguments
            let smoke = args.firstIndex(of:"--smoke-test")
            let storage = smoke.map { _ in FileManager.default.temporaryDirectory.appendingPathComponent("idm-ui-smoke-\(UUID())") }
            controller = try MainWindowController(storageDirectory:storage); controller?.showWindow(nil); NSApp.activate(ignoringOtherApps:true)
            if let smoke, args.count > smoke + 1 {
                let output = URL(fileURLWithPath:args[smoke+1])
                DispatchQueue.main.asyncAfter(deadline:.now()+1) { [weak self] in
                    do {
                        let result = try self?.controller?.smokeCheck(output:output) ?? [:]
                        try JSONSerialization.data(withJSONObject:result,options:.prettyPrinted).write(to:output)
                        if let storage { try FileManager.default.removeItem(at:storage) }
                        NSApp.terminate(nil)
                    } catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8)); exit(1) }
                }
            } }
        catch { let alert = NSAlert(error: error); alert.runModal(); NSApp.terminate(nil) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller?.stopAll(); return .terminateNow
    }
}
