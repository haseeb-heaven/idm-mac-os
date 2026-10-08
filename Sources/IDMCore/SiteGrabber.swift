import Foundation
public enum SiteGrabber {
    public static func links(on url: URL) async throws -> [URL] {
        guard ["http","https"].contains(url.scheme ?? ""), url.host != nil, url.user == nil else { throw DownloadError.invalidURL }
        let session = URLSession(configuration:.ephemeral); defer { session.invalidateAndCancel() }
        let (bytes,response) = try await session.bytes(from:url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw DownloadError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        var data = Data()
        for try await byte in bytes {
            if data.count >= 2*1024*1024 { throw DownloadError.storage("Page exceeds the 2 MiB grabber limit") }
            data.append(byte)
        }
        let document = try XMLDocument(data:data,options:[.documentTidyHTML,.nodeLoadExternalEntitiesNever])
        var baseURL = response.url ?? url
        for node in try document.nodes(forXPath:"//base/@href") {
            guard let value = node.stringValue,
                  let candidate = URL(string:value,relativeTo:baseURL)?.absoluteURL,
                  ["http","https"].contains(candidate.scheme ?? ""),candidate.host != nil,candidate.user == nil else { continue }
            baseURL = candidate;break
        }
        let extensions:Set<String> = ["zip","7z","rar","gz","tar","pdf","mp3","m4a","mp4","mkv","mov","webm","exe","dmg","pkg","iso","epub","doc","docx","png","jpg","jpeg"]
        var seen = Set<URL>(); var links = [URL]()
        for node in try document.nodes(forXPath:"//*[@href and not(self::base)]/@href | //*[@src]/@src") {
            guard let value = node.stringValue, let candidate = URL(string:value,relativeTo:baseURL)?.absoluteURL,
                  ["http","https"].contains(candidate.scheme ?? ""),candidate.user == nil,extensions.contains(candidate.pathExtension.lowercased()),seen.insert(candidate).inserted else { continue }
            links.append(candidate)
            if links.count == 500 { break }
        }
        return links
    }
}
