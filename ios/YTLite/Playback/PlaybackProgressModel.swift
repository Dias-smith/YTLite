import Foundation

/// High-frequency playback clock, separate from `PlaybackController` so list tabs
/// that only need play/queue APIs are not invalidated every progress tick.
@MainActor
final class PlaybackProgressModel: ObservableObject {
    @Published private(set) var positionSeconds: Double = 0
    @Published private(set) var durationSeconds: Double = 0
    /// Bumps every second while sleep timer is active so remaining-time UI refreshes.
    @Published private(set) var sleepTimerTick: Date = .distantPast

    func setPosition(_ value: Double) {
        positionSeconds = value
    }

    func setDuration(_ value: Double) {
        durationSeconds = value
    }

    func setPositionAndDuration(position: Double, duration: Double?) {
        positionSeconds = position
        if let duration {
            durationSeconds = duration
        }
    }

    func resetClock() {
        positionSeconds = 0
        durationSeconds = 0
    }

    func bumpSleepTimerTick(_ date: Date = Date()) {
        sleepTimerTick = date
    }
}
