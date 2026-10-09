import AppKit
import IDMCore
import Darwin
@MainActor final class BrowserURLDelivery {
    private var pending:[URL] = []
    private var handler:((URL) -> Void)?
    func receive(_ urls:[URL]) {
        if let handler { urls.forEach(handler) }
        else { pending.append(contentsOf:urls.prefix(max(0,200-pending.count))) }
    }
    func activate(_ handler:@escaping (URL) -> Void) {
        self.handler = handler
        let queued = pending; pending.removeAll()
        queued.forEach(handler)
    }
    static func startupCheck() throws {
        let delivery = BrowserURLDelivery()
        let early = URL(string:"idm-mac://download?early")!, late = URL(string:"idm-mac://download?late")!
        var received:[URL] = []
        delivery.receive([early]); delivery.activate { received.append($0) }; delivery.receive([late])
        guard received == [early,late] else { throw DownloadError.storage("Startup URL delivery lost a handoff") }
    }
}
@main struct IDMMac {
    @MainActor static func main() {
        if ProcessInfo.processInfo.arguments.contains("--register-browsers") {
            do { try BrowserRegistration.install(app:Bundle.main.bundleURL); print("Registered native browser hosts"); return }
            catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8)); exit(1) }
        }
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
    private var qaTermination: DispatchSourceSignal?
    private let browserURLs = BrowserURLDelivery()
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
                if let qa {
                    controller.browserQAReportURL = qa.appendingPathComponent("jobs.json")
                    Darwin.signal(SIGTERM,SIG_IGN)
                    let source = DispatchSource.makeSignalSource(signal:SIGTERM,queue:.main)
                    source.setEventHandler { Task { @MainActor in NSApp.terminate(nil) } }; source.resume(); qaTermination = source
                }
                let bridge = BrowserIntegrationCoordinator(controller:controller,configurationURL:qa?.appendingPathComponent("browser-bridge.json") ?? BrowserBridgeConfiguration.defaultURL,qaDirectory:qa)
                controller.browserIntegration = bridge; try bridge.start()
                browserURLs.activate { [weak bridge] url in bridge?.handleURL(url) }
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
                        try BrowserURLDelivery.startupCheck()
                        var result = try self?.controller?.smokeCheck(output:output) ?? [:]
                        result["startupURLDelivery"] = true
                        try JSONSerialization.data(withJSONObject:result,options:.prettyPrinted).write(to:output)
                        if let storage { try FileManager.default.removeItem(at:storage) }
                        NSApp.terminate(nil)
                    } catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8)); exit(1) }
                }
            } }
        catch { let alert = NSAlert(error: error); alert.runModal(); NSApp.terminate(nil) }
    }
    func application(_ application:NSApplication, open urls:[URL]) { browserURLs.receive(urls) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller?.prepareForTermination(); return .terminateNow
    }
}
