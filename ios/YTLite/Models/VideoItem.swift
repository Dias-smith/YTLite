import Foundation

struct VideoItem: Identifiable, Hashable, Sendable {
    var id: String { videoId }
    let videoId: String
    let title: String
    let channelName: String
    let subtitle: String
    let thumbnailURL: URL?
    let durationText: String?

    init(
        videoId: String,
        title: String,
        channelName: String,
        subtitle: String = "",
        thumbnailURL: URL? = nil,
        durationText: String? = nil
    ) {
        self.videoId = videoId
        self.title = title
        self.channelName = channelName
        self.subtitle = subtitle.isEmpty ? channelName : subtitle
        self.thumbnailURL = thumbnailURL
            ?? URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg")
        self.durationText = durationText
    }

    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
    }
}

typealias SearchVideoItem = VideoItem

enum DurationFormat {
    static func text(seconds: Int) -> String? {
        guard seconds > 0 else { return nil }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    static func text(fromISO8601 iso: String?) -> String? {
        text(seconds: seconds(fromISO8601: iso))
    }

    static func seconds(fromISO8601 iso: String?) -> Int {
        guard let iso, iso.hasPrefix("PT") else { return 0 }
        let body = iso.dropFirst(2)
        var total = 0
        var number = ""
        for ch in body {
            if ch.isNumber {
                number.append(ch)
                continue
            }
            let value = Int(number) ?? 0
            number = ""
            switch ch {
            case "H": total += value * 3600
            case "M": total += value * 60
            case "S": total += value
            default: break
            }
        }
        return total
    }

    static func seconds(from text: String?) -> Int {
        guard let text, !text.isEmpty else { return 0 }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        case 1: return parts[0]
        default: return 0
        }
    }
}
