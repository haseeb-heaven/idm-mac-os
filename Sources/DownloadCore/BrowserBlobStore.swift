import Foundation
import CryptoKit
import Darwin
public struct BrowserBlobResult: Sendable { public let destination:URL; public let bytes:Int64; public let sha256:String }
public final class BrowserBlobStore {
    public static let maximumChunkBytes=128*1024
    public static let maximumSessions=4
    private struct Session { let destination:URL;let staging:URL;let handle:FileHandle;let expected:Int64?;var sequence=0;var bytes:Int64=0;var hash=SHA256() }
    private var sessions:[UUID:Session]=[:]
    public init() {}
    deinit { for s in sessions.values { try? s.handle.close();try? FileManager.default.removeItem(at:s.staging) } }
    public func begin(destination:URL,expectedBytes:Int64? = nil) throws -> UUID {
        guard destination.isFileURL, sessions.count < Self.maximumSessions, expectedBytes == nil || expectedBytes! >= 0 else { throw BrowserProtocolError.invalid }
        guard !FileManager.default.fileExists(atPath:destination.path) else { throw DownloadError.destinationExists }
        let id=UUID(), staging=destination.deletingLastPathComponent().appendingPathComponent(".mdm-blob-\(id).part")
        let fd=Darwin.open(staging.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600);guard fd >= 0 else { throw DownloadError.storage("Cannot create blob staging file") }
        sessions[id]=Session(destination:destination,staging:staging,handle:FileHandle(fileDescriptor:fd,closeOnDealloc:true),expected:expectedBytes);return id
    }
    public func append(id:UUID,sequence:Int,data:Data) throws -> Int64 {
        guard var s=sessions[id],sequence == s.sequence,data.count <= Self.maximumChunkBytes, Int64(data.count) <= Int64.max-s.bytes else { throw BrowserProtocolError.invalid }
        let count=s.bytes+Int64(data.count);guard s.expected == nil || count <= s.expected! else { throw BrowserProtocolError.invalid }
        try s.handle.write(contentsOf:data);s.hash.update(data:data);s.bytes=count;s.sequence += 1;sessions[id]=s;return count
    }
    public func finish(id:UUID,expectedBytes:Int64? = nil) throws -> BrowserBlobResult {
        guard let s=sessions[id], expectedBytes == nil || expectedBytes! == s.bytes, s.expected == nil || s.expected! == s.bytes else { throw BrowserProtocolError.invalid }
        try s.handle.synchronize();try s.handle.close()
        // link is atomic and refuses collisions; staging and destination share a filesystem.
        guard Darwin.link(s.staging.path,s.destination.path) == 0 else { throw DownloadError.destinationExists }
        try FileManager.default.removeItem(at:s.staging);sessions.removeValue(forKey:id)
        return BrowserBlobResult(destination:s.destination,bytes:s.bytes,sha256:s.hash.finalize().map { String(format:"%02x",$0) }.joined())
    }
    public func abort(id:UUID) { guard let s=sessions.removeValue(forKey:id) else { return };try? s.handle.close();try? FileManager.default.removeItem(at:s.staging) }
}
