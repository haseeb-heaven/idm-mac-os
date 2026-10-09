import Foundation
import CryptoKit
import Darwin
import IDMCore

private enum CheckFailure: Error { case failed(String) }
private func require(_ condition: Bool, _ message: String = "Assertion failed") throws { if !condition { throw CheckFailure.failed(message) } }
private func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) throws { try require(a == b, "Expected \(a) == \(b)") }
private func XCTAssertFalse(_ value: Bool) throws { try require(!value) }
private func XCTAssertTrue(_ value: Bool) throws { try require(value) }
private func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T) throws { try require(a > b) }
private func XCTAssertGreaterThanOrEqual<T: Comparable>(_ a: T, _ b: T) throws { try require(a >= b) }
private func XCTFail(_ message: String) throws { throw CheckFailure.failed(message) }
private func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T) throws {
    do { _ = try expression() } catch { return }; throw CheckFailure.failed("Expected error")
}

final class Fixture {
    let process = Process()
    let base: URL
    init() throws {
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        process.executableURL = URL(fileURLWithPath:"/Library/Frameworks/Python.framework/Versions/3.12/bin/python3")
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        process.arguments = [root.appendingPathComponent("scripts/http_fixture.py").path]
        try process.run()
        var data = Data()
        while let byte = try output.fileHandleForReading.read(upToCount:1), !byte.isEmpty {
            if byte[0] == 10 { break }; data.append(byte)
        }
        guard let port = Int(String(decoding:data,as:UTF8.self)), let url = URL(string:"http://127.0.0.1:\(port)") else { throw DownloadError.storage("Fixture did not start") }
        base = url
    }
    deinit { if process.isRunning { process.terminate() } }
}
private actor ProgressRecorder {
    var maximum: Int64 = 0
    var final: Int64 = 0
    func record(_ update:TransferProgress) { maximum = max(maximum,update.received); final = update.received }
}
final class DownloadTests: @unchecked Sendable {
    private func directory() throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("idm-tests-\(UUID())")
        try FileManager.default.createDirectory(at:path,withIntermediateDirectories:true);return path
    }
    private func expected() -> Data { Data((0..<1048576).map { UInt8($0 % 256) }) }
    private func check(_ path:String,authorization:String? = nil) async throws {
        let fixture = try Fixture(); let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:fixture.base.appendingPathComponent(path),destination:dir.appendingPathComponent("result"))
        var options = DownloadOptions();options.chunkBytes = 256*1024
        try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job,options:options,authorization:authorization)
        let data = try Data(contentsOf:job.destination)
        try XCTAssertEqual(SHA256.hash(data:data),SHA256.hash(data:expected()))
    }
    func testMissingValidatorFallback() async throws { try await check("omitignore") }
    func testEmptyHeadFallback() async throws {
        let fixture = try Fixture();let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:fixture.base.appendingPathComponent("emptyhead"),destination:dir.appendingPathComponent("empty"))
        try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job)
        try XCTAssertEqual(try Data(contentsOf:job.destination).count,0)
    }
    func testSafeFilenames() throws {
        for value in ["%2E%2E%2Foutside.zip", "%2E%2E", "%5Coutside.zip", "%00bad.zip"] {
            try XCTAssertEqual(DownloadFilename.from(URL(string:"https://example.com/" + value)!),"download")
        }
        try XCTAssertEqual(DownloadFilename.from(URL(string:"https://example.com/file.zip")!),"file.zip")
    }
    func testWeakETagRangeFallback() async throws { try await check("weakignore") }
    func testGETLoginPageRejected() async throws { try await rejection("gethtml") }
    func testHTMLAttachmentAllowed() async throws {
        let fixture = try Fixture();let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:fixture.base.appendingPathComponent("htmlattachment"),destination:dir.appendingPathComponent("sample.html"))
        try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job)
        try XCTAssertEqual(try String(contentsOf:job.destination,encoding:.utf8),"<html>login or attachment</html>")
    }
    func testFiveGiBDownload() async throws {
        let fixture = try Fixture();let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:fixture.base.appendingPathComponent("large"),destination:dir.appendingPathComponent("5GiB.bin"))
        var options = DownloadOptions();options.chunkBytes = 8*1024*1024
        let start = Date()
        try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job,options:options)
        let size = (try FileManager.default.attributesOfItem(atPath:job.destination.path)[.size] as! NSNumber).int64Value
        try XCTAssertEqual(size,5*1024*1024*1024)
        let pattern = expected();var reference = SHA256();for _ in 0..<5120 { reference.update(data:pattern) }
        let file = try FileHandle(forReadingFrom:job.destination);defer { try? file.close() };var result = SHA256()
        while let data = try autoreleasepool(invoking: { try file.read(upToCount:1024*1024) }), !data.isEmpty { result.update(data:data) }
        try XCTAssertEqual(result.finalize(),reference.finalize())
        var usage = rusage()
        try XCTAssertEqual(getrusage(RUSAGE_SELF,&usage),0)
        // Darwin reports ru_maxrss in bytes. Keep the opt-in large-file check below 1 GiB.
        try require(usage.ru_maxrss < 1024*1024*1024,"Large-file peak RSS exceeded 1 GiB")
        log("PASS large-file memory: peak RSS \(usage.ru_maxrss) bytes (< 1 GiB)")
        log("PASS 5 GiB download: 5368709120 bytes, full SHA256 verified, \(Int(Date().timeIntervalSince(start))) seconds")
    }
    func testQueueScheduling() throws {
        let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let now = Date(timeIntervalSince1970:1000)
        var scheduled = try DownloadJob(url:URL(string:"https://example.com/a")!,destination:dir.appendingPathComponent("a"),scheduledAt:now.addingTimeInterval(60))
        var immediate = try DownloadJob(url:URL(string:"https://example.com/b")!,destination:dir.appendingPathComponent("b"))
        try XCTAssertEqual(QueuePolicy.next(in:[scheduled,immediate],at:now)?.id,immediate.id)
        try XCTAssertEqual(QueuePolicy.next(in:[scheduled,immediate],at:now.addingTimeInterval(60))?.id,scheduled.id)
        scheduled.state = .paused;immediate.state = .completed
        try XCTAssertEqual(QueuePolicy.next(in:[scheduled,immediate],at:now.addingTimeInterval(60))?.id,nil)
    }
    func testTrustedHTTPS() async throws {
        let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:URL(string:"https://raw.githubusercontent.com/github/gitignore/main/Swift.gitignore")!,destination:dir.appendingPathComponent("https-result"))
        try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job)
        let reference = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build/https-reference.txt")
        try XCTAssertEqual(SHA256.hash(data:try Data(contentsOf:job.destination)),SHA256.hash(data:try Data(contentsOf:reference)))
    }
    func testHTTPProxy() async throws {
        let fixture = try Fixture();let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:URL(string:"http://idm-fixture.invalid/file")!,destination:dir.appendingPathComponent("result"))
        var options = DownloadOptions();options.proxyHost = "127.0.0.1";options.proxyPort = fixture.base.port
        try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job,options:options)
        try XCTAssertEqual(SHA256.hash(data:try Data(contentsOf:job.destination)),SHA256.hash(data:expected()))
    }
    func testKeychainRoundTrip() throws {
        let id = UUID();defer { try? CredentialStore.delete(jobID:id) }
        try CredentialStore.save(username:"fixture-user",password:"fixture-password",jobID:id)
        try XCTAssertEqual(try CredentialStore.authorization(jobID:id),"Basic " + Data("fixture-user:fixture-password".utf8).base64EncodedString())
        try CredentialStore.save(username:"fixture-user",password:"updated",jobID:id)
        try XCTAssertEqual(try CredentialStore.authorization(jobID:id),"Basic " + Data("fixture-user:updated".utf8).base64EncodedString())
        try CredentialStore.delete(jobID:id);try XCTAssertEqual(try CredentialStore.authorization(jobID:id),nil)
    }
    func testHeadForbiddenGetAllowed() async throws { try await check("headforbidden") }
    func testBrowserVerificationMessage() async throws {
        let fixture = try Fixture();let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:fixture.base.appendingPathComponent("protected"),destination:dir.appendingPathComponent("result"))
        do { try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job);try XCTFail("Expected verification error") }
        catch DownloadError.browserVerification {} catch { throw error }
        try XCTAssertFalse(FileManager.default.fileExists(atPath:job.destination.path))
    }
    func testHTMLPageRejected() async throws { try await rejection("page") }
    func testHeadInspectionRetry() async throws { try await check("headflaky") }
    func testSingleStreamRetryProgress() async throws {
        let fixture = try Fixture(); let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:fixture.base.appendingPathComponent("retryfull"),destination:dir.appendingPathComponent("result"))
        let recorder = ProgressRecorder()
        try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job) { await recorder.record($0) }
        let final = await recorder.final; try XCTAssertEqual(final,1048576)
        let maximum = await recorder.maximum; try require(maximum <= 1048576,"Progress exceeded file length")
        try XCTAssertEqual(SHA256.hash(data:try Data(contentsOf:job.destination)),SHA256.hash(data:expected()))
    }
    func testStorageFailureDoesNotPublishFile() async throws {
        let fixture = try Fixture(); let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
        let work = dir.appendingPathComponent("work"); try Data().write(to:work)
        let job = try DownloadJob(url:fixture.base.appendingPathComponent("file"),destination:dir.appendingPathComponent("result"))
        do { try await DownloadEngine(workDirectory:work).run(job:job); try XCTFail("Expected storage error") }
        catch let failure as CheckFailure { throw failure } catch {}
        try XCTAssertFalse(FileManager.default.fileExists(atPath:job.destination.path))
    }
    func testSegmentedDownload() async throws { try await check("file") }
    func testIgnoredRangesFallback() async throws { try await check("ignore") }
    func testSingleStream() async throws { try await check("norange") }
    func testNoValidatorUsesSingleStream() async throws { try await check("novalidator") }
    func testRedirect() async throws { try await check("redirect") }
    func testAuthentication() async throws { try await check("auth",authorization:"Basic dXNlcjpwYXNz") }
    func testRetryServerFailure() async throws { try await check("flaky") }
    func testHeadUnsupported() async throws { try await check("nohead") }
    func testUnknownLength() async throws { try await check("unknown") }
    func testEmptyFile() async throws {
        let fixture = try Fixture();let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:fixture.base.appendingPathComponent("empty"),destination:dir.appendingPathComponent("empty"))
        try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job)
        try XCTAssertEqual(try Data(contentsOf:job.destination).count,0)
    }
    func testMalformedRangeRejected() async throws { try await rejection("bad") }
    func testChangedResourceRejected() async throws { try await rejection("changed") }
    func testAuthenticationRejected() async throws { try await rejection("auth") }
    func test404Rejected() async throws { try await rejection("missing") }
    func testTruncatedFileRejected() async throws { try await rejection("truncate") }
    private func rejection(_ path:String) async throws {
        let fixture = try Fixture();let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:fixture.base.appendingPathComponent(path),destination:dir.appendingPathComponent("result"))
        var options = DownloadOptions();options.chunkBytes = 256*1024;options.retries = 0
        do { try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job,options:options);try XCTFail("Expected rejection") }
        catch let failure as CheckFailure { throw failure }
        catch { try XCTAssertFalse(FileManager.default.fileExists(atPath:job.destination.path)) }
    }
    func testCollisionPreservesExistingFile() async throws {
        let fixture = try Fixture();let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:fixture.base.appendingPathComponent("file"),destination:dir.appendingPathComponent("result"))
        try Data("original".utf8).write(to:job.destination)
        do { try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job);try XCTFail("Expected collision") } catch let failure as CheckFailure { throw failure } catch {}
        try XCTAssertEqual(try String(contentsOf:job.destination,encoding:.utf8),"original")
    }
    func testCancelAndResume() async throws {
        let fixture = try Fixture();let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:fixture.base.appendingPathComponent("slow"),destination:dir.appendingPathComponent("result"))
        let engine = DownloadEngine(workDirectory:dir.appendingPathComponent("work"));var options = DownloadOptions();options.chunkBytes = 256*1024;options.connections = 2
        let recorder = ProgressRecorder()
        let task = Task { try await engine.run(job:job,options:options) { await recorder.record($0) } }
        try await Task.sleep(for:.milliseconds(250));task.cancel()
        do { try await task.value;try XCTFail("Expected cancellation") } catch let failure as CheckFailure { throw failure } catch {}
        try XCTAssertFalse(FileManager.default.fileExists(atPath:job.destination.path))
        let max = await recorder.maximum; try XCTAssertGreaterThan(max,0)
        try await engine.run(job:job,options:options)
        try XCTAssertEqual(SHA256.hash(data:try Data(contentsOf:job.destination)),SHA256.hash(data:expected()))
    }
    func testSpeedLimit() async throws {
        let fixture = try Fixture();let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:fixture.base.appendingPathComponent("file"),destination:dir.appendingPathComponent("result"))
        var options = DownloadOptions();options.bytesPerSecond = 1024*1024
        let start = ContinuousClock.now
        try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job,options:options)
        try XCTAssertGreaterThanOrEqual(start.duration(to:.now),.milliseconds(950))
    }
    func testGrabberIgnoresInactiveBase() async throws {
        let fixture = try Fixture()
        try XCTAssertEqual(try await SiteGrabber.links(on:fixture.base.appendingPathComponent("commentbase")),[fixture.base.appendingPathComponent("assets/file.zip")])
    }
    func testGrabberBaseURL() async throws {
        let fixture = try Fixture()
        try XCTAssertEqual(try await SiteGrabber.links(on:fixture.base.appendingPathComponent("basepage")),[fixture.base.appendingPathComponent("assets/file.zip")])
    }
    func testGrabberDeduplicatesFileLinks() async throws {
        let fixture = try Fixture()
        let links = try await SiteGrabber.links(on:fixture.base.appendingPathComponent("page"))
        try XCTAssertEqual(links,[fixture.base.appendingPathComponent("asset.zip")])
    }
    func testSQLiteRoundTripAndCrashRecovery() throws {
        let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let store = try JobStore(url:dir.appendingPathComponent("jobs.sqlite"))
        var job = try DownloadJob(url:URL(string:"https://example.com/file")!,destination:dir.appendingPathComponent("file"),scheduledAt:Date(timeIntervalSince1970:1000))
        job.state = .downloading;job.receivedBytes = 42
        try store.save([job]);let loaded = try store.load()
        try XCTAssertEqual(loaded.count,1);try XCTAssertEqual(loaded[0].id,job.id);try XCTAssertEqual(loaded[0].state,.paused);try XCTAssertEqual(loaded[0].receivedBytes,42);try XCTAssertEqual(loaded[0].scheduledAt,job.scheduledAt)
        try store.save([]);try XCTAssertTrue(try store.load().isEmpty)
    }
    func testBrowserLocalURLs() throws {
        for value in ["blob:https://hark.com/477987cc-348b-4564-8c7c-f4e1ae128c7c","blob:https://igi-qvm-editor.vercel.app/25888708-6d81-4dc8-abff-3827c0284670","blob:https://cursor.com/cda1e668-eb2d-4179-bbc6-5b75fbdca930"] {
            do { _ = try DownloadJob(url:URL(string:value)!,destination:URL(fileURLWithPath:"/tmp/blob"));try XCTFail("Blob URL accepted") }
            catch DownloadError.browserLocalURL { }
            log("PASS browser-local URL rejected with actionable error: " + value)
        }
    }
    func testChangedChunkLayoutResume() async throws {
        let fixture = try Fixture();let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:fixture.base.appendingPathComponent("slow"),destination:dir.appendingPathComponent("result"))
        let engine = DownloadEngine(workDirectory:dir.appendingPathComponent("work"));var options = DownloadOptions();options.chunkBytes = 256*1024
        let task = Task { try await engine.run(job:job,options:options) }
        try await Task.sleep(for:.milliseconds(250));task.cancel();_ = try? await task.value
        options.chunkBytes = 128*1024
        try await engine.run(job:job,options:options)
        try XCTAssertEqual(SHA256.hash(data:try Data(contentsOf:job.destination)),SHA256.hash(data:expected()))
    }
    func testInvalidOptionsAndDestination() async throws {
        let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        try XCTAssertThrowsError(try DownloadJob(url:URL(string:"https://example.com/file")!,destination:URL(string:"https://example.com/out")!))
        let job = try DownloadJob(url:URL(string:"https://example.com/file")!,destination:dir.appendingPathComponent("out"))
        for number in 0..<4 {
            var options = DownloadOptions()
            switch number { case 0:options.connections = 0;case 1:options.chunkBytes = 0;case 2:options.retries = 11;default:options.bytesPerSecond = -1 }
            do { try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job,options:options);try XCTFail("Invalid options accepted") }
            catch DownloadError.storage { }
        }
    }
    func testGrabberLimitsAndErrors() async throws {
        let fixture = try Fixture()
        for value in ["file:///tmp/page","https://user@example.com/page"] {
            do { _ = try await SiteGrabber.links(on:URL(string:value)!);try XCTFail("Unsafe grabber URL accepted") }
            catch DownloadError.invalidURL { }
        }
        do { _ = try await SiteGrabber.links(on:fixture.base.appendingPathComponent("missing"));try XCTFail("Missing page accepted") }
        catch DownloadError.http(404) { }
        do { _ = try await SiteGrabber.links(on:fixture.base.appendingPathComponent("bigpage"));try XCTFail("Oversized page accepted") }
        catch DownloadError.storage { }
        try XCTAssertEqual(try await SiteGrabber.links(on:fixture.base.appendingPathComponent("manylinks")).count,500)
    }
    func testAllErrorMessages() throws {
        let errors:[DownloadError] = [.invalidURL,.invalidDestination,.http(403),.invalidRange,.rangeUnsupported,.browserLocalURL,.browserVerification,.webPage,.destinationExists,.storage("disk"),.changedResource,.incomplete]
        for error in errors { try XCTAssertFalse(error.localizedDescription.isEmpty) }
    }
    func testChunkStreamBackpressure() async throws {
        let fixture = try Fixture();let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:fixture.base.appendingPathComponent("bulk"),destination:dir.appendingPathComponent("bulk"))
        var options = DownloadOptions();options.useRanges = false;options.bytesPerSecond = 1024*1024
        let started = ContinuousClock.now
        try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job,options:options)
        try XCTAssertEqual(SHA256.hash(data:try Data(contentsOf:job.destination)),SHA256.hash(data:expected()+expected()+expected()+expected()))
        try XCTAssertGreaterThanOrEqual(started.duration(to:.now),.milliseconds(3800))
    }
    func testCancelBeforeStreamHeaders() async throws {
        let fixture = try Fixture();let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        let job = try DownloadJob(url:fixture.base.appendingPathComponent("delayheaders"),destination:dir.appendingPathComponent("result"))
        let engine = DownloadEngine(workDirectory:dir.appendingPathComponent("work"))
        let task = Task { try await engine.run(job:job) }
        try await Task.sleep(for:.milliseconds(100));task.cancel()
        do { try await task.value;try XCTFail("Cancellation before headers succeeded") }
        catch is CancellationError { }
        try XCTAssertFalse(FileManager.default.fileExists(atPath:job.destination.path))
    }
    func testSameOriginRedirectCredentials() async throws { try await check("redirectauth",authorization:"Basic dXNlcjpwYXNz") }
    func testCrossOriginRedirectDropsCredentials() async throws {
        let fixture = try Fixture();let target = try Fixture();let dir = try directory();defer { try? FileManager.default.removeItem(at:dir) }
        var url = URLComponents(url:fixture.base.appendingPathComponent("externalredirect"),resolvingAgainstBaseURL:false)!
        url.queryItems = [URLQueryItem(name:"target",value:target.base.appendingPathComponent("auth-leak-check").absoluteString)]
        let job = try DownloadJob(url:url.url!,destination:dir.appendingPathComponent("result"))
        var options = DownloadOptions();options.chunkBytes = 256*1024
        try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job,options:options,authorization:"Basic dXNlcjpwYXNz")
        try XCTAssertEqual(SHA256.hash(data:try Data(contentsOf:job.destination)),SHA256.hash(data:expected()))
    }
    func testURLValidation() throws {
        try XCTAssertThrowsError(try DownloadJob(url:URL(string:"file:///tmp/x")!,destination:URL(fileURLWithPath:"/tmp/out")))
        try XCTAssertThrowsError(try DownloadJob(url:URL(string:"https://user:secret@example.com/x")!,destination:URL(fileURLWithPath:"/tmp/out")))
    }
}

