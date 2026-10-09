import Foundation

public enum BrowserProtocolError: Error, LocalizedError { case invalid
    public var errorDescription: String? { "Invalid browser message." }
}
public enum BrowserOperation: String, Codable, Sendable { case ping, download, batch, blobBegin, blobChunk, blobFinish, blobAbort }
public enum BrowserHeaders {
    public static func validate(_ headers: [String:String]) throws {
        guard headers.reduce(0, { $0 + $1.key.utf8.count + $1.value.utf8.count }) <= 65536 else { throw BrowserProtocolError.invalid }
        var seen = Set<String>()
        for (key,value) in headers {
            let name = key.lowercased()
            guard ["cookie","referer","user-agent"].contains(name), seen.insert(name).inserted,
                  !value.unicodeScalars.contains(where: { $0.value == 13 || $0.value == 10 || $0.value == 0 }) else { throw BrowserProtocolError.invalid }
            if name == "referer" { try BrowserLink(url:value).validate() }
        }
    }
}
public struct BrowserLink: Codable, Sendable {
    public var url: String; public var filename: String?; public var pageURL: String?; public var headers: [String:String]?
    public init(url:String, filename:String? = nil, pageURL:String? = nil, headers:[String:String]? = nil) { self.url=url; self.filename=filename; self.pageURL=pageURL; self.headers=headers }
    public var httpURL: URL? { guard let u=URL(string:url), ["http","https"].contains(u.scheme?.lowercased() ?? "") else { return nil }; return u }
    public func validate(allowBlob:Bool = false) throws {
        guard !url.unicodeScalars.contains(where: { $0.value == 13 || $0.value == 10 || $0.value == 0 }) else { throw BrowserProtocolError.invalid }
        if allowBlob && url.hasPrefix("blob:") {
            let inner=String(url.dropFirst(5)); try BrowserLink(url:inner).validate()
            guard let pageURL, let page=URL(string:pageURL), let source=URL(string:inner) else { throw BrowserProtocolError.invalid }
            try BrowserLink(url:pageURL).validate()
            guard HTTPChunkStream.sameOrigin(page,source) else { throw BrowserProtocolError.invalid }
        } else { guard let u=httpURL, u.host?.isEmpty == false, u.user == nil, u.password == nil else { throw BrowserProtocolError.invalid } }
        if let filename { guard !filename.isEmpty, filename != ".", filename != "..", !filename.contains("/"), !filename.contains("\\"), !filename.unicodeScalars.contains(where: { $0.value == 13 || $0.value == 10 || $0.value == 0 }) else { throw BrowserProtocolError.invalid } }
        if let pageURL { try BrowserLink(url:pageURL).validate() }
        if let headers { try BrowserHeaders.validate(headers) }
    }
}
public struct BrowserRequest: Codable, Sendable {
    public var id:String; public var op:BrowserOperation; public var links:[BrowserLink]?; public var streamID:String?; public var sequence:Int?; public var data:String?; public var totalBytes:Int64?
    public init(id:String, op:BrowserOperation, links:[BrowserLink]? = nil, streamID:String? = nil, sequence:Int? = nil, data:String? = nil, totalBytes:Int64? = nil) { self.id=id;self.op=op;self.links=links;self.streamID=streamID;self.sequence=sequence;self.data=data;self.totalBytes=totalBytes }
    public func validate() throws {
        guard UUID(uuidString:id) != nil, totalBytes == nil || totalBytes! >= 0 else { throw BrowserProtocolError.invalid }
        switch op {
        case .ping: break
        case .download,.batch,.blobBegin:
            guard let links, !links.isEmpty, links.count <= (op == .batch ? 200 : 1) else { throw BrowserProtocolError.invalid }
            for link in links { try link.validate(allowBlob:op == .blobBegin) }
            if op == .blobBegin { guard links[0].url.hasPrefix("blob:") else { throw BrowserProtocolError.invalid } }
        case .blobChunk,.blobFinish,.blobAbort:
            guard let streamID, UUID(uuidString:streamID) != nil else { throw BrowserProtocolError.invalid }
            if op == .blobChunk { guard let sequence, sequence >= 0, let data, data.utf8.count <= 174764, let bytes=Data(base64Encoded:data), bytes.count <= 131072, bytes.base64EncodedString() == data else { throw BrowserProtocolError.invalid } }
        }
    }
}
public struct BrowserResponse: Codable, Sendable {
    public var id:String; public var status:String; public var message:String?; public var jobID:String?; public var streamID:String?; public var sha256:String?
    public init(id:String,status:String,message:String? = nil,jobID:String? = nil,streamID:String? = nil,sha256:String? = nil) { self.id=id;self.status=status;self.message=message;self.jobID=jobID;self.streamID=streamID;self.sha256=sha256 }
}
public struct BrowserEnvelope: Codable, Sendable { public var token:String; public var request:BrowserRequest; public init(token:String,request:BrowserRequest) { self.token=token;self.request=request } }
public struct BrowserBridgeConfiguration: Codable, Sendable {
    public var port:UInt16; public var token:String
    public init(port:UInt16,token:String) { self.port=port;self.token=token }
    public static var defaultURL:URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacDownloadManager/browser-bridge.json") }
}
public enum NativeMessageFrame {
    public static let maximumBytes = 1024*1024
    public static func encode(_ data:Data) throws -> Data { guard data.count > 0, data.count <= maximumBytes else { throw BrowserProtocolError.invalid }; var n=UInt32(data.count).littleEndian; var out=withUnsafeBytes(of:&n) { Data($0) }; out.append(data);return out }
    public static func extract(buffer:inout Data) throws -> Data? {
        guard buffer.count >= 4 else { return nil }; let n=buffer.prefix(4).enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << (8*$1.offset)) }
        guard n > 0, n <= maximumBytes else { throw BrowserProtocolError.invalid }; guard buffer.count >= 4+Int(n) else { return nil }
        let result=Data(buffer.dropFirst(4).prefix(Int(n)));buffer.removeFirst(4+Int(n));return result
    }
    public static func read(from handle:FileHandle) throws -> Data? {
        var buffer=Data()
        while buffer.count < 4 { guard let part=try handle.read(upToCount:4-buffer.count), !part.isEmpty else { if buffer.isEmpty { return nil };throw BrowserProtocolError.invalid };buffer.append(part) }
        let n=buffer.enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << (8*$1.offset)) }; guard n > 0,n <= maximumBytes else { throw BrowserProtocolError.invalid }
        while buffer.count < Int(n)+4 { guard let part=try handle.read(upToCount:Int(n)+4-buffer.count),!part.isEmpty else { throw BrowserProtocolError.invalid };buffer.append(part) }
        return try extract(buffer:&buffer)
    }
}
