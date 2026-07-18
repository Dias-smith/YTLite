import Foundation

/// Temporary stage probe for diagnosing playback failures (filter Console: `YTLite.PlayProbe`).
enum PlayProbe {
    static let tag = "YTLite.PlayProbe"

    static func log(_ stage: String, videoId: String? = nil, _ detail: String = "") {
        let idPart = videoId.map { " id=\($0)" } ?? ""
        let detailPart = detail.isEmpty ? "" : " | \(detail)"
        print("[\(tag)] [\(stage)]\(idPart)\(detailPart)")
    }
}

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

    /// Progressive MP4 is what `AVPlayerItem(url:)` can open reliably.
    var isLikelyMP4: Bool {
        let lower = mimeType.lowercased()
        return lower.contains("mp4") || lower.contains("m4a") || lower.contains("mpeg")
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
    /// HLS master playlist when present (often the only AVPlayer-friendly Shorts stream).
    let hlsManifestURL: URL?

    init(
        videoId: String,
        title: String,
        channelName: String,
        channelId: String?,
        durationSeconds: Int,
        formats: [StreamFormat],
        thumbnailURL: URL?,
        captionTracks: [CaptionTrack],
        hlsManifestURL: URL? = nil
    ) {
        self.videoId = videoId
        self.title = title
        self.channelName = channelName
        self.channelId = channelId
        self.durationSeconds = durationSeconds
        self.formats = formats
        self.thumbnailURL = thumbnailURL
        self.captionTracks = captionTracks
        self.hlsManifestURL = hlsManifestURL
    }

    func preferredStreamURL(preferVideo: Bool = true) -> URL? {
        // Prefer progressive muxed itag 18 (then 22/37); HLS only if no muxed URL.
        // Adaptive DASH cannot be opened via AVPlayerItem(url:).
        if let url = PlaybackFormatSelector.select(formats: formats, preferVideo: preferVideo)?.url {
            return url
        }
        if preferVideo {
            return hlsManifestURL
        }
        return nil
    }

    func preferredStreamDescription(preferVideo: Bool = true) -> String {
        if let fmt = PlaybackFormatSelector.select(formats: formats, preferVideo: preferVideo) {
            return "itag=\(fmt.itag) mime=\(fmt.mimeType.prefix(64)) muxed=\(fmt.isMuxed)"
        }
        if preferVideo, hlsManifestURL != nil {
            return "hls"
        }
        return "none"
    }
}

enum PlaybackFormatSelector {
    /// Muxed A+V only for progressive; preferred order is itag 18 → 22 → 37.
    static func select(formats: [StreamFormat], preferVideo: Bool) -> StreamFormat? {
        if preferVideo {
            for itag in YouTubeConstants.preferredVideoItags {
                if let hit = formats.first(where: {
                    $0.itag == itag && $0.isMuxed
                }) {
                    return hit
                }
            }
            if let muxedMP4 = formats
                .filter({ $0.isMuxed && $0.isLikelyMP4 })
                .max(by: { $0.height < $1.height })
            {
                return muxedMP4
            }
            if let muxed = formats.filter(\.isMuxed).max(by: { $0.height < $1.height }) {
                return muxed
            }
            // Never return adaptive video-only — AVPlayer reports "Cannot Open".
            return nil
        } else {
            for itag in YouTubeConstants.preferredAudioItags {
                if let hit = formats.first(where: { $0.itag == itag && $0.isAudioOnly }) {
                    return hit
                }
            }
            return formats.first(where: \.isAudioOnly)
        }
    }
}

