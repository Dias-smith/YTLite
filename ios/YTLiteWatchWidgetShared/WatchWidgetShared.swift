import Foundation

/// App Group keys shared by the Watch app and Watch Widget extension.
enum WatchWidgetShared {
    static let appGroupId = "group.com.ytlite.player"
    static let widgetKind = "WatchNowPlayingWidget"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    enum DefaultsKey {
        static let snapshot = "watch.widget.playbackSnapshot.v1"
        static let pendingCommand = "watch.widget.pendingCommand.v1"
    }
}

struct WatchWidgetPlaybackSnapshot: Codable, Equatable, Sendable {
    var videoId: String
    var title: String
    var artist: String
    var isPlaying: Bool
    var updatedAt: TimeInterval

    var hasTrack: Bool {
        !videoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let empty = WatchWidgetPlaybackSnapshot(
        videoId: "",
        title: "",
        artist: "",
        isPlaying: false,
        updatedAt: 0
    )
}

enum WatchWidgetPlaybackSnapshotStore {
    static func load() -> WatchWidgetPlaybackSnapshot {
        guard let data = WatchWidgetShared.defaults?.data(forKey: WatchWidgetShared.DefaultsKey.snapshot),
              let decoded = try? JSONDecoder().decode(WatchWidgetPlaybackSnapshot.self, from: data)
        else {
            return .empty
        }
        return decoded
    }

    static func save(_ snapshot: WatchWidgetPlaybackSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        WatchWidgetShared.defaults?.set(data, forKey: WatchWidgetShared.DefaultsKey.snapshot)
        WatchWidgetShared.defaults?.synchronize()
    }
}

enum WatchWidgetCommand: String, Codable, Sendable {
    case togglePlayPause
    case next
    case openApp
}

enum WatchWidgetCommandQueue {
    static func enqueue(_ command: WatchWidgetCommand) {
        guard let defaults = WatchWidgetShared.defaults else { return }
        defaults.set(command.rawValue, forKey: WatchWidgetShared.DefaultsKey.pendingCommand)
        defaults.synchronize()
    }

    static func consume() -> WatchWidgetCommand? {
        guard let defaults = WatchWidgetShared.defaults else { return nil }
        defaults.synchronize()
        guard let raw = defaults.string(forKey: WatchWidgetShared.DefaultsKey.pendingCommand),
              let command = WatchWidgetCommand(rawValue: raw)
        else {
            return nil
        }
        defaults.removeObject(forKey: WatchWidgetShared.DefaultsKey.pendingCommand)
        defaults.synchronize()
        return command
    }
}
