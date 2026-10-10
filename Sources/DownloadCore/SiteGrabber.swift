import Foundation

public struct GrabbedItem: Sendable, Hashable, Identifiable {
    public var id: URL { url }
    public let url: URL
    public let filename: String
    public let category: String
    public let fileExtension: String

    public init(url: URL) {
        self.url = url
        let name = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        self.filename = name
        let ext = url.pathExtension.lowercased()
        self.fileExtension = ext.isEmpty ? "—" : ".\(ext)"
        self.category = Self.categorize(url: url)
    }

    public static func categorize(url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "webp", "gif", "svg", "bmp", "ico", "tiff", "tif", "avif", "psd":
            return "Picture"
        case "mp4", "mkv", "mov", "webm", "avi", "wmv", "flv", "m4v", "3gp", "ts", "mpg", "mpeg":
            return "Video"
        case "mp3", "m4a", "flac", "wav", "aac", "ogg", "opus", "wma", "aiff":
            return "Audio"
        case "zip", "7z", "rar", "gz", "tar", "tgz", "bz2", "xz", "zst", "iso", "dmg", "pkg", "deb", "rpm":
            return "Compressed"
        case "pdf", "epub", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "csv", "odt", "ods", "odp":
            return "Document"
        case "exe", "msi", "bin", "apk", "ipa", "run", "sh", "bash", "zsh", "command", "py", "app":
            return "Program"
        default:
            if url.pathComponents.contains(where: { $0.lowercased() == "download" }) {
                return "Compressed"
            }
            return "Other"
        }
    }
}

public enum SiteGrabber {
    private static let extensions: Set<String> = [
        // Archives & Compressed
        "zip", "7z", "rar", "gz", "tar", "tgz", "bz2", "xz", "zst", "iso", "dmg", "pkg", "deb", "rpm", "cab", "msi", "apk", "ipa",
        // Audio
        "mp3", "m4a", "flac", "wav", "aac", "ogg", "opus", "wma", "aiff", "alac", "mid", "midi",
        // Video
        "mp4", "mkv", "mov", "webm", "avi", "wmv", "flv", "m4v", "3gp", "ts", "mpg", "mpeg", "vob",
        // Images / Pictures
        "png", "jpg", "jpeg", "webp", "gif", "svg", "bmp", "ico", "tiff", "tif", "psd", "avif",
        // Documents
        "pdf", "epub", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "txt", "rtf", "csv",
        // Programs & Scripts
        "exe", "bin", "run", "sh", "bash", "zsh", "command", "py", "app"
    ]

    public static func links(on url: URL) async throws -> [URL] {
        return try await fetch(on: url).map(\.url)
    }

    public static func items(on url: URL) async throws -> [GrabbedItem] {
        return try await fetch(on: url)
    }

