import Foundation
import UserNotifications

/// Schedules at most one local notification per calendar day at 08:00 or 21:00
/// when the user has successfully played more than three songs.
@MainActor
enum DailyListenNotificationScheduler {
    static let minimumSongCount = 4
    static let identifierPrefix = "daily-listen."
    private static let hourMorning = 8
    private static let hourEvening = 21
    private static let daysAhead = 14

    private static let askedKey = "daily_listen.permission_asked.v1"
    private static let lastStatusKey = "notif_permission.last_status"

    /// Reschedule only. Does not show the system permission dialog.
    static func refresh(using store: LibraryStore?) async {
        await refresh(using: store, requestPermission: false)
    }

    /// One ask, after a song has finished, once the listener already has 4 successful plays.
    static func askOnceAfterCompletedSong(using store: LibraryStore?) async {
        let songs = store?.successfullyPlayedSongs() ?? []
        guard songs.count >= minimumSongCount else { return }
        guard !UserDefaults.standard.bool(forKey: askedKey) else { return }
        guard AppPermissionPromptGate.canPresent else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        await refresh(using: store, requestPermission: true)
    }

    private static func refresh(using store: LibraryStore?, requestPermission: Bool) async {
        let songs = store?.successfullyPlayedSongs() ?? []
        guard songs.count >= minimumSongCount else {
            await cancelAll()
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard requestPermission, AppPermissionPromptGate.canPresent else { return }
            UserDefaults.standard.set(true, forKey: askedKey)
            do {
                let ok = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                recordPermission(ok ? "authorized" : "denied", force: true)
                guard ok else { return }
            } catch {
                recordPermission("error", force: true)
                return
            }
        case .denied:
            recordPermission("denied", force: false)
            return
        default:
            recordPermission(statusLabel(settings.authorizationStatus), force: false)
        }
        await reschedule(songs: songs)
    }

    /// Dialog result always logs. Later refreshes log only when the status actually changes.
    private static func recordPermission(_ status: String, force: Bool) {
        let previous = UserDefaults.standard.string(forKey: lastStatusKey)
        guard force || previous != status else { return }
        UserDefaults.standard.set(status, forKey: lastStatusKey)
        AppAnalytics.notifPermission(status: status)
    }

    private static func statusLabel(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        case .notDetermined: return "not_determined"
        @unknown default: return "unknown"
        }
    }

    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func reschedule(songs: [VideoItem]) async {
        await cancelAll()
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let now = Date()
        guard let startDay = calendar.dateInterval(of: .day, for: now)?.start else { return }
        var scheduled = 0

        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { continue }
            let hour = Bool.random() ? hourMorning : hourEvening
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour
            comps.minute = 0
            comps.second = 0
            guard let fireDate = calendar.date(from: comps), fireDate > now else { continue }
            guard let song = songs.randomElement() else { continue }

            let content = UNMutableNotificationContent()
            content.title = L("notification.daily_listen.title")
            content.body = Lf("notification.daily_listen.body", song.title)
            content.sound = .default
            content.userInfo = [
                "videoId": song.videoId,
                "title": song.title,
                "channelName": song.channelName,
            ]

            let dayKey = Self.dayKey(for: day, calendar: calendar)
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: fireDate
                ),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: identifierPrefix + dayKey,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
                scheduled += 1
            } catch {
                continue
            }
        }
        if scheduled > 0 {
            AppAnalytics.dailyListenScheduled(count: scheduled)
        }
    }

    private static func dayKey(for day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