private func log(_ text:String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }
@main struct TestRunner {
    static func main() async throws {
        if ProcessInfo.processInfo.environment["IDM_BROWSER_CHECKS_ONLY"] == "1" { let count=try await runBrowserChecks();print("Passed \(count) browser checks");return }
        let suite = DownloadTests()
        if ProcessInfo.processInfo.arguments.contains("--large") { try await suite.testFiveGiBDownload();return }
        if ProcessInfo.processInfo.arguments.contains("--https") { try await suite.testTrustedHTTPS();log("PASS trusted HTTPS with independent SHA256 reference");return }
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of:"--url"), ProcessInfo.processInfo.arguments.count > index + 1 {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("idm-external-\(UUID())")
            defer { try? FileManager.default.removeItem(at:dir) }
            let job = try DownloadJob(url:URL(string:ProcessInfo.processInfo.arguments[index+1])!,destination:dir.appendingPathComponent("result"))
            do {
                try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job)
                let attrs = try FileManager.default.attributesOfItem(atPath:job.destination.path)
                let handle = try FileHandle(forReadingFrom:job.destination);defer { try? handle.close() };var hash = SHA256()
                while let bytes = try autoreleasepool(invoking: { try handle.read(upToCount:1024*1024) }), !bytes.isEmpty { hash.update(data:bytes) }
                let digest = hash.finalize().map { String(format:"%02x",$0) }.joined()
                if let refIndex = ProcessInfo.processInfo.arguments.firstIndex(of:"--sha256"), ProcessInfo.processInfo.arguments.count > refIndex + 1 {
                    try XCTAssertEqual(digest,ProcessInfo.processInfo.arguments[refIndex+1])
                }
                log("DOWNLOAD SUCCEEDED: \(attrs[.size] ?? 0) bytes, SHA256 \(digest)")
            } catch { log("DOWNLOAD FAILED: \(error.localizedDescription)");exit(1) }
            return
        }
        var passed = 0
        try await suite.testMissingValidatorFallback();passed += 1;log("PASS testMissingValidatorFallback")
        try await suite.testEmptyHeadFallback();passed += 1;log("PASS testEmptyHeadFallback")
        try suite.testSafeFilenames();passed += 1;log("PASS testSafeFilenames")
        log("RUN testWeakETagRangeFallback");try await suite.testWeakETagRangeFallback();passed += 1;log("PASS testWeakETagRangeFallback")
        log("RUN testGETLoginPageRejected");try await suite.testGETLoginPageRejected();passed += 1;log("PASS testGETLoginPageRejected")
        log("RUN testHTMLAttachmentAllowed");try await suite.testHTMLAttachmentAllowed();passed += 1;log("PASS testHTMLAttachmentAllowed")
        log("RUN testQueueScheduling");try suite.testQueueScheduling();passed += 1;log("PASS testQueueScheduling")
        log("RUN testHTTPProxy"); try await suite.testHTTPProxy(); passed += 1; log("PASS testHTTPProxy")
        log("RUN testKeychainRoundTrip"); try suite.testKeychainRoundTrip(); passed += 1; log("PASS testKeychainRoundTrip")
        log("RUN testHeadForbiddenGetAllowed"); try await suite.testHeadForbiddenGetAllowed(); passed += 1; log("PASS testHeadForbiddenGetAllowed")
        log("RUN testBrowserVerificationMessage"); try await suite.testBrowserVerificationMessage(); passed += 1; log("PASS testBrowserVerificationMessage")
        log("RUN testHTMLPageRejected"); try await suite.testHTMLPageRejected(); passed += 1; log("PASS testHTMLPageRejected")
        log("RUN testHeadInspectionRetry"); try await suite.testHeadInspectionRetry(); passed += 1; log("PASS testHeadInspectionRetry")
        log("RUN testSingleStreamRetryProgress"); try await suite.testSingleStreamRetryProgress(); passed += 1; log("PASS testSingleStreamRetryProgress")
        log("RUN testStorageFailureDoesNotPublishFile"); try await suite.testStorageFailureDoesNotPublishFile(); passed += 1; log("PASS testStorageFailureDoesNotPublishFile")
        log("RUN testSegmentedDownload"); try await suite.testSegmentedDownload(); passed += 1; log("PASS testSegmentedDownload")
        log("RUN testIgnoredRangesFallback"); try await suite.testIgnoredRangesFallback(); passed += 1; log("PASS testIgnoredRangesFallback")
        log("RUN testSingleStream"); try await suite.testSingleStream(); passed += 1; log("PASS testSingleStream")
        log("RUN testNoValidatorUsesSingleStream"); try await suite.testNoValidatorUsesSingleStream(); passed += 1; log("PASS testNoValidatorUsesSingleStream")
        log("RUN testRedirect"); try await suite.testRedirect(); passed += 1; log("PASS testRedirect")
        log("RUN testAuthentication"); try await suite.testAuthentication(); passed += 1; log("PASS testAuthentication")
        log("RUN testRetryServerFailure"); try await suite.testRetryServerFailure(); passed += 1; log("PASS testRetryServerFailure")
        log("RUN testHeadUnsupported"); try await suite.testHeadUnsupported(); passed += 1; log("PASS testHeadUnsupported")
        log("RUN testUnknownLength"); try await suite.testUnknownLength(); passed += 1; log("PASS testUnknownLength")
        log("RUN testEmptyFile"); try await suite.testEmptyFile(); passed += 1; log("PASS testEmptyFile")
        log("RUN testMalformedRangeRejected"); try await suite.testMalformedRangeRejected(); passed += 1; log("PASS testMalformedRangeRejected")
        log("RUN testChangedResourceRejected"); try await suite.testChangedResourceRejected(); passed += 1; log("PASS testChangedResourceRejected")
        log("RUN testAuthenticationRejected"); try await suite.testAuthenticationRejected(); passed += 1; log("PASS testAuthenticationRejected")
        log("RUN test404Rejected"); try await suite.test404Rejected(); passed += 1; log("PASS test404Rejected")
        log("RUN testTruncatedFileRejected"); try await suite.testTruncatedFileRejected(); passed += 1; log("PASS testTruncatedFileRejected")
        log("RUN testCollisionPreservesExistingFile"); try await suite.testCollisionPreservesExistingFile(); passed += 1; log("PASS testCollisionPreservesExistingFile")
        log("RUN testCancelAndResume"); try await suite.testCancelAndResume(); passed += 1; log("PASS testCancelAndResume")
        log("RUN testSpeedLimit"); try await suite.testSpeedLimit(); passed += 1; log("PASS testSpeedLimit")
        try await suite.testGrabberIgnoresInactiveBase();passed += 1;log("PASS testGrabberIgnoresInactiveBase")
        try await suite.testGrabberBaseURL();passed += 1;log("PASS testGrabberBaseURL")
        log("RUN testGrabberDeduplicatesFileLinks"); try await suite.testGrabberDeduplicatesFileLinks(); passed += 1; log("PASS testGrabberDeduplicatesFileLinks")
        log("RUN testSQLiteRoundTripAndCrashRecovery"); try suite.testSQLiteRoundTripAndCrashRecovery(); passed += 1; log("PASS testSQLiteRoundTripAndCrashRecovery")
        try await suite.testChangedChunkLayoutResume();passed += 1;log("PASS testChangedChunkLayoutResume")
        try await suite.testInvalidOptionsAndDestination();passed += 1;log("PASS testInvalidOptionsAndDestination")
        try await suite.testGrabberLimitsAndErrors();passed += 1;log("PASS testGrabberLimitsAndErrors")
        try suite.testAllErrorMessages();passed += 1;log("PASS testAllErrorMessages")
        try await suite.testChunkStreamBackpressure();passed += 1;log("PASS testChunkStreamBackpressure")
        try await suite.testCancelBeforeStreamHeaders();passed += 1;log("PASS testCancelBeforeStreamHeaders")
        try await suite.testSameOriginRedirectCredentials();passed += 1;log("PASS testSameOriginRedirectCredentials")
        try await suite.testCrossOriginRedirectDropsCredentials();passed += 1;log("PASS testCrossOriginRedirectDropsCredentials")
        try suite.testBrowserLocalURLs();passed += 1;log("PASS testBrowserLocalURLs")
        log("RUN testURLValidation"); try suite.testURLValidation(); passed += 1; log("PASS testURLValidation")
        passed += try await runBrowserChecks();log("PASS browser protocol, blobs, legacy jobs and Keychain")
        log("Passed \(passed) checks")
    }
}
