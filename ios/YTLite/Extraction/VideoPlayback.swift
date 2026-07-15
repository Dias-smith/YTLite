import Foundation

struct StreamFormat: Identifiable, Sendable, Equatable {
    var id: Int { itag }
    let itag: Int
    let url: URL
    let mimeType: String
    let width: Int
    let height: Int
    let acodec: String
    let vcodec: String

    var isAudioOnly: Bool {
        !acodec.isEmpty && acodec != "none" && (vcodec.isEmpty || vcodec == "none")
    }

    var isMuxed: Bool {
        !acodec.isEmpty && acodec != "none" && !vcodec.isEmpty && vcodec != "none"
    }
}

struct VideoPlayback: Sendable, Equatable {
    let videoId: String
    let title: String
    let channelName: String
    /// YouTube channel id (e.g. `UC…`) when extract provides it — Android `channelID`.
    let channelId: String?
    let durationSeconds: Int
    let formats: [StreamFormat]
    let thumbnailURL: URL?
    let captionTracks: [CaptionTrack]

    func preferredStreamURL(preferVideo: Bool = true) -> URL? {
        PlaybackFormatSelector.select(formats: formats, preferVideo: preferVideo)?.url
    }
}

enum PlaybackFormatSelector {
    static func select(formats: [StreamFormat], preferVideo: Bool) -> StreamFormat? {
        if preferVideo {
            for itag in YouTubeConstants.preferredVideoItags {
                if let hit = formats.first(where: { $0.itag == itag }) { return hit }
            }
            if let muxed = formats.filter(\.isMuxed).max(by: { $0.height < $1.height }) {
                return muxed
            }
            return formats.first { !$0.isAudioOnly } ?? formats.first
        } else {
            for itag in YouTubeConstants.preferredAudioItags {
                if let hit = formats.first(where: { $0.itag == itag }) { return hit }
            }
            return formats.first(where: \.isAudioOnly) ?? formats.first
        }
    }
}

enum ExtractResultMapper {
    static func map(envelope: [String: Any], fallbackVideoId: String) throws -> VideoPlayback {
        guard let data = envelope["data"] as? [String: Any] else {
            throw ExtractorBridge.ExtractorError.invalidResponse("missing data")
        }
        // extractor.js `createExtractMsg` always sets success:true; real failures land in
        // errorMsg / music:null (same as Android JsResultMapper.playbackErrorMessage).
        let topError = stringValue(data["errorMsg"]).nilIfEmpty
            ?? stringValue(data["errorMSG"]).nilIfEmpty
        let explicitFail = (data["success"] as? Bool) == false
        if explicitFail {
            throw ExtractorBridge.ExtractorError.extractFailed(
                topError ?? "extract failed"
            )
        }
        guard let payload = data["data"] as? [String: Any] else {
            throw ExtractorBridge.ExtractorError.invalidResponse(
                topError ?? "missing payload"
            )
        }
        let nestedError = stringValue(payload["errMsg"]).nilIfEmpty
            ?? stringValue(payload["errorMSG"]).nilIfEmpty
            ?? stringValue(payload["errorMsg"]).nilIfEmpty
            ?? topError
        let music = payload["music"] as? [String: Any]
        guard let music else {
            let msg = (nestedError ?? "Unable to extract playable stream")
                .replacingOccurrences(of: "__notRetry@", with: "")
            throw ExtractorBridge.ExtractorError.extractFailed(msg)
        }
        let rawFormats = music["formats"] as? [[String: Any]] ?? []
        let formats: [StreamFormat] = rawFormats.compactMap { item in
            guard let urlString = item["url"] as? String,
                  let url = URL(string: urlString),
                  !urlString.isEmpty
            else { return nil }
            let itag = intValue(item["itag"]) ?? 0
            let mime = (item["type"] as? String)
                ?? (item["mimeType"] as? String)
                ?? ""
            return StreamFormat(
                itag: itag,
                url: url,
                mimeType: mime,
                width: intValue(item["width"]) ?? 0,
                height: intValue(item["height"]) ?? 0,
                acodec: stringValue(item["acodec"]),
                vcodec: stringValue(item["vcodec"])
            )
        }
        guard !formats.isEmpty else {
            let msg = (nestedError ?? "no formats with url")
                .replacingOccurrences(of: "__notRetry@", with: "")
            throw ExtractorBridge.ExtractorError.extractFailed(msg)
        }

        let videoId = stringValue(music["videoId"]).nilIfEmpty
            ?? extractVideoId(from: stringValue(payload["url"]))
            ?? fallbackVideoId
        let title = stringValue(music["title"]).nilIfEmpty ?? videoId
        let channel = stringValue(music["uploader"]).nilIfEmpty
            ?? stringValue(music["channel"]).nilIfEmpty
            ?? ""
        let channelId = stringValue(music["channelID"]).nilIfEmpty
            ?? stringValue(music["channelId"]).nilIfEmpty
            ?? stringValue(music["uploader_id"]).nilIfEmpty
            ?? channelId(fromUploaderURL: stringValue(music["uploader_url"]).nilIfEmpty
                ?? stringValue(music["channel_url"]).nilIfEmpty)
        let duration = intValue(music["duration"]) ?? 0
        let thumb = URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg")
        let captions = mapCaptions(music)

        return VideoPlayback(
            videoId: videoId,
            title: title,
            channelName: channel,
            channelId: channelId,
            durationSeconds: duration,
            formats: formats,
            thumbnailURL: thumb,
            captionTracks: captions
        )
    }

