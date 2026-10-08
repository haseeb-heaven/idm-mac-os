import Foundation

private struct Manifest: Codable, Sendable {
    var url: URL
    var finalURL: URL
    var length: Int64
    var validator: String?
    var ranges: Bool
    var chunkBytes: Int64
}
private actor Meter {
    var received: Int64
    let total: Int64
    let callback: @Sendable (TransferProgress) async -> Void
    var lastUpdate = Date.distantPast
    var nextSlot = ContinuousClock.now
    let rate: Int64
    init(received: Int64, total: Int64, rate: Int64, callback: @escaping @Sendable (TransferProgress) async -> Void) {
        self.received = received; self.total = total; self.rate = rate; self.callback = callback
    }
    func record(_ count: Int) async throws {
        if rate > 0 {
            let start = max(nextSlot, ContinuousClock.now)
            nextSlot = start.advanced(by: .seconds(Double(count) / Double(rate)))
            try await ContinuousClock().sleep(until: nextSlot)
        }
        received += Int64(count)
        if Date().timeIntervalSince(lastUpdate) >= 0.15 {
            lastUpdate = Date(); await callback(.init(received: received, total: total))
        }
    }
    func discard(_ count:Int64) async { received = max(0, received - count); await callback(.init(received:received,total:total)) }
    func finish() async { await callback(.init(received: received, total: total)) }
}

