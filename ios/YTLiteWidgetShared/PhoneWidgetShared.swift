import AppIntents
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
        guard let defaults = PhoneWidgetShared.defaults else { return .empty }
        // Widget extension keeps an in-memory App Group cache; flush before read so
        // Intent / app writes are visible (otherwise play/pause icon is intermittently stale).
        defaults.synchronize()
        guard let data = defaults.data(forKey: PhoneWidgetShared.DefaultsKey.snapshot),
              let decoded = try? JSONDecoder().decode(PhoneWidgetPlaybackSnapshot.self, from: data)
        else {
            return .empty
        }
        return decoded
    }

    static func save(_ snapshot: PhoneWidgetPlaybackSnapshot) {
        guard let defaults = PhoneWidgetShared.defaults,
              let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: PhoneWidgetShared.DefaultsKey.snapshot)
        defaults.synchronize()
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

// MARK: - Intent dispatch (main app registers a handler; widget falls back to App Group queue)

/// Bridges widget `AudioPlaybackIntent`s into the main app process.
/// `AudioPlaybackIntent` wakes / runs inside the host app (even when previously killed).
enum PhoneWidgetIntentDispatcher {
    /// Set from the main app as early as `PlaybackController` exists.
    @MainActor
    static var handler: ((PhoneWidgetCommand) -> Void)?

    @MainActor
    static func dispatch(_ command: PhoneWidgetCommand) async {
        if let handler {
            handler(command)
            return
        }
        // Cold start race: intent can run before SwiftUI `.task` binds the handler.
        PhoneWidgetCommandQueue.enqueue(command)
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let handler {
                // Bridge.start may already have consumed the queue — apply once more if still pending.
                if let pending = PhoneWidgetCommandQueue.consume() {
                    handler(pending)
                }
                return
            }
        }
    }
}

// MARK: - Widget control intents (must live in app + widget targets)

/// Play/pause — runs in the **app** process via `AudioPlaybackIntent` so a killed app can resume.
struct PhoneWidgetTogglePlayIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play/Pause"
    static var description = IntentDescription("Play or pause Mixtube")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await PhoneWidgetIntentDispatcher.dispatch(.togglePlayPause)
        // WidgetKit reloads the timeline after `perform` returns — flush App Group first.
        PhoneWidgetShared.defaults?.synchronize()
        return .result()
    }
}

struct PhoneWidgetPlayNextIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Next"
    static var description = IntentDescription("Skip to the next track")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await PhoneWidgetIntentDispatcher.dispatch(.next)
        PhoneWidgetShared.defaults?.synchronize()
        return .result()
    }
}

struct PhoneWidgetPlayPreviousIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Previous"
    static var description = IntentDescription("Go to the previous track")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await PhoneWidgetIntentDispatcher.dispatch(.previous)
        PhoneWidgetShared.defaults?.synchronize()
        return .result()
    }
}
