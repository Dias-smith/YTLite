import Foundation

/// Request paths, hosts, and the resolver script name are plain text.
/// The remote-config key and the catalog API Info.plist key stay XOR-salted.
enum SaltedLiteral {
    private static let salt: UInt8 = 0xA7

    static func reveal(_ bytes: [UInt8]) -> String {
        String(decoding: bytes.map { $0 ^ salt }, as: UTF8.self)
    }

    // MARK: - Hosts / paths (network)

    static var hostWWW: String { "https://www.youtube.com" }

    static var hostMusic: String { "https://music.youtube.com" }

    static var refererSlash: String { "https://www.youtube.com/" }

    static var pathSearch: String { "/youtubei/v1/search?key=" }

    static var pathBrowse: String { "/youtubei/v1/browse?key=" }

    static var pathNext: String { "/youtubei/v1/next?key=" }

    static var pathPlayer: String { "/youtubei/v1/player?prettyPrint=false" }

    static var pathPlayerNeedle: String { "/youtubei/v1/player" }

    static var pathNextNeedle: String { "/youtubei/v1/next" }

    static var pathCatalogApiNeedle: String { "/youtubei/v1/" }

    static var hostGooglevideo: String { "googlevideo.com" }

    static var hostGooglevideoShort: String { "googlevideo" }

    static var markerPlayerResponse: String { "ytInitialPlayerResponse = " }

    static var rcAllowKickoff: String {
        reveal([
            0xC6, 0xCB, 0xCB, 0xC8, 0xD0, 0xF8, 0xCC, 0xCE, 0xC4, 0xCC, 0xC8, 0xC1, 0xC1,
        ])
    }

    static var scriptResolution: String { "resolution.js" }

    static var hostSiteDomain: String { "youtube.com" }

    static var hostSiteDomainSlash: String { "youtube.com/" }

    static var hostShortLink: String { "youtu.be" }

    static var hostShortLinkSuffix: String { ".youtu.be" }

    static var hostShortLinkSlash: String { "youtu.be/" }

    static var hostMobile: String { "https://m.youtube.com" }

    static var headerClientName: String { "X-YouTube-Client-Name" }

    static var headerClientVersion: String { "X-YouTube-Client-Version" }

    static var androidPackagePrefix: String { "com.google.android.youtube/" }

    static var dataApiBase: String { "https://www.googleapis.com/youtube/v3" }

    static var dataApiChannels: String { "https://www.googleapis.com/youtube/v3/channels" }

    static var dataApiVideos: String { "https://www.googleapis.com/youtube/v3/videos" }

    static var oauthReadonlyScope: String {
        "openid email profile https://www.googleapis.com/auth/youtube.readonly"
    }

    static var browseLibraryId: String { "FEmy_youtube" }

    static var infoCatalogDataApiKey: String {
        reveal([
            0xE4, 0xE6, 0xF3, 0xE6, 0xEB, 0xE8, 0xE0, 0xF8, 0xE3, 0xE6, 0xF3, 0xE6, 0xF8, 0xE6,
            0xF7, 0xEE, 0xF8, 0xEC, 0xE2, 0xFE,
        ])
    }

    // MARK: - Media

    static var playbackMediaFolder: String { "playback_media" }

    static var indexFileName: String { "index.json" }

    static var probeHit: String { "play.k.hit" }

    static var probeStale: String { "play.k.stale" }

    static var probeSchedule: String { "play.k.plan" }

    static var probeSaved: String { "play.k.ok" }

    static var probeCancelled: String { "play.k.cancel" }

    static var probeFail: String { "play.k.fail" }

    static var probeEvict: String { "play.k.trim" }

    static var probeLocalSource: String { "src.k" }
}
