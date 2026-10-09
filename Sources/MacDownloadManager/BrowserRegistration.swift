import Foundation
import DownloadCore

enum BrowserRegistration {
    static func install(app:URL) throws {
        let host = app.appendingPathComponent("Contents/MacOS/MacDownloadManagerHost")
        guard FileManager.default.isExecutableFile(atPath:host.path) else { throw DownloadError.storage("Package the application before registering browsers.") }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let chromium = ["Google/Chrome", "Google/Chrome Beta", "Google/Chrome Dev", "Google/Chrome Canary", "Chromium", "Microsoft Edge", "Microsoft Edge Beta", "Microsoft Edge Dev", "Microsoft Edge Canary", "BraveSoftware/Brave-Browser", "Vivaldi", "com.operasoftware.Opera", "com.operasoftware.OperaGX", "Arc/User Data"]
        for path in chromium + ["Mozilla"] {
            let directory = root.appendingPathComponent(path).appendingPathComponent("NativeMessagingHosts")
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            var manifest:[String:Any] = ["name":"local.haseebheaven.macdownloadmanager","description":"MacDownloadManager native browser integration","path":host.path,"type":"stdio"]
            if path == "Mozilla" { manifest["allowed_extensions"] = ["macdownloadmanager@haseeb-heaven"] }
            else { manifest["allowed_origins"] = ["chrome-extension://amdlggemepjploaameacboladklhlndk/"] }
            let data = try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys])
            try data.write(to:directory.appendingPathComponent("local.haseebheaven.macdownloadmanager.json"),options:.atomic)
        }
    }
}
