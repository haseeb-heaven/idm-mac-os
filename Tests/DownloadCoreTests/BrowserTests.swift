import Foundation
import CryptoKit
import DownloadCore
private enum BrowserCheckError:Error { case failed(Int) }
private func check(_ value:Bool, line:Int = #line) throws { if !value { throw BrowserCheckError.failed(line) } }
private func rejects(line:Int = #line, _ action:() throws -> Void) throws { do { try action() } catch { return };throw BrowserCheckError.failed(line) }
func runBrowserChecks() async throws -> Int {
    let id=UUID().uuidString
    let payload=try JSONEncoder().encode(BrowserRequest(id:id,op:.ping))
    let frame=try NativeMessageFrame.encode(payload)
    var fragmented=Data(frame.prefix(2));try check(try NativeMessageFrame.extract(buffer:&fragmented) == nil)
    fragmented.append(frame.dropFirst(2));fragmented.append(frame)
    try check(try NativeMessageFrame.extract(buffer:&fragmented) == payload);try check(try NativeMessageFrame.extract(buffer:&fragmented) == payload);try check(fragmented.isEmpty)
    try rejects { _=try NativeMessageFrame.encode(Data(count:NativeMessageFrame.maximumBytes+1)) }
    var invalid=Data([0xff,0xff,0xff,0xff]);try rejects { _=try NativeMessageFrame.extract(buffer:&invalid) }
    let pipe=Pipe();try pipe.fileHandleForWriting.write(contentsOf:Data([4,0,0,0,1]));try pipe.fileHandleForWriting.close();try rejects { _=try NativeMessageFrame.read(from:pipe.fileHandleForReading) }
    try BrowserRequest(id:id,op:.download,links:[BrowserLink(url:"https://example.com/file",headers:["Cookie":"a=b","Referer":"https://example.com/page"])]).validate()
    for bad in ["file:///tmp/x","https://u:p@example.com/x","https://example.com/x\r\nCookie:a"] { do { try BrowserLink(url:bad).validate();try FileHandle.standardError.write(contentsOf:Data("Unexpected accepted URL: \(bad.debugDescription)\n".utf8));throw BrowserCheckError.failed(#line) } catch is BrowserProtocolError {} }
    try rejects { try BrowserLink(url:"https://example.com",filename:"../x").validate() }
    try rejects { try BrowserHeaders.validate(["Cookie":"a\r\nb"]) }
    try rejects { try BrowserHeaders.validate(["Authorization":"secret"]) }
    try rejects { try BrowserHeaders.validate(["Cookie":String(repeating:"a",count:65537)]) }
    try rejects { try BrowserRequest(id:id,op:.batch,links:Array(repeating:BrowserLink(url:"https://example.com"),count:201)).validate() }
    try rejects { try BrowserRequest(id:id,op:.blobChunk,streamID:id,sequence:0,data:"!!!!").validate() }
    try BrowserLink(url:"blob:https://example.com/a",pageURL:"https://example.com/page").validate(allowBlob:true)
    try rejects { try BrowserLink(url:"blob:https://example.com/a",pageURL:"https://other.example/page").validate(allowBlob:true) }
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent("mdm-browser-tests-\(UUID())");try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);defer { try? FileManager.default.removeItem(at:dir) }
    let store=BrowserBlobStore();let destination=dir.appendingPathComponent("result.bin");let stream=try store.begin(destination:destination,expectedBytes:3)
    try rejects { _=try store.append(id:stream,sequence:1,data:Data([1])) }
    try rejects { _=try store.append(id:stream,sequence:0,data:Data(count:131073)) }
    _=try store.append(id:stream,sequence:0,data:Data([1,2]));try rejects { _=try store.finish(id:stream,expectedBytes:3) }
    _=try store.append(id:stream,sequence:1,data:Data([3]));let result=try store.finish(id:stream,expectedBytes:3)
    try check(result.bytes == 3);try check(result.sha256 == SHA256.hash(data:Data([1,2,3])).map { String(format:"%02x",$0) }.joined());try check(try Data(contentsOf:destination) == Data([1,2,3]))
    try rejects { _=try store.begin(destination:destination) }
    let abort=try store.begin(destination:dir.appendingPathComponent("abort"));store.abort(id:abort)
    try check(try FileManager.default.contentsOfDirectory(atPath:dir.path) == ["result.bin"])
    let collision=dir.appendingPathComponent("collision");let pending=try store.begin(destination:collision);try Data([9]).write(to:collision);try rejects { _=try store.finish(id:pending) };store.abort(id:pending);try check(try Data(contentsOf:collision) == Data([9]))
    let job=try DownloadJob(url:URL(string:"https://example.com/file")!,destination:destination)
    let legacy=try JSONEncoder().encode(job);let decoded=try JSONDecoder().decode(DownloadJob.self,from:legacy);try check(decoded.browserSourceURL == nil)
    var imported=job;imported.browserSourceURL=URL(string:"blob:https://example.com/a")
    do { try await DownloadEngine(workDirectory:dir).run(job:imported);throw BrowserCheckError.failed(#line) } catch DownloadError.browserLocalURL {}
    let key=UUID();defer { try? CredentialStore.deleteHeaders(jobID:key) }
    try CredentialStore.saveHeaders(["Cookie":"fixture=1"],jobID:key);try check(try CredentialStore.headers(jobID:key) == ["Cookie":"fixture=1"]);try CredentialStore.deleteHeaders(jobID:key);try check(try CredentialStore.headers(jobID:key).isEmpty)
    let source=try Fixture();let target=try Fixture()
    let headers=["Cookie":"fixture=1","Referer":"https://example.com/page","User-Agent":"BrowserFixture/1"]
    for path in ["browserheaders","browserredirect"] {
        let job=try DownloadJob(url:source.base.appendingPathComponent(path),destination:dir.appendingPathComponent(path))
        try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:job,headers:headers)
        try check(try Data(contentsOf:job.destination).count == 1048576)
    }
    var redirect=URLComponents(url:source.base.appendingPathComponent("externalredirect"),resolvingAgainstBaseURL:false)!
    redirect.queryItems=[URLQueryItem(name:"target",value:target.base.appendingPathComponent("browserleak").absoluteString)]
    let redirected=try DownloadJob(url:redirect.url!,destination:dir.appendingPathComponent("cross"))
    try await DownloadEngine(workDirectory:dir.appendingPathComponent("work")).run(job:redirected,authorization:"Basic secret",headers:headers)
    try check(try Data(contentsOf:redirected.destination).count == 1048576)
    return 10
}
