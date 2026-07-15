import Foundation

/// Sleep timer presets for player detail + settings (session-scoped wall-clock countdown).
enum SleepTimerOptions {
    /// Minutes choices excluding Off (`nil`).
    static let minutesOptions: [Int] = [15, 30, 45, 60]

    static func formatLabel(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "Off" }
        return "\(minutes) min"
    }

    /// Compact chip label for remaining time (e.g. `24m`, `1:05`).
    static func formatRemaining(_ remaining: TimeInterval) -> String {
        let seconds = max(0, Int(remaining.rounded(.down)))
        let m = seconds / 60
        let s = seconds % 60
        if m >= 60 {
            let h = m / 60
            let mins = m % 60
            return String(format: "%d:%02d:%02d", h, mins, s)
        }
        if m >= 10 {
            return "\(m)m"
        }
        return String(format: "%d:%02d", m, s)
    }
}
