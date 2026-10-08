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
        var baseURL = response.url ?? url
        let baseTags = try NSRegularExpression(pattern:#"(?i)<base\b[^>]*>"#)
        let href = try NSRegularExpression(pattern:#"(?i)\bhref\s*=\s*["']([^"']+)["']"#)
        for tag in baseTags.matches(in:html,range:NSRange(html.startIndex...,in:html)) {
            guard let tagRange = Range(tag.range,in:html) else { continue }
            let text = String(html[tagRange])
            guard let match = href.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),
                  let value = Range(match.range(at:1),in:text),
                  let candidate = URL(string:String(text[value]).replacingOccurrences(of:"&amp;",with:"&"),relativeTo:baseURL)?.absoluteURL,
                  ["http","https"].contains(candidate.scheme ?? ""),candidate.host != nil,candidate.user == nil else { continue }
            baseURL = candidate;break
        }
        let linkHTML = baseTags.stringByReplacingMatches(in:html,range:NSRange(html.startIndex...,in:html),withTemplate:"")
        let regex = try NSRegularExpression(pattern:#"(?i)(?:href|src)\s*=\s*["']([^"']+)["']"#)
        let extensions:Set<String> = ["zip","7z","rar","gz","tar","pdf","mp3","m4a","mp4","mkv","mov","webm","exe","dmg","pkg","iso","epub","doc","docx","png","jpg","jpeg"]
        var seen = Set<URL>(); var links = [URL]()
        for match in regex.matches(in:linkHTML,range:NSRange(linkHTML.startIndex...,in:linkHTML)) {
            guard let range = Range(match.range(at:1),in:linkHTML), let candidate = URL(string:String(linkHTML[range]).replacingOccurrences(of:"&amp;",with:"&"),relativeTo:baseURL)?.absoluteURL,
                  ["http","https"].contains(candidate.scheme ?? ""),candidate.user == nil,extensions.contains(candidate.pathExtension.lowercased()),seen.insert(candidate).inserted else { continue }
            links.append(candidate)
            if links.count == 500 { break }
        }
        return links
    }
}
