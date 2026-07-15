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
        let duration = intValue(music["duration"]) ?? 0
        let thumb = URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg")
        let captions = mapCaptions(music)

        return VideoPlayback(
            videoId: videoId,
            title: title,
            channelName: channel,
            durationSeconds: duration,
            formats: formats,
            thumbnailURL: thumb,
            captionTracks: captions
        )
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
        guard let url, let comps = URLComponents(string: url) else { return nil }
        return comps.queryItems?.first(where: { $0.name == "v" })?.value
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