public struct DownloadEngine: Sendable {
    public let workDirectory: URL
    public init(workDirectory: URL) { self.workDirectory = workDirectory }
    public func discard(jobID: UUID) throws {
        let path = workDirectory.appendingPathComponent(jobID.uuidString)
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }
    public func run(job: DownloadJob, options: DownloadOptions = .init(), authorization: String? = nil,
                    progress: @escaping @Sendable (TransferProgress) async -> Void = { _ in }) async throws {
        guard !FileManager.default.fileExists(atPath: job.destination.path) else { throw DownloadError.destinationExists }
        guard options.chunkBytes > 0, options.connections > 0, options.connections <= 32,
              options.retries >= 0, options.retries <= 10, options.bytesPerSecond >= 0 else { throw DownloadError.storage("Invalid download options") }
        let fm = FileManager.default
        let directory = workDirectory.appendingPathComponent(job.id.uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 24 * 60 * 60
        config.httpMaximumConnectionsPerHost = options.connections
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let host = options.proxyHost, let port = options.proxyPort {
            config.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": host, "HTTPPort": port,
                                               "HTTPSEnable": 1, "HTTPSProxy": host, "HTTPSPort": port]
        }
        let chunks = HTTPChunkStream()
        let session = URLSession(configuration: config,delegate:chunks,delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        let manifestURL = directory.appendingPathComponent("manifest.json")
        var inspected = try await inspectWithRetry(job.url, session: session, authorization: authorization, options: options)
        if !options.useRanges { inspected.ranges = false }
        let fresh = inspected
        let transferAuthorization = HTTPChunkStream.sameOrigin(job.url,fresh.finalURL) ? authorization : nil
        if let data = try? Data(contentsOf: manifestURL), let old = try? JSONDecoder().decode(Manifest.self, from: data) {
            if old.url != fresh.url || old.finalURL != fresh.finalURL || old.length != fresh.length || old.validator == nil ||
                old.validator != fresh.validator || old.ranges != fresh.ranges || old.chunkBytes != fresh.chunkBytes {
                try fm.removeItem(at: directory); try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        } else {
            // Never trust orphaned partial files without a matching manifest.
            try fm.removeItem(at: directory); try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try JSONEncoder().encode(fresh).write(to: manifestURL, options: .atomic)
        let ranged = fresh.ranges && fresh.validator != nil && fresh.length > 0
        let count64 = ranged ? (fresh.length - 1) / options.chunkBytes + 1 : 1
        guard count64 <= 1_000_000 else { throw DownloadError.storage("Too many download segments") }
        let count = Int(count64)
        var initial: Int64 = 0
        for index in 0..<count {
            let file = directory.appendingPathComponent("\(index).part")
            if !ranged, fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
            if ranged {
                let expected = min(options.chunkBytes, fresh.length - Int64(index) * options.chunkBytes)
                let size = try fileSize(file)
                if size > expected { try fm.removeItem(at: file) } else { initial += size }
            }
        }
        let meter = Meter(received: initial, total: fresh.length, rate: options.bytesPerSecond, callback: progress)
        await progress(.init(received: initial, total: fresh.length))
        do {
        try await withThrowingTaskGroup(of: Void.self) { group in
            var next = 0
            func enqueue(_ index: Int) {
                group.addTask {
                    let start = Int64(index) * options.chunkBytes
                    let end = ranged ? min(start + options.chunkBytes - 1, fresh.length - 1) : nil
                    try await transfer(url: fresh.finalURL, manifest: fresh, start: ranged ? start : nil, end: end,
                                       file: directory.appendingPathComponent("\(index).part"), session: session,
                                       authorization: transferAuthorization, retries: options.retries, meter: meter, chunks: chunks)
                }
            }
            for _ in 0..<min(count, options.connections) { enqueue(next); next += 1 }
            while try await group.next() != nil {
                if next < count { enqueue(next); next += 1 }
            }
        }
        } catch DownloadError.rangeUnsupported {
            try Task.checkCancellation()
            try discard(jobID: job.id)
            var fallback = options; fallback.useRanges = false
            try await run(job: job, options: fallback, authorization: authorization, progress: progress)
            return
        }
        try Task.checkCancellation()
        try fm.createDirectory(at: job.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let assembling = job.destination.deletingLastPathComponent().appendingPathComponent(".idm-\(job.id).assembling")
        guard fm.createFile(atPath: assembling.path, contents: nil) else { throw DownloadError.storage("Cannot create output") }
        defer { try? fm.removeItem(at: assembling) }
        let output = try FileHandle(forWritingTo: assembling)
        do {
            var assembled: Int64 = 0
            for index in 0..<count {
                try Task.checkCancellation()
                let input = try FileHandle(forReadingFrom: directory.appendingPathComponent("\(index).part"))
                defer { try? input.close() }
                while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
                    try Task.checkCancellation()
                    try output.write(contentsOf: data); assembled += Int64(data.count)
                }
                try input.close()
                // Missing segments are re-fetched on a later resume if assembly is interrupted.
                // Removing copied segments keeps assembly disk usage near one file size.
                try fm.removeItem(at:directory.appendingPathComponent("\(index).part"))
            }
            guard fresh.length < 0 || assembled == fresh.length else { throw DownloadError.incomplete }
            try output.synchronize(); try output.close()
            // moveItem fails on collisions, including a file created while the transfer ran.
            try fm.moveItem(at: assembling, to: job.destination)
        } catch { try? output.close(); throw error }
        try fm.removeItem(at: directory)
        await meter.finish()
    }
    private func request(_ url: URL, authorization: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("IDMMac/0.1", forHTTPHeaderField: "User-Agent")
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        return request
    }
    private func validateResponse(_ http:HTTPURLResponse) throws {
        if http.statusCode == 403 && http.value(forHTTPHeaderField:"cf-mitigated")?.lowercased() == "challenge" { throw DownloadError.browserVerification }
        guard (200...299).contains(http.statusCode) else { throw DownloadError.http(http.statusCode) }
        let attachment = http.value(forHTTPHeaderField:"Content-Disposition")?.lowercased().hasPrefix("attachment") == true
        if http.value(forHTTPHeaderField:"Content-Type")?.lowercased().contains("text/html") == true && !attachment { throw DownloadError.webPage }
    }
    private func responseValidator(_ http:HTTPURLResponse, matching value:String?) -> String? {
        if value?.hasPrefix("\"") == true { return http.value(forHTTPHeaderField:"ETag") }
        return http.value(forHTTPHeaderField:"Last-Modified")
    }
    private func inspectWithRetry(_ url:URL, session:URLSession, authorization:String?, options:DownloadOptions) async throws -> Manifest {
        for attempt in 0...options.retries {
            try Task.checkCancellation()
            do { return try await inspect(url,session:session,authorization:authorization,chunkBytes:options.chunkBytes) }
            catch {
                if Task.isCancelled { throw CancellationError() }
                if let problem = error as? DownloadError {
                    if case .http(let code) = problem, code == 408 || code == 429 || code >= 500 {} else { throw problem }
                }
                if attempt == options.retries { throw error }
                try await Task.sleep(for:.seconds(pow(2,Double(attempt))))
            }
        }
        throw DownloadError.incomplete
    }
    private func inspect(_ url: URL, session: URLSession, authorization: String?, chunkBytes: Int64) async throws -> Manifest {
        var head = request(url, authorization: authorization); head.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: head)
        guard var http = response as? HTTPURLResponse else { throw DownloadError.http(0) }
        if [403,405,501].contains(http.statusCode) {
            var probe = request(url,authorization:authorization)
            probe.setValue("bytes=0-0",forHTTPHeaderField:"Range")
            let (bytes,response) = try await session.bytes(for:probe)
            defer { bytes.task.cancel() }
            guard let actual = response as? HTTPURLResponse else { throw DownloadError.http(0) }
            http = actual
            if http.statusCode == 416 {
                bytes.task.cancel()
                probe.setValue(nil,forHTTPHeaderField:"Range")
                let (full,fullResponse) = try await session.bytes(for:probe)
                defer { full.task.cancel() }
                guard let actual = fullResponse as? HTTPURLResponse else { throw DownloadError.http(0) }
                http = actual
            }
        }
        try validateResponse(http)
        let etag = http.value(forHTTPHeaderField: "ETag")
        let validator = etag.flatMap { $0.hasPrefix("W/") ? nil : $0 } ?? http.value(forHTTPHeaderField: "Last-Modified")
        let length = http.statusCode == 206 ? Int64(http.value(forHTTPHeaderField:"Content-Range")?.split(separator:"/").last ?? "") ?? -1 : http.expectedContentLength
        return Manifest(url: url, finalURL: http.url ?? url, length: length, validator: validator,
                        ranges: http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes", chunkBytes: chunkBytes)
    }
    private func fileSize(_ url: URL) throws -> Int64 {
        if !FileManager.default.fileExists(atPath: url.path) { return 0 }
        return (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
    private func transfer(url: URL, manifest: Manifest, start: Int64?, end: Int64?, file: URL,
                          session: URLSession, authorization: String?, retries: Int, meter: Meter, chunks: HTTPChunkStream) async throws {
        for attempt in 0...retries {
            try Task.checkCancellation()
            do {
                var existing = try fileSize(file)
                if let start, let end, existing == end - start + 1 { return }
                if start == nil && existing > 0 { try FileManager.default.removeItem(at: file); await meter.discard(existing); existing = 0 }
                var req = request(url, authorization: authorization)
                if let start, let end {
                    req.setValue("bytes=\(start + existing)-\(end)", forHTTPHeaderField: "Range")
                    req.setValue(manifest.validator, forHTTPHeaderField: "If-Range")
                }
                let opened = try await chunks.open(req,session:session)
                defer { opened.task.cancel() }
                let http = opened.response
                try validateResponse(http)
                if let start, let end {
                    guard http.statusCode == 206 else {
                        let returned = responseValidator(http,matching:manifest.validator)
                        if returned == nil || returned == manifest.validator { throw DownloadError.rangeUnsupported }
                        throw DownloadError.changedResource
                    }
                    guard http.value(forHTTPHeaderField: "Content-Range") == "bytes \(start + existing)-\(end)/\(manifest.length)" else { throw DownloadError.invalidRange }
                    if let returned = responseValidator(http,matching:manifest.validator), returned != manifest.validator { throw DownloadError.changedResource }
                }
                if !FileManager.default.fileExists(atPath: file.path) {
                    guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw DownloadError.storage("Cannot create segment") }
                }
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                var buffer = Data(); buffer.reserveCapacity(65536)
                var received = existing
                for try await data in opened.chunks {
                    defer { chunks.consumed(data.count,task:opened.task) }
                    try Task.checkCancellation()
                    buffer.append(data)
                    while buffer.count >= 65536 {
                        if let start, let end, received + 65536 > end - start + 1 { throw DownloadError.invalidRange }
                        try handle.write(contentsOf:buffer.prefix(65536));received += 65536
                        try await meter.record(65536);buffer.removeFirst(65536)
                    }
                }
                try Task.checkCancellation()
                if !buffer.isEmpty {
                    if let start, let end, received + Int64(buffer.count) > end - start + 1 { throw DownloadError.invalidRange }
                    try handle.write(contentsOf: buffer); received += Int64(buffer.count); try await meter.record(buffer.count)
                }
                try handle.synchronize()
                if let start, let end, received != end - start + 1 { throw DownloadError.incomplete }
                if start == nil && manifest.length >= 0 && received != manifest.length { throw DownloadError.incomplete }
                return
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if let problem = error as? DownloadError {
                    switch problem {
                    case .invalidRange, .rangeUnsupported, .browserVerification, .webPage, .changedResource, .destinationExists, .storage: throw problem
                    case .http(let code) where code != 408 && code != 429 && code < 500: throw problem
                    default: break
                    }
                }
                if attempt == retries { throw error }
                try await Task.sleep(for: .seconds(pow(2, Double(attempt))))
            }
        }
    }
}
