import Foundation
import UserNotifications

extension Notification.Name {
    static let ytlitePlayFromDailyNotification = Notification.Name("ytlite.playFromDailyNotification")
}

/// Holds a pending play request from a notification tap (cold or warm start).
@MainActor
enum PendingDailyListenPlayback {
    private static let videoIdKey = "pendingDailyListen.videoId"
    private static let titleKey = "pendingDailyListen.title"
    private static let channelKey = "pendingDailyListen.channelName"

    static func store(videoId: String, title: String, channelName: String) {
        let defaults = UserDefaults.standard
        defaults.set(videoId, forKey: videoIdKey)
        defaults.set(title, forKey: titleKey)
        defaults.set(channelName, forKey: channelKey)
        NotificationCenter.default.post(name: .ytlitePlayFromDailyNotification, object: nil)
    }

    static func consume() -> VideoItem? {
        let defaults = UserDefaults.standard
        guard let videoId = defaults.string(forKey: videoIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !videoId.isEmpty
        else { return nil }
        let title = defaults.string(forKey: titleKey) ?? videoId
        let channel = defaults.string(forKey: channelKey) ?? ""
        defaults.removeObject(forKey: videoIdKey)
        defaults.removeObject(forKey: titleKey)
        defaults.removeObject(forKey: channelKey)
        return VideoItem(videoId: videoId, title: title, channelName: channel)
    }
}

/// `UNUserNotificationCenter` delegate — set once at app launch.
final class AppNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationCenterDelegate()

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Still show banner while foreground so the daily prompt is visible.
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let info = response.notification.request.content.userInfo
        guard let videoId = info["videoId"] as? String, !videoId.isEmpty else { return }
        let title = (info["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? videoId
        let channel = (info["channelName"] as? String) ?? ""
        await MainActor.run {
            PendingDailyListenPlayback.store(
                videoId: videoId,
                title: title,
                channelName: channel
            )
        }
    }
}