enum ExtractResultMapper {
    static func map(envelope: [String: Any], fallbackVideoId: String) throws -> VideoPlayback {
        PlayProbe.log("extract.map.start", videoId: fallbackVideoId)
        guard let data = envelope["data"] as? [String: Any] else {
            PlayProbe.log("extract.map.fail", videoId: fallbackVideoId, "missing data")
            throw ExtractorBridge.ExtractorError.invalidResponse("missing data")
        }
        // extractor.js `createExtractMsg` always sets success:true; real failures land in
        // errorMsg / music:null (same as Android JsResultMapper.playbackErrorMessage).
        let topError = stringValue(data["errorMsg"]).nilIfEmpty
            ?? stringValue(data["errorMSG"]).nilIfEmpty
        let explicitFail = (data["success"] as? Bool) == false
        if explicitFail {
            PlayProbe.log(
                "extract.map.fail",
                videoId: fallbackVideoId,
                "explicitFail err=\(topError ?? "extract failed")"
            )
            throw ExtractorBridge.ExtractorError.extractFailed(
                topError ?? "extract failed"
            )
        }
        guard let payload = data["data"] as? [String: Any] else {
            PlayProbe.log(
                "extract.map.fail",
                videoId: fallbackVideoId,
                "missing payload err=\(topError ?? "-")"
            )
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
            PlayProbe.log("extract.map.fail", videoId: fallbackVideoId, "music=null err=\(msg)")
            throw ExtractorBridge.ExtractorError.extractFailed(msg)
        }
        let rawFormats = music["formats"] as? [[String: Any]] ?? []
        var formats: [StreamFormat] = []
        var hlsFromFormat: URL?
        for item in rawFormats {
            guard let urlString = item["url"] as? String,
                  let url = URL(string: urlString),
                  !urlString.isEmpty
            else { continue }
            let lower = urlString.lowercased()
            if lower.contains(".m3u8") {
                if hlsFromFormat == nil { hlsFromFormat = url }
                continue
            }
            let itag = intValue(item["itag"]) ?? 0
            let mime = (item["type"] as? String)
                ?? (item["mimeType"] as? String)
                ?? ""
            formats.append(
                StreamFormat(
                    itag: itag,
                    url: url,
                    mimeType: mime,
                    width: intValue(item["width"]) ?? 0,
                    height: intValue(item["height"]) ?? 0,
                    acodec: stringValue(item["acodec"]),
                    vcodec: stringValue(item["vcodec"])
                )
            )
        }
        let hlsManifestURL = hlsManifestURL(from: music)
            ?? hlsManifestURL(from: payload)
            ?? hlsFromFormat
        guard !formats.isEmpty || hlsManifestURL != nil else {
            let msg = (nestedError ?? "no formats with url")
                .replacingOccurrences(of: "__notRetry@", with: "")
            PlayProbe.log(
                "extract.map.fail",
                videoId: fallbackVideoId,
                "no formats/hls (raw=\(rawFormats.count)) err=\(msg)"
            )
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

        PlayProbe.log(
            "extract.map.ok",
            videoId: videoId,
            "formats=\(formats.count) hls=\(hlsManifestURL != nil) duration=\(duration)s title=\(title.prefix(40))"
        )
        return VideoPlayback(
            videoId: videoId,
            title: title,
            channelName: channel,
            channelId: channelId,
            durationSeconds: duration,
            formats: formats,
            thumbnailURL: thumb,
            captionTracks: captions,
            hlsManifestURL: hlsManifestURL
        )
    }

    /// Live streams often only expose HLS; JS payload may nest it under music / streamingData.
    private static func hlsManifestURL(from root: [String: Any]) -> URL? {
        let directKeys = [
            "hlsManifestUrl", "hls_manifest_url", "manifest_url", "hlsUrl", "hls_url",
        ]
        for key in directKeys {
            if let url = stringValue(root[key]).nilIfEmpty.flatMap(URL.init(string:)) {
                return url
            }
        }
        if let streaming = root["streamingData"] as? [String: Any] {
            for key in directKeys {
                if let url = stringValue(streaming[key]).nilIfEmpty.flatMap(URL.init(string:)) {
                    return url
                }
            }
        }
        if let player = root["player_response"] as? [String: Any]
            ?? root["playerResponse"] as? [String: Any],
           let streaming = player["streamingData"] as? [String: Any]
        {
            for key in directKeys {
                if let url = stringValue(streaming[key]).nilIfEmpty.flatMap(URL.init(string:)) {
                    return url
                }
            }
        }
        return nil
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

/// When InnerTube JS clients return UNPLAYABLE:
/// 1) ANDROID `/youtubei/v1/player` with `signatureTimestamp` (direct googlevideo URLs, no nsig)
/// 2) scrape `ytInitialPlayerResponse` from watch HTML (often 403 without nsig — last resort)
enum WatchPagePlayerFallback {
    /// Cap so a hung ANDROID player never burns the full URLSession request timeout
    /// before the WKWebView bridge can start.
    private static let fastPathDeadlineSeconds: TimeInterval = 6

    /// One-request fast path using the configured Android client and STS.
    /// Falls back to the WKWebView extractor when YouTube rejects this client.
    /// Hard-capped so failure is fail-fast (does not wait ~30s HTTP timeout).
    static func extractFast(videoId: String) async -> VideoPlayback? {
        let id = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        let cfg = ExtractorRemoteConfigStore.current
        guard cfg.enableAndroidPlayerFallback else { return nil }
        PlayProbe.log("extract.fast.begin", videoId: id)
        return await withTaskGroup(of: VideoPlayback?.self) { group in
            group.addTask {
                await extractViaAndroidPlayer(
                    videoId: id,
                    signatureTimestamp: cfg.signatureTimestamp,
                    clientVersion: cfg.androidClientVersion,
                    requestTimeout: fastPathDeadlineSeconds
                )
            }
            group.addTask {
                try? await Task.sleep(
                    nanoseconds: UInt64(fastPathDeadlineSeconds * 1_000_000_000)
                )
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            if first == nil {
                PlayProbe.log("extract.fast.miss", videoId: id, "deadline_or_reject")
            }
            return first
        }
    }

    static func extract(videoId: String) async throws -> VideoPlayback {
        let id = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw ExtractorBridge.ExtractorError.invalidResponse("empty videoId")
        }
        PlayProbe.log("extract.fallback.start", videoId: id)
        let cfg = ExtractorRemoteConfigStore.current
        // Normalize Shorts → watch before scraping (never hit /shorts/{id}).
        let pages = [
            YouTubeURL.canonicalWatchURL(YouTubeURL.watchURL(videoId: id)),
            YouTubeURL.canonicalWatchURL("https://m.youtube.com/watch?v=\(id)"),
        ]
        var lastError: Error = ExtractorBridge.ExtractorError.extractFailed("unplayable")
        var signatureTimestamp = cfg.signatureTimestamp
        for pageURL in pages {
            PlayProbe.log("extract.fallback.page", videoId: id, pageURL)
            do {
                let html = try await fetchHTML(pageURL)
                PlayProbe.log(
                    "extract.fallback.html",
                    videoId: id,
                    "bytes=\(html.utf8.count)"
                )
                if let sts = extractSignatureTimestamp(from: html) {
                    signatureTimestamp = sts
                }

                // Prefer ANDROID player: WEB HTML progressive URLs commonly 403 without nsig.
                if cfg.enableAndroidPlayerFallback,
                   let androidPlayback = await extractViaAndroidPlayer(
                    videoId: id,
                    signatureTimestamp: signatureTimestamp,
                    clientVersion: cfg.androidClientVersion
                   )
                {
                    PlayProbe.log(
                        "extract.fallback.android.ok",
                        videoId: id,
                        "formats=\(androidPlayback.formats.count) sts=\(signatureTimestamp)"
                    )
                    return androidPlayback
                }

                guard cfg.enableWatchPageFallback else {
                    throw ExtractorBridge.ExtractorError.extractFailed("watch page fallback disabled")
                }
                guard let player = extractPlayerResponseJSON(from: html) else {
                    PlayProbe.log("extract.fallback.fail", videoId: id, "no ytInitialPlayerResponse")
                    continue
                }
                let mapped = try mapPlayerResponse(player, fallbackVideoId: id, source: "html")
                PlayProbe.log(
                    "extract.fallback.ok",
                    videoId: id,
                    "formats=\(mapped.formats.count) source=html"
                )
                return mapped
            } catch {
                PlayProbe.log(
                    "extract.fallback.fail",
                    videoId: id,
                    error.localizedDescription
                )
                lastError = error
            }
        }

        // HTML fetch may have failed; still try ANDROID with configured STS.
        if cfg.enableAndroidPlayerFallback,
           let androidPlayback = await extractViaAndroidPlayer(
            videoId: id,
            signatureTimestamp: signatureTimestamp,
            clientVersion: cfg.androidClientVersion
           )
        {
            PlayProbe.log(
                "extract.fallback.android.ok",
                videoId: id,
                "formats=\(androidPlayback.formats.count) sts=\(signatureTimestamp) no-html"
            )
            return androidPlayback
        }

        PlayProbe.log("extract.fallback.exhausted", videoId: id, lastError.localizedDescription)
        throw lastError
    }

    /// ANDROID Innertube player on `www.youtube.com` — returns plain `url` formats (no `n=`).
    private static func extractViaAndroidPlayer(
        videoId: String,
        signatureTimestamp: Int,
        clientVersion: String,
        requestTimeout: TimeInterval? = nil
    ) async -> VideoPlayback? {
        let androidUA =
            "com.google.android.youtube/\(clientVersion) (Linux; U; Android 11) gzip"
        PlayProbe.log(
            "extract.fallback.android.begin",
            videoId: videoId,
            "sts=\(signatureTimestamp) ver=\(clientVersion)"
        )
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "ANDROID",
                    "clientVersion": clientVersion,
                    "androidSdkVersion": 30,
                    "userAgent": androidUA,
                    "osName": "Android",
                    "osVersion": "11",
                    "hl": YouTubeConstants.hl,
                    "timeZone": "UTC",
                    "utcOffsetMinutes": 0,
                ],
            ],
            "videoId": videoId,
            "playbackContext": [
                "contentPlaybackContext": [
                    "html5Preference": "HTML5_PREF_WANTS",
                    "signatureTimestamp": signatureTimestamp,
                ],
            ],
            "contentCheckOk": true,
            "racyCheckOk": true,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let bodyText = String(data: data, encoding: .utf8)
        else {
            PlayProbe.log("extract.fallback.android.fail", videoId: videoId, "body encode")
            return nil
        }
        let result = await YouTubeHTTPClient.shared.request(
            url: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false",
            method: "POST",
            headers: [
                "User-Agent": androidUA,
                "Content-Type": "application/json",
                "X-YouTube-Client-Name": "3",
                "X-YouTube-Client-Version": clientVersion,
                "Origin": "https://www.youtube.com",
                "Referer": "https://www.youtube.com/",
            ],
            body: bodyText,
            timeout: requestTimeout
        )
        guard result.success,
              let raw = result.body.data(using: .utf8),
              let player = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else {
            PlayProbe.log(
                "extract.fallback.android.fail",
                videoId: videoId,
                "http code=\(result.errCode) \(result.errMsg)"
            )
            return nil
        }
        do {
            let mapped = try mapPlayerResponse(player, fallbackVideoId: videoId, source: "android")
            guard mapped.formats.contains(where: \.isMuxed) || mapped.hlsManifestURL != nil else {
                PlayProbe.log(
                    "extract.fallback.android.fail",
                    videoId: videoId,
                    "no muxed/hls"
                )
                return nil
            }
            return mapped
        } catch {
            PlayProbe.log(
                "extract.fallback.android.fail",
                videoId: videoId,
                error.localizedDescription
            )
            return nil
        }
    }

    private static func extractSignatureTimestamp(from html: String) -> Int? {
        let patterns = [
            #"\"STS\"\s*:\s*(\d+)"#,
            #"signatureTimestamp[=:]\s*(\d+)"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(
                   in: html,
                   range: NSRange(html.startIndex..., in: html)
               ),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: html),
               let value = Int(html[range])
            {
                return value
            }
        }
        return nil
    }

    private static func fetchHTML(_ url: String) async throws -> String {
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "GET",
            headers: [
                "User-Agent": YouTubeConstants.userAgent,
                "Referer": "https://www.youtube.com/",
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

    private static func mapPlayerResponse(
        _ player: [String: Any],
        fallbackVideoId: String,
        source: String
    ) throws -> VideoPlayback {
        let status = ((player["playabilityStatus"] as? [String: Any])?["status"] as? String)?
            .uppercased() ?? ""
        guard status == "OK" || status.isEmpty else {
            let reason = ((player["playabilityStatus"] as? [String: Any])?["reason"] as? String)?
                .nilIfEmpty
            throw ExtractorBridge.ExtractorError.extractFailed(reason ?? status.lowercased())
        }

        let streaming = player["streamingData"] as? [String: Any] ?? [:]
        let hlsManifestURL = (streaming["hlsManifestUrl"] as? String)?
            .youtubeUnescaped
            .nilIfEmpty
            .flatMap(URL.init(string:))
        // Prefer progressive `formats` (muxed) over adaptiveFragments for AVPlayer.
        let progressive = streaming["formats"] as? [[String: Any]] ?? []
        let adaptive = streaming["adaptiveFormats"] as? [[String: Any]] ?? []
        let formats: [StreamFormat] = (progressive + adaptive).compactMap { item in
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
        let muxedCount = formats.filter(\.isMuxed).count
        PlayProbe.log(
            "extract.fallback.formats",
            videoId: fallbackVideoId,
            "source=\(source) total=\(formats.count) muxed=\(muxedCount) hls=\(hlsManifestURL != nil) progressive=\(progressive.count) adaptive=\(adaptive.count)"
        )
        guard !formats.isEmpty || hlsManifestURL != nil else {
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
            captionTracks: [],
            hlsManifestURL: hlsManifestURL
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
