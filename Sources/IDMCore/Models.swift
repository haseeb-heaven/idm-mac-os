import Foundation

public enum JobState: String, Codable, Sendable { case queued, downloading, paused, completed, failed }
public struct DownloadJob: Codable, Identifiable, Sendable {
    public var id: UUID
    public var url: URL
    public var destination: URL
    public var state: JobState = .queued
    public var category: String
    public var totalBytes: Int64 = 0
    public var receivedBytes: Int64 = 0
    public var error: String?
    public var scheduledAt: Date?
    public var createdAt = Date()
    public init(url: URL, destination: URL, scheduledAt: Date? = nil) throws {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
              url.user == nil, url.password == nil else { throw DownloadError.invalidURL }
        guard destination.isFileURL, !destination.lastPathComponent.isEmpty else { throw DownloadError.invalidDestination }
        self.id = UUID(); self.url = url; self.destination = destination; self.scheduledAt = scheduledAt
        let ext = destination.pathExtension.lowercased()
        category = ["mp4","mkv","mov","webm"].contains(ext) ? "Video" : ["mp3","wav","m4a","flac"].contains(ext) ? "Music" : ["zip","gz","7z","rar","tar"].contains(ext) ? "Compressed" : ["pdf","txt","doc","docx"].contains(ext) ? "Documents" : ["exe","dmg","pkg","msi"].contains(ext) ? "Programs" : "Other"
    }
}
public struct DownloadOptions: Codable, Sendable {
    public var connections: Int = 4
    public var chunkBytes: Int64 = 2 * 1024 * 1024
    public var bytesPerSecond: Int64 = 0
    public var retries: Int = 3
    public var useRanges: Bool = true
    public var proxyHost: String?
    public var proxyPort: Int?
    public init() {}
}
public struct TransferProgress: Sendable {
    public var received: Int64
    public var total: Int64
    public init(received: Int64, total: Int64) { self.received = received; self.total = total }
}
public enum DownloadError: Error, LocalizedError, Sendable {
    case invalidURL, invalidDestination, http(Int), invalidRange, rangeUnsupported, browserVerification, webPage, destinationExists, storage(String), changedResource, incomplete
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter an HTTP or HTTPS URL without embedded credentials."
        case .invalidDestination: "Choose a valid destination file."
        case .http(let code): "The server returned HTTP \(code)."
        case .browserVerification: "This website requires browser verification. Open the page in your browser, then copy the direct file download link."
        case .webPage: "This URL points to an HTML page. Copy the direct file download link or use Grabber to find file links."
        case .rangeUnsupported: "The server does not support range requests."
        case .invalidRange: "The server returned an invalid byte range."
        case .destinationExists: "The destination already exists. Choose another filename."
        case .storage(let message): "Storage error: \(message)"
        case .changedResource: "The remote file changed during the download. Restart the download."
        case .incomplete: "The received file length does not match the expected length."
        }
    }
}
