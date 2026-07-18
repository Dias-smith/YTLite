import Foundation

/// One stream variant from an HLS master playlist (`#EXT-X-STREAM-INF`).
struct HLSVariant: Identifiable, Hashable, Sendable {
    let id: String
    let url: URL
    let width: Int
    let height: Int
    let bandwidth: Int
    let frameRate: Double?

    var displayLabel: String {
        if height > 0 { return "\(height)p" }
        if bandwidth > 0 {
            let mbps = Double(bandwidth) / 1_000_000
            return String(format: "%.1f Mbps", mbps)
        }
        return "Stream"
    }
}

enum HLSMasterPlaylistParser {
    /// Parse master playlist text. Returns empty for media playlists (no STREAM-INF).
    static func parse(playlist: String, baseURL: URL) -> [HLSVariant] {
        let lines = playlist
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var variants: [HLSVariant] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            guard line.hasPrefix("#EXT-X-STREAM-INF:") else { continue }
            let attrs = parseAttributes(String(line.dropFirst("#EXT-X-STREAM-INF:".count)))
            // Skip URI attribute on same line; next non-comment line is the playlist URI.
            var uriLine: String?
            while index < lines.count {
                let next = lines[index]
                index += 1
                if next.isEmpty { continue }
                if next.hasPrefix("#") { continue }
                uriLine = next
                break
            }
            guard let uriLine,
                  let url = resolveURL(uriLine, baseURL: baseURL)
            else { continue }

            let resolution = parseResolution(attrs["RESOLUTION"])
            let bandwidth = Int(attrs["BANDWIDTH"] ?? attrs["AVERAGE-BANDWIDTH"] ?? "") ?? 0
            let frameRate = Double(attrs["FRAME-RATE"] ?? "")
            let height = resolution.height
            let width = resolution.width
            let id = "\(height)x\(width)_\(bandwidth)_\(url.lastPathComponent)"
            variants.append(
                HLSVariant(
                    id: id,
                    url: url,
                    width: width,
                    height: height,
                    bandwidth: bandwidth,
                    frameRate: frameRate
                )
            )
        }

        // Highest resolution first; same height keeps highest bandwidth.
        var bestByHeight: [Int: HLSVariant] = [:]
        var unordered: [HLSVariant] = []
        for variant in variants {
            if variant.height <= 0 {
                unordered.append(variant)
                continue
            }
            if let existing = bestByHeight[variant.height] {
                if variant.bandwidth > existing.bandwidth {
                    bestByHeight[variant.height] = variant
                }
            } else {
                bestByHeight[variant.height] = variant
            }
        }
        let ordered = bestByHeight.values.sorted {
            if $0.height != $1.height { return $0.height > $1.height }
            return $0.bandwidth > $1.bandwidth
        }
        return ordered + unordered.sorted { $0.bandwidth > $1.bandwidth }
    }

    // MARK: - Attribute helpers

    private static func parseAttributes(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        var i = raw.startIndex
        while i < raw.endIndex {
            while i < raw.endIndex, raw[i] == " " || raw[i] == "," {
                i = raw.index(after: i)
            }
            guard i < raw.endIndex else { break }
            guard let eq = raw[i...].firstIndex(of: "=") else { break }
            let key = String(raw[i..<eq]).trimmingCharacters(in: .whitespaces)
            i = raw.index(after: eq)
            guard i < raw.endIndex else { break }
            let value: String
            if raw[i] == "\"" {
                i = raw.index(after: i)
                var buf = ""
                while i < raw.endIndex, raw[i] != "\"" {
                    buf.append(raw[i])
                    i = raw.index(after: i)
                }
                if i < raw.endIndex { i = raw.index(after: i) }
                value = buf
            } else {
                var buf = ""
                while i < raw.endIndex, raw[i] != "," {
                    buf.append(raw[i])
                    i = raw.index(after: i)
                }
                value = buf.trimmingCharacters(in: .whitespaces)
            }
            if !key.isEmpty { result[key.uppercased()] = value }
        }
        return result
    }

    private static func parseResolution(_ value: String?) -> (width: Int, height: Int) {
        guard let value else { return (0, 0) }
        let parts = value.split(separator: "x")
        guard parts.count == 2,
              let w = Int(parts[0]),
              let h = Int(parts[1])
        else { return (0, 0) }
        return (w, h)
    }

    private static func resolveURL(_ uri: String, baseURL: URL) -> URL? {
        if let absolute = URL(string: uri), absolute.scheme != nil {
            return absolute
        }
        return URL(string: uri, relativeTo: baseURL)?.absoluteURL
    }

    #if DEBUG
    /// Lightweight self-check for master playlist parsing (no XCTest target).
    static func debugSelfCheck() {
        let master = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
        360p.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720
        https://cdn.example.com/live/720p.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720
        720p-low.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,FRAME-RATE=30.000
        /path/1080p.m3u8
        """
        let base = URL(string: "https://cdn.example.com/live/master.m3u8")!
        let variants = parse(playlist: master, baseURL: base)
        assert(variants.count == 3, "expected 3 unique heights, got \(variants.count)")
        assert(variants[0].height == 1080)
        assert(variants[1].height == 720)
        assert(variants[1].bandwidth == 2_500_000, "keep highest bandwidth for 720p")
        assert(variants[1].url.absoluteString == "https://cdn.example.com/live/720p.m3u8")
        assert(variants[2].url.absoluteString == "https://cdn.example.com/live/360p.m3u8")
        let mediaOnly = parse(playlist: "#EXTM3U\n#EXTINF:4,\nseg.ts\n", baseURL: base)
        assert(mediaOnly.isEmpty)
        PlayProbe.log("hls.parser.selfCheck", videoId: nil, "ok variants=\(variants.count)")
    }
    #endif
}
