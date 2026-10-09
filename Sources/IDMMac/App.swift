import AppKit
import IDMCore
@main struct IDMMac {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.appearance = NSAppearance(named:.aqua)
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
            let e2e = args.firstIndex(of:"--e2e-test")
            let qa = args.firstIndex(of:"--browser-qa").flatMap { args.count > $0+1 ? URL(fileURLWithPath:args[$0+1],isDirectory:true) : nil }
            let storage = qa ?? (smoke ?? e2e).map { _ in FileManager.default.temporaryDirectory.appendingPathComponent("idm-ui-smoke-\(UUID())") }
            controller = try MainWindowController(storageDirectory:storage); controller?.showWindow(nil); NSApp.activate(ignoringOtherApps:true)
            if smoke == nil && e2e == nil, let controller {
                if let qa { controller.browserQAReportURL = qa.appendingPathComponent("jobs.json") }
                let bridge = BrowserIntegrationCoordinator(controller:controller,configurationURL:qa?.appendingPathComponent("browser-bridge.json") ?? BrowserBridgeConfiguration.defaultURL,qaDirectory:qa)
                controller.browserIntegration = bridge; try bridge.start()
            }
            if let e2e,args.count > e2e + 2,let base = URL(string:args[e2e+1]) {
                let output = URL(fileURLWithPath:args[e2e+2])
                Task { @MainActor [weak self] in
                    do {
                        let result = try await self?.controller?.endToEndCheck(base:base,output:output) ?? [:]
                        try JSONSerialization.data(withJSONObject:result,options:.prettyPrinted).write(to:output)
                        self?.controller?.prepareForTermination();self?.controller = nil
                        if let storage { try FileManager.default.removeItem(at:storage) }
                        NSApp.terminate(nil)
                    } catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8));exit(1) }
                }
            }
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
    func application(_ application:NSApplication, open urls:[URL]) { for url in urls { controller?.browserIntegration?.handleURL(url) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller?.prepareForTermination(); return .terminateNow
    }
}