    private static func channelId(fromUploaderURL urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if let idx = parts.firstIndex(of: "channel"), parts.indices.contains(idx + 1) {
            let id = parts[idx + 1]
            return id.hasPrefix("UC") ? id : nil
        }
        return nil
    }

    private static func mapCaptions(_ music: [String: Any]) -> [CaptionTrack] {
        var byCode: [String: CaptionTrack] = [:]
        collectCaptionMap(music["subtitles"] as? [String: Any], into: &byCode, isAuto: false)
        collectCaptionMap(music["automatic_captions"] as? [String: Any], into: &byCode, isAuto: true)
        if let arr = music["captionTracks"] as? [[String: Any]] {
            for track in arr {
                let base = stringValue(track["baseUrl"]).nilIfEmpty
                    ?? stringValue(track["url"]).nilIfEmpty
                guard let base else { continue }
                var code = stringValue(track["languageCode"])
                if code.isEmpty {
                    code = stringValue(track["vssId"]).replacingOccurrences(of: ".", with: "")
                }
                if code.isEmpty { code = "und" }
                let nameDict = track["name"] as? [String: Any]
                let display = stringValue(nameDict?["simpleText"]).nilIfEmpty
                    ?? stringValue(track["name"]).nilIfEmpty
                    ?? code
                if byCode[code] == nil {
                    byCode[code] = CaptionTrack(
                        languageCode: code,
                        displayName: display,
                        baseURL: base,
                        isAutoGenerated: track["kind"] as? String == "asr"
                            || (track["isTranslatable"] as? Bool ?? false)
                    )
                }
            }
        }
        return Array(byCode.values)
    }

    private static func collectCaptionMap(
        _ map: [String: Any]?,
        into out: inout [String: CaptionTrack],
        isAuto: Bool
    ) {
        guard let map else { return }
        for (code, value) in map {
            guard let entries = value as? [[String: Any]] else { continue }
            for entry in entries {
                let url = stringValue(entry["url"])
                guard !url.isEmpty else { continue }
                let display = stringValue(entry["name"]).nilIfEmpty ?? code
                if out[code] == nil {
                    out[code] = CaptionTrack(
                        languageCode: code,
                        displayName: display,
                        baseURL: url,
                        isAutoGenerated: isAuto
                    )
                }
            }
        }
    }

    private static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }

    private static func stringValue(_ any: Any?) -> String {
        switch any {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return ""
        }
    }

    private static func extractVideoId(from url: String?) -> String? {
        guard let url else { return nil }
        return YouTubeURL.videoId(from: url)
    }
}

