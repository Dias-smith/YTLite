import Foundation

/// App Group keys shared by the iPhone app and Home Screen / Lock Screen widget.
enum PhoneWidgetShared {
    static let appGroupId = "group.com.ytlite.player"
    static let widgetKind = "PhoneNowPlayingWidget"
    static let darwinNotifyName = "com.ytlite.player.widgetCommand" as CFString

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    enum DefaultsKey {
        static let snapshot = "phone.widget.playbackSnapshot.v1"
        static let pendingCommand = "phone.widget.pendingCommand.v1"
    }
}

struct PhoneWidgetPlaybackSnapshot: Codable, Equatable, Sendable {
    var videoId: String
    var title: String
    var artist: String
    var thumbnailURL: String?
    var isPlaying: Bool
    var updatedAt: TimeInterval

    var hasTrack: Bool {
        !videoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let empty = PhoneWidgetPlaybackSnapshot(
        videoId: "",
        title: "",
        artist: "",
        thumbnailURL: nil,
        isPlaying: false,
        updatedAt: 0
    )
}

enum PhoneWidgetPlaybackSnapshotStore {
    static func load() -> PhoneWidgetPlaybackSnapshot {
        guard let data = PhoneWidgetShared.defaults?.data(forKey: PhoneWidgetShared.DefaultsKey.snapshot),
              let decoded = try? JSONDecoder().decode(PhoneWidgetPlaybackSnapshot.self, from: data)
        else {
            return .empty
        }
        return decoded
    }

    static func save(_ snapshot: PhoneWidgetPlaybackSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        PhoneWidgetShared.defaults?.set(data, forKey: PhoneWidgetShared.DefaultsKey.snapshot)
        PhoneWidgetShared.defaults?.synchronize()
    }
}

enum PhoneWidgetCommand: String, Codable, Sendable {
    case togglePlayPause
    case next
    case previous
}

enum PhoneWidgetCommandQueue {
    static func enqueue(_ command: PhoneWidgetCommand) {
        guard let defaults = PhoneWidgetShared.defaults else { return }
        defaults.set(command.rawValue, forKey: PhoneWidgetShared.DefaultsKey.pendingCommand)
        defaults.synchronize()
        PhoneWidgetDarwin.notifyCommandPending()
    }

    static func consume() -> PhoneWidgetCommand? {
        guard let defaults = PhoneWidgetShared.defaults else { return nil }
        defaults.synchronize()
        guard let raw = defaults.string(forKey: PhoneWidgetShared.DefaultsKey.pendingCommand),
              let command = PhoneWidgetCommand(rawValue: raw)
        else {
            return nil
        }
        defaults.removeObject(forKey: PhoneWidgetShared.DefaultsKey.pendingCommand)
        defaults.synchronize()
        return command
    }
}

enum PhoneWidgetDarwin {
    static func notifyCommandPending() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(PhoneWidgetShared.darwinNotifyName),
            nil,
            nil,
            true
        )
    }
}