    public static func fetch(on url: URL) async throws -> [GrabbedItem] {
        guard ["http", "https"].contains(url.scheme ?? ""), url.host != nil, url.user == nil, url.password == nil else {
            throw DownloadError.invalidURL
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DownloadError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        var data = Data()
        for try await byte in bytes {
            if data.count >= 2 * 1024 * 1024 {
                throw DownloadError.storage("Page exceeds the 2 MiB grabber limit")
            }
            data.append(byte)
        }

        var baseURL = response.url ?? url
        var rawCandidates: [(raw: String, isAnchor: Bool, isDownloadAttr: Bool)] = []

        // Attempt 1: Standard XMLDocument HTML parsing
        if let document = try? XMLDocument(data: data, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]) {
            for node in (try? document.nodes(forXPath: "//base/@href")) ?? [] {
                if let val = node.stringValue,
                   let candidate = URL(string: val, relativeTo: baseURL)?.absoluteURL,
                   ["http", "https"].contains(candidate.scheme ?? ""), candidate.host != nil, candidate.user == nil, candidate.password == nil {
                    baseURL = candidate
                    break
                }
            }
            for node in (try? document.nodes(forXPath: "//*[@href and not(self::base)]/@href | //*[@src]/@src")) ?? [] {
                if let val = node.stringValue {
                    let element = node.parent as? XMLElement
                    let isAnchor = element?.name?.lowercased() == "a"
                    let explicitDownload = isAnchor && element?.attribute(forName: "download") != nil
                    rawCandidates.append((val, isAnchor, explicitDownload))
                }
            }
        }

        // Attempt 2: High-speed HTML Regex Scanner fallback (robust against modern/malformed HTML)
        if rawCandidates.isEmpty, let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            let clean = html.replacingOccurrences(of: "(?s)<!--.*?-->", with: "", options: .regularExpression)
            if let baseRange = clean.range(of: "<base[^>]+href=[\"']([^\"']+)[\"']", options: .regularExpression) {
                let tag = String(clean[baseRange])
                if let valRange = tag.range(of: "href=[\"']([^\"']+)[\"']", options: .regularExpression) {
                    let raw = String(tag[valRange]).replacingOccurrences(of: "href=[\"']|[\"']", with: "", options: .regularExpression)
                    if let candidate = URL(string: raw, relativeTo: baseURL)?.absoluteURL,
                       ["http", "https"].contains(candidate.scheme ?? ""), candidate.host != nil, candidate.user == nil, candidate.password == nil {
                        baseURL = candidate
                    }
                }
            }

            let pattern = "(?:href|src|data-src|data-url)=[\"']([^\"'#\\s]+)[\"']"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let ns = clean as NSString
                let matches = regex.matches(in: clean, options: [], range: NSRange(location: 0, length: ns.length))
                for match in matches where match.numberOfRanges > 1 {
                    let val = ns.substring(with: match.range(at: 1))
                    rawCandidates.append((val, true, false))
                }
            }
            // Also scan for direct URLs embedded in text, scripts, or markdown (e.g. bash scripts downloading archives)
            let directUrlPattern = #"https?://[^\s"'`<>|\)]+"#
            if let urlRegex = try? NSRegularExpression(pattern: directUrlPattern, options: .caseInsensitive) {
                let ns = clean as NSString
                let matches = urlRegex.matches(in: clean, options: [], range: NSRange(location: 0, length: ns.length))
                for match in matches {
                    var val = ns.substring(with: match.range)
                    while let last = val.last, [")", "]", "}", "'", "\"", ">", ",", ";"].contains(last) {
                        val.removeLast()
                    }
                    rawCandidates.append((val, true, false))
                }
            }
        }

        var seen = Set<URL>()
        var results = [GrabbedItem]()

        // If the targeted page/URL itself is a downloadable file or script (e.g. .sh, .zip, .dmg, etc.),
        // include it as the first grabbed item:
        let baseExt = baseURL.pathExtension.lowercased()
        if extensions.contains(baseExt) && seen.insert(baseURL).inserted {
            results.append(GrabbedItem(url: baseURL))
        }

        for item in rawCandidates {
            guard let candidate = URL(string: item.raw, relativeTo: baseURL)?.absoluteURL,
                  ["http", "https"].contains(candidate.scheme ?? ""),
                  candidate.host != nil,
                  candidate.user == nil,
                  candidate.password == nil else { continue }

            let ext = candidate.pathExtension.lowercased()
            let isAnchor = item.isAnchor
            let explicitDownload = item.isDownloadAttr
            let downloadEndpoint = isAnchor && candidate.pathComponents.contains(where: { $0.lowercased() == "download" })

            var queryMatches = false
            if ext.isEmpty, let query = candidate.query?.lowercased() {
                for e in extensions {
                    if query.contains(".\(e)") || query.contains("=\(e)") {
                        queryMatches = true
                        break
                    }
                }
            }

            guard extensions.contains(ext) || explicitDownload || downloadEndpoint || queryMatches,
                  seen.insert(candidate).inserted else { continue }

            results.append(GrabbedItem(url: candidate))
            if results.count == 500 { break }
        }

        return results
    }
}