/// When InnerTube clients return UNPLAYABLE, scrape `ytInitialPlayerResponse` from
/// the public watch HTML page (often still has progressive itag 18 URLs).
enum WatchPagePlayerFallback {
    static func extract(videoId: String) async throws -> VideoPlayback {
        let id = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw ExtractorBridge.ExtractorError.invalidResponse("empty videoId")
        }
        // Normalize Shorts → watch before scraping (never hit /shorts/{id}).
        let pages = [
            YouTubeURL.canonicalWatchURL(YouTubeURL.watchURL(videoId: id)),
            YouTubeURL.canonicalWatchURL("https://m.youtube.com/watch?v=\(id)"),
        ]
        var lastError: Error = ExtractorBridge.ExtractorError.extractFailed("unplayable")
        for pageURL in pages {
            do {
                let html = try await fetchHTML(pageURL)
                guard let player = extractPlayerResponseJSON(from: html) else {
                    continue
                }
                return try mapPlayerResponse(player, fallbackVideoId: id)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func fetchHTML(_ url: String) async throws -> String {
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "GET",
            headers: [
                "User-Agent":
                    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 "
                    + "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
                "Accept-Language": "en-US,en;q=0.9",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            ],
            body: nil
        )
        guard result.success, !result.body.isEmpty else {
            throw ExtractorBridge.ExtractorError.extractFailed(
                result.errMsg.isEmpty ? "watch page fetch failed" : result.errMsg
            )
        }
        return result.body
    }

    /// Locates `ytInitialPlayerResponse = {...}` (skips `= null` stubs).
    private static func extractPlayerResponseJSON(from html: String) -> [String: Any]? {
        let marker = "ytInitialPlayerResponse = "
        var searchStart = html.startIndex
        while let markerRange = html.range(of: marker, range: searchStart..<html.endIndex) {
            let after = html[markerRange.upperBound...]
              .drop(while: { $0.isWhitespace || $0 == "\n" || $0 == "\r" })
            if after.hasPrefix("null") {
                searchStart = markerRange.upperBound
                continue
            }
            guard after.first == "{" else {
                searchStart = markerRange.upperBound
                continue
            }
            let braceIndex = after.startIndex
            // Map into full-string index
            let absoluteBrace = braceIndex
            if let jsonText = extractBalancedObject(from: html, startingAt: absoluteBrace),
               let data = jsonText.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               obj["videoDetails"] != nil || obj["streamingData"] != nil
            {
                return obj
            }
            searchStart = markerRange.upperBound
        }
        return nil
    }

    private static func extractBalancedObject(from text: String, startingAt start: String.Index) -> String? {
        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        while i < text.endIndex {
            let ch = text[i]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                switch ch {
                case "\"":
                    inString = true
                case "{":
                    depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...i])
                    }
                default:
                    break
                }
            }
            i = text.index(after: i)
        }
        return nil
    }

    private static func mapPlayerResponse(_ player: [String: Any], fallbackVideoId: String) throws -> VideoPlayback {
        let status = ((player["playabilityStatus"] as? [String: Any])?["status"] as? String)?
            .uppercased() ?? ""
        guard status == "OK" || status.isEmpty else {
            let reason = ((player["playabilityStatus"] as? [String: Any])?["reason"] as? String)?
                .nilIfEmpty
            throw ExtractorBridge.ExtractorError.extractFailed(reason ?? status.lowercased())
        }

        let streaming = player["streamingData"] as? [String: Any] ?? [:]
        let formatsRaw = (streaming["formats"] as? [[String: Any]] ?? [])
            + (streaming["adaptiveFormats"] as? [[String: Any]] ?? [])
        let formats: [StreamFormat] = formatsRaw.compactMap { item in
            guard let urlString = (item["url"] as? String)?.nilIfEmpty,
                  let url = URL(string: urlString.youtubeUnescaped)
            else { return nil }
            let mime = (item["mimeType"] as? String) ?? (item["type"] as? String) ?? ""
            let codecs = mimeCodecs(mime)
            let hasAudio = codecs.contains(where: { $0.hasPrefix("mp4a") || $0.hasPrefix("opus") || $0.hasPrefix("aac") })
                || mime.contains("audio/")
                || item["audioQuality"] != nil
                || item["audioSampleRate"] != nil
            let hasVideo = codecs.contains(where: { $0.hasPrefix("avc") || $0.hasPrefix("vp9") || $0.hasPrefix("av01") || $0.hasPrefix("hev") })
                || mime.contains("video/")
                || ((item["width"] as? Int) ?? 0) > 0
                || ((item["height"] as? Int) ?? 0) > 0
            return StreamFormat(
                itag: intValue(item["itag"]) ?? 0,
                url: url,
                mimeType: mime,
                width: intValue(item["width"]) ?? 0,
                height: intValue(item["height"]) ?? 0,
                acodec: hasAudio ? (codecs.first(where: { $0.hasPrefix("mp4a") || $0.hasPrefix("opus") }) ?? "audio") : "none",
                vcodec: hasVideo ? (codecs.first(where: { $0.hasPrefix("avc") || $0.hasPrefix("vp9") || $0.hasPrefix("av01") }) ?? "video") : "none"
            )
        }
        guard !formats.isEmpty else {
            throw ExtractorBridge.ExtractorError.extractFailed("watch page: no formats with url")
        }

        let details = player["videoDetails"] as? [String: Any] ?? [:]
        let videoId = (details["videoId"] as? String)?.nilIfEmpty ?? fallbackVideoId
        let title = (details["title"] as? String)?.nilIfEmpty ?? videoId
        let micro = (player["microformat"] as? [String: Any])
            .flatMap { $0["playerMicroformatRenderer"] as? [String: Any] }
        let channel = (details["author"] as? String)?.nilIfEmpty
            ?? (micro?["ownerChannelName"] as? String)?.nilIfEmpty
            ?? ""
        let channelId = (details["channelId"] as? String)?.nilIfEmpty
        let duration = intValue(details["lengthSeconds"]) ?? 0

        return VideoPlayback(
            videoId: videoId,
            title: title,
            channelName: channel,
            channelId: channelId,
            durationSeconds: duration,
            formats: formats,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"),
            captionTracks: []
        )
    }

    private static func mimeCodecs(_ mime: String) -> [String] {
        guard let range = mime.range(of: "codecs=\"") else { return [] }
        let rest = mime[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return [] }
        return String(rest[..<end])
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s)
        default: return nil
        }
    }

    private static func stringValue(_ any: Any?) -> String {
        switch any {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return ""
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func nested(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    /// YouTube HTML embeds `&` as `\u0026`.
    var youtubeUnescaped: String {
        replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")
    }
}
