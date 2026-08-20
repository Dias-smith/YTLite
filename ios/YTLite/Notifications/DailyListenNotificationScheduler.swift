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

    static func refresh(using store: LibraryStore?) async {
        let songs = store?.successfullyPlayedSongs() ?? []
        guard songs.count >= minimumSongCount else {
            await cancelAll()
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let ok = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                guard ok else { return }
            } catch {
                return
            }
        case .denied:
            return
        default:
            break
        }
        await reschedule(songs: songs)
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
            try? await center.add(request)
        }
    }

    private static func dayKey(for day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
