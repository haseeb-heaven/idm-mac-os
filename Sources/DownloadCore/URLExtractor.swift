import Foundation

public struct ParsedDownloadRequest: Sendable, Equatable {
    public let url: URL
    public let suggestedFilename: String?
    public let username: String?
    public let password: String?
    public let headers: [String: String]

    public init(
        url: URL,
        suggestedFilename: String? = nil,
        username: String? = nil,
        password: String? = nil,
        headers: [String: String] = [:]
    ) {
        self.url = url
        self.suggestedFilename = suggestedFilename
        self.username = username
        self.password = password
        self.headers = headers
    }
}

public enum URLExtractor {
    /// Extracts a structured download request from a raw URL, or shell commands like:
    /// - `curl -fsSL https://openigi.com/install.sh | bash`
    /// - `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/...)"`
    /// - `wget -O output.zip https://example.com/file.zip`
    /// - `curl -u admin:pass -H "Auth: Token" https://example.com/file`
    public static func extract(from input: String) -> ParsedDownloadRequest? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var suggestedFilename: String? = nil
        var username: String? = nil
        var password: String? = nil
        var headers: [String: String] = [:]

        // 1. Extract suggested output filename from -o or -O flag
        // e.g. -o filename or --output filename or -O filename (in wget)
        if let outMatch = matchRegex(pattern: #"(?:^|\s)(?:-o|--output|-O)\s+["']?([^"'\s|&;]+)["']?"#, in: trimmed) {
            suggestedFilename = outMatch
        }

        // 2. Extract credentials from -u user:pass or --user user:pass
        if let creds = matchRegex(pattern: #"(?:^|\s)(?:-u|--user)\s+["']?([^"'\s:]+):([^"'\s]+)["']?"#, in: trimmed, groups: [1, 2]),
           creds.count >= 2 {
            username = creds[0]
            password = creds[1]
        }

        // 3. Extract custom headers from -H "Key: Value" or --header "Key: Value"
        let headerMatches = matchAllRegex(pattern: #"(?:-H|--header)\s+["']([^"']+)["']"#, in: trimmed)
        for h in headerMatches {
            let parts = h.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                headers[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }

        // 4. Extract the target HTTP/HTTPS URL
        if let urlString = findHTTPURL(in: trimmed) {
            if let valid = normalizeURL(urlString) {
                return ParsedDownloadRequest(
                    url: valid,
                    suggestedFilename: suggestedFilename,
                    username: username,
                    password: password,
                    headers: headers
                )
            }
        }

        // 5. Fallback: Extract bare domain with path (e.g. "openigi.com/install.sh" or "curl openigi.com/install.sh")
        if let domainString = findDomainURL(in: trimmed, ignoring: suggestedFilename) {
            if let valid = normalizeURL("https://" + domainString) {
                return ParsedDownloadRequest(
                    url: valid,
                    suggestedFilename: suggestedFilename,
                    username: username,
                    password: password,
                    headers: headers
                )
            }
        }

        return nil
    }

    /// Shorthand to extract just the target URL.
    public static func extractURL(from input: String) -> URL? {
        return extract(from: input)?.url
    }

    private static func findHTTPURL(in text: String) -> String? {
        let pattern = #"https?://[^\s"'`<>|\)]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard let range = match?.range else { return nil }
        var result = ns.substring(with: range)

        // Strip trailing punctuation / closing brackets from shell commands
        while let last = result.last, [")", "]", "}", "'", "\"", ">", ",", ";"].contains(last) {
            result.removeLast()
        }
        return result
    }

    private static func findDomainURL(in text: String, ignoring: String? = nil) -> String? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["/bin/bash -c", "/bin/sh -c", "bash -c", "sh -c", "curl", "wget"] {
            if s.lowercased().hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let pattern = #"(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}(?:/[^\s"'`<>|\)]*)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = s as NSString
        let matches = regex.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))

        // First pass: look for matches containing a path '/'
        for match in matches {
            var candidate = ns.substring(with: match.range)
            while let last = candidate.last, [")", "]", "}", "'", "\"", ">", ",", ";", "."].contains(last) {
                candidate.removeLast()
            }
            if let ignoring, candidate == ignoring { continue }
            if candidate.contains("/") {
                return candidate
            }
        }

        // Second pass: any valid domain match that is not the ignored filename or a plain script filename
        for match in matches {
            var candidate = ns.substring(with: match.range)
            while let last = candidate.last, [")", "]", "}", "'", "\"", ">", ",", ";", "."].contains(last) {
                candidate.removeLast()
            }
            if let ignoring, candidate == ignoring { continue }
            let ext = (candidate as NSString).pathExtension.lowercased()
            if ["sh", "bash", "zsh", "py", "js", "tar", "gz", "zip", "exe"].contains(ext) && !candidate.contains("/") {
                continue
            }
            return candidate
        }

        return nil
    }

    private static func normalizeURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let host = url.host,
              !host.isEmpty,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        return url
    }

    private static func matchRegex(pattern: String, in text: String, groups: [Int] = [1]) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        var res = [String]()
        for g in groups {
            if g < match.numberOfRanges {
                res.append(ns.substring(with: match.range(at: g)))
            }
        }
        return res.isEmpty ? nil : res
    }

    private static func matchRegex(pattern: String, in text: String) -> String? {
        return matchRegex(pattern: pattern, in: text, groups: [1])?.first
    }

    private static func matchAllRegex(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { m in
            m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : nil
        }
    }
}
