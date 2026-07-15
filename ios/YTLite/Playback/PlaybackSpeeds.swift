import Foundation

/// Playback speed options aligned with Android `PlaybackSpeeds`.
enum PlaybackSpeeds {
    static let options: [Float] = PlaybackController.speedOptions
    static let `default`: Float = 1

    static func formatLabel(_ speed: Float) -> String {
        if speed.rounded() == speed {
            return "\(Int(speed))x"
        }
        let trimmed = String(format: "%g", speed)
        return "\(trimmed)x"
    }
}
