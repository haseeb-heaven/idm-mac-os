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
        let html = String(decoding:data,as:UTF8.self)
        let regex = try NSRegularExpression(pattern:#"(?i)(?:href|src)\s*=\s*["']([^"']+)["']"#)
        let extensions:Set<String> = ["zip","7z","rar","gz","tar","pdf","mp3","m4a","mp4","mkv","mov","webm","exe","dmg","pkg","iso","epub","doc","docx","png","jpg","jpeg"]
        var seen = Set<URL>(); var links = [URL]()
        for match in regex.matches(in:html,range:NSRange(html.startIndex...,in:html)) {
            guard let range = Range(match.range(at:1),in:html), let candidate = URL(string:String(html[range]).replacingOccurrences(of:"&amp;",with:"&"),relativeTo:response.url ?? url)?.absoluteURL,
                  ["http","https"].contains(candidate.scheme ?? ""),candidate.user == nil,extensions.contains(candidate.pathExtension.lowercased()),seen.insert(candidate).inserted else { continue }
            links.append(candidate)
            if links.count == 500 { break }
        }
        return links
    }
}
