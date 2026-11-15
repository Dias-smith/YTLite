import Foundation

struct WebDAVEntry: Identifiable, Hashable, Sendable {
    var id: String { href }
    let href: String
    let displayName: String
    let isCollection: Bool
    let contentLength: Int64?
}

enum WebDAVClientError: LocalizedError {
    case badURL
    case httpStatus(Int)
    case parse

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid WebDAV URL"
        case .httpStatus(let code): return "WebDAV HTTP \(code)"
        case .parse: return "Could not parse WebDAV response"
        }
    }
}

actor WebDAVClient {
    let baseURL: URL
    let username: String
    let password: String

    init(baseURL: URL, username: String, password: String) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
    }

    func list(path: String) async throws -> [WebDAVEntry] {
        let url = join(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
        <?xml version="1.0"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:displayname/>
            <d:resourcetype/>
            <d:getcontentlength/>
          </d:prop>
        </d:propfind>
        """.utf8)
        applyAuth(&request)
        // Depth 1 for children
        request.setValue("1", forHTTPHeaderField: "Depth")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw WebDAVClientError.httpStatus(code) }
        return try parsePropfind(data)
    }

    func download(path: String) async throws -> Data {
        let url = join(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw WebDAVClientError.httpStatus(code) }
        return data
    }

    /// Resolve a PROPFIND href / browse path against `baseURL` without double-encoding.
    /// rclone / Synology often return already percent-encoded absolute paths (e.g. `/%E5%8D%8A.mp4`).
    private func join(_ path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "/" {
            return baseURL
        }

        if let absolute = URL(string: trimmed),
           let scheme = absolute.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return absolute
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }

        let decoded = trimmed.removingPercentEncoding ?? trimmed
        let resolvedPath: String
        if decoded.hasPrefix("/") {
            resolvedPath = decoded
        } else {
            var basePath = components.path
            if basePath.isEmpty { basePath = "/" }
            if !basePath.hasSuffix("/") { basePath += "/" }
            resolvedPath = basePath + decoded
        }

        components.percentEncodedPath = Self.percentEncodePath(resolvedPath)
        return components.url ?? baseURL
    }

    private static func percentEncodePath(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
            .joined(separator: "/")
    }

    private func applyAuth(_ request: inout URLRequest) {
        let raw = "\(username):\(password)"
        let b64 = Data(raw.utf8).base64EncodedString()
        request.setValue("Basic \(b64)", forHTTPHeaderField: "Authorization")
    }

    private func parsePropfind(_ data: Data) throws -> [WebDAVEntry] {
        guard let xml = String(data: data, encoding: .utf8) else { throw WebDAVClientError.parse }
        var entries: [WebDAVEntry] = []
        // Lightweight scrape — sufficient for Synology / Nutstore / many NAS.
        var chunks: [String] = []
        for sep in ["<d:response", "<D:response", "<response"] {
            let parts = xml.components(separatedBy: sep)
            if parts.count > 1 {
                chunks.append(contentsOf: parts.dropFirst())
            }
        }
        var seen = Set<String>()
        for chunk in chunks {
            guard let href = firstTag(chunk, names: ["d:href", "D:href", "href"]),
                  !href.isEmpty,
                  !seen.contains(href)
            else { continue }
            seen.insert(href)
            let name = firstTag(chunk, names: ["d:displayname", "D:displayname", "displayname"])
                ?? URL(string: href.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? href)?.lastPathComponent
                ?? href
            let isCollection = chunk.lowercased().contains("collection")
            let lengthText = firstTag(chunk, names: ["d:getcontentlength", "D:getcontentlength", "getcontentlength"])
            let length = lengthText.flatMap(Int64.init)
            entries.append(
                WebDAVEntry(
                    href: href,
                    displayName: name.removingPercentEncoding ?? name,
                    isCollection: isCollection,
                    contentLength: length
                )
            )
        }
        // Drop the root itself when listing children
        if entries.count > 1 {
            return Array(entries.dropFirst())
        }
        return entries
    }

    private func firstTag(_ xml: String, names: [String]) -> String? {
        for name in names {
            let open = "<\(name)>"
            let close = "</\(name)>"
            guard let s = xml.range(of: open, options: .caseInsensitive),
                  let e = xml.range(of: close, options: .caseInsensitive, range: s.upperBound..<xml.endIndex)
            else { continue }
            return String(xml[s.upperBound..<e.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
