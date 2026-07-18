import Foundation

/// Playback speed options aligned with Android `PlaybackSpeeds`.
enum PlaybackSpeeds {
    static let options: [Float] = PlaybackController.speedOptions
    static let `default`: Float = 1

    static func formatLabel(_ speed: Float) -> String {
        if speed.rounded() == speed {
            return String(format: "%.1fx", speed)
        }
        let trimmed = String(format: "%g", speed)
        return "\(trimmed)x"
    }
}

/// Queue loop mode — mirrors Android `QueueRepeatMode`.
enum QueueRepeatMode: String, Codable, CaseIterable, Sendable {
    case off = "OFF"
    case all = "ALL"
    case one = "ONE"

    mutating func cycle() {
        self = switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    var systemImage: String {
        switch self {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    var isActive: Bool {
        self != .off
    }
}
