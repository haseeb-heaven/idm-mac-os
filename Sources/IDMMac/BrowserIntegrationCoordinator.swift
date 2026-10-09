import AppKit
import IDMCore

@MainActor final class BrowserIntegrationCoordinator {
    private weak var controller: MainWindowController?
    private let configurationURL: URL
    private let qaDirectory: URL?
    private var server: BrowserBridgeServer?
    private let blobs = BrowserBlobStore()
    private struct Import { let storeID: UUID; let jobID: UUID; var touched: Date; let total: Int64? }
    private var imports: [String: Import] = [:]
    private var cleanup: Task<Void, Never>?
    init(controller: MainWindowController, configurationURL: URL, qaDirectory: URL? = nil) {
        self.controller = controller; self.configurationURL = configurationURL; self.qaDirectory = qaDirectory
    }
    func start() throws {
        let server = BrowserBridgeServer(configurationURL: configurationURL) { [weak self] request, deadline, isActive in
            guard let self else { return BrowserResponse(id: request.id, status: "error", message: "Application is closing") }
            return self.handle(request, deadline: deadline, isActive: isActive)
        }
        self.server = server; try server.start()
        cleanup = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                for (key, value) in Array(self.imports) where Date().timeIntervalSince(value.touched) > 180 {
                    self.abortStream(key, error: BrowserProtocolError.invalid)
                }
            }
        }
    }
    func stop() { cleanup?.cancel(); cleanup = nil; server?.stop(); server = nil; for key in Array(imports.keys) { abortStream(key, error: BrowserProtocolError.invalid) } }
    func abort(jobID: UUID) { for (key, value) in Array(imports) where value.jobID == jobID { abortStream(key, error: CancellationError()) } }
    private func abortStream(_ key: String, error: Error?) {
        guard let value = imports.removeValue(forKey: key) else { return }
        blobs.abort(id: value.storeID); try? controller?.browserImportFinished(id: value.jobID, error: error)
    }
    private func destination(_ link: BrowserLink, directory: URL? = nil) -> URL? {
        let filename = link.filename ?? link.httpURL.map(DownloadFilename.from) ?? "browser-import.bin"
        if let directory { return directory.appendingPathComponent(filename) }
        let panel = NSSavePanel(); panel.nameFieldStringValue = filename; panel.title = "Approve browser download destination"
        return panel.runModal() == .OK ? panel.url : nil
    }
    private func qaDestination(_ links: [BrowserLink]) -> URL? {
        guard let qaDirectory, links.allSatisfy({ link in
            let source = link.httpURL ?? link.pageURL.flatMap(URL.init(string:))
            return source?.host == "127.0.0.1" || source?.host == "localhost" || source?.host == "::1"
        }) else { return nil }
        let downloads = qaDirectory.appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        return downloads
    }
    private func handle(_ request: BrowserRequest, allowQA: Bool = true, deadline: Date = Date().addingTimeInterval(110), isActive: @MainActor () -> Bool = { true }) -> BrowserResponse {
        do {
            try request.validate(); guard Date() < deadline, isActive() else { throw BrowserProtocolError.invalid }; guard let controller else { throw BrowserProtocolError.invalid }
            switch request.op {
            case .ping: return BrowserResponse(id: request.id, status: "ready")
            case .download, .batch:
                let links = request.links!; var directory = allowQA ? qaDestination(links) : nil
                if links.count > 1 && directory == nil {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.title = "Approve destination for \(links.count) browser downloads"
                    guard panel.runModal() == .OK else { return BrowserResponse(id: request.id, status: "cancelled") }; directory = panel.url
                }
                var destinations: [URL] = []
                let chooseUnique = directory != nil
                var chosen = Set<String>()
                for link in links {
                    guard var path = destination(link, directory: directory) else { return BrowserResponse(id: request.id, status: "cancelled") }
                    if chooseUnique {
                        let original = path; var suffix = 1
                        while controller.browserDestinationIsOccupied(path) || chosen.contains(path.path) {
                            path = original.deletingLastPathComponent().appendingPathComponent("\(original.deletingPathExtension().lastPathComponent)-\(suffix)").appendingPathExtension(original.pathExtension); suffix += 1
                        }
                    }
                    guard !controller.browserDestinationIsOccupied(path), chosen.insert(path.path).inserted else { throw DownloadError.destinationExists }
                    destinations.append(path)
                }
                guard Date() < deadline, isActive() else { throw BrowserProtocolError.invalid }
                let jobs = try controller.queueBrowserDownloads(links: links, destinations: destinations)
                return BrowserResponse(id: request.id, status: "queued", jobID: jobs.first?.uuidString)
            case .blobBegin:
                guard let stream = request.streamID, UUID(uuidString: stream) != nil, imports[stream] == nil, imports.count < 4 else { throw BrowserProtocolError.invalid }
                let link = request.links![0]
                guard let path = destination(link, directory: allowQA ? qaDestination([link]) : nil) else { return BrowserResponse(id: request.id, status: "cancelled") }
                guard Date() < deadline, isActive() else { throw BrowserProtocolError.invalid }
                let storeID = try blobs.begin(destination: path, expectedBytes: request.totalBytes)
                do {
                    let jobID = try controller.beginBrowserImport(link: link, destination: path)
                    imports[stream] = Import(storeID: storeID, jobID: jobID, touched: Date(), total: request.totalBytes)
                    return BrowserResponse(id: request.id, status: "accepted", jobID: jobID.uuidString, streamID: stream)
                } catch { blobs.abort(id: storeID); throw error }
            case .blobChunk:
                let stream = request.streamID!; guard var value = imports[stream] else { throw BrowserProtocolError.invalid }
                let received = try blobs.append(id: value.storeID, sequence: request.sequence!, data: Data(base64Encoded: request.data!)!)
                value.touched = Date(); imports[stream] = value
                controller.browserImportProgress(id: value.jobID, received: received, total: value.total ?? received)
                return BrowserResponse(id: request.id, status: "accepted", streamID: stream)
            case .blobFinish:
                let stream = request.streamID!; guard let value = imports[stream], let total = request.totalBytes else { throw BrowserProtocolError.invalid }
                let result = try blobs.finish(id: value.storeID, expectedBytes: total); imports.removeValue(forKey: stream)
                controller.browserImportProgress(id: value.jobID, received: result.bytes, total: result.bytes)
                try controller.browserImportFinished(id: value.jobID, error: nil)
                return BrowserResponse(id: request.id, status: "complete", jobID: value.jobID.uuidString, streamID: stream, sha256: result.sha256)
            case .blobAbort:
                abortStream(request.streamID!, error: CancellationError())
                return BrowserResponse(id: request.id, status: "cancelled", streamID: request.streamID)
            }
        } catch {
            if (request.op == .blobChunk || request.op == .blobFinish), let stream = request.streamID { abortStream(stream, error: error) }
            return BrowserResponse(id: request.id, status: "error", message: error.localizedDescription)
        }
    }
    func handleURL(_ url: URL) {
        do {
            guard url.scheme == "idm-mac", url.host == "download", let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let payload = components.queryItems?.first(where: { $0.name == "payload" })?.value, payload.utf8.count <= 1398104 else { throw BrowserProtocolError.invalid }
            var base64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
            guard let bytes = Data(base64Encoded: base64), bytes.count <= NativeMessageFrame.maximumBytes else { throw BrowserProtocolError.invalid }
            var request = try JSONDecoder().decode(BrowserRequest.self, from: bytes)
            guard request.op == .download || request.op == .batch else { throw BrowserProtocolError.invalid }
            request.links = request.links?.map { BrowserLink(url: $0.url, filename: $0.filename, pageURL: $0.pageURL) }
            try request.validate()
            let response = handle(request, allowQA: false)
            if response.status == "error" { throw BrowserProtocolError.invalid }
        } catch { let alert = NSAlert(); alert.messageText = "Browser handoff failed"; alert.informativeText = error.localizedDescription; alert.runModal() }
    }
}
private extension String { var nonEmpty: String? { isEmpty ? nil : self } }
