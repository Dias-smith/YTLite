import Foundation
import SwiftUI

/// Watch string catalog lookup (`Localizable.xcstrings` in the Watch target).
enum WatchL10n {
    /// Call once at process start. DEBUG forces English regardless of Watch system language.
    static func configureAtLaunch() {
        #if DEBUG
        UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        #endif
    }

    static func string(_ key: String, default defaultValue: String) -> String {
        let value = Bundle.main.localizedString(forKey: key, value: defaultValue, table: "Localizable")
        return value.isEmpty ? defaultValue : value
    }
}

func WL(_ key: String, _ defaultValue: String) -> String {
    WatchL10n.string(key, default: defaultValue)
}

/// Compact watch typography — a notch smaller than stock `.caption` / `.caption2`.
enum WatchType {
    /// Primary row / now-playing title (~11pt; stock caption ≈ 12).
    static let title = Font.system(size: 11, weight: .regular)
    static let titleSemibold = Font.system(size: 11, weight: .semibold)
    static let titleBold = Font.system(size: 11, weight: .bold)

    /// Secondary meta / artist / duration (~9.5pt; stock caption2 ≈ 11).
    static let meta = Font.system(size: 9.5, weight: .regular)
    static let metaMedium = Font.system(size: 9.5, weight: .medium)
    static let metaSemibold = Font.system(size: 9.5, weight: .semibold)
    static let metaMono = Font.system(size: 9.5, weight: .regular).monospacedDigit()

    /// Empty-state headline.
    static let emptyTitle = Font.system(size: 13, weight: .semibold)
    static let emptyIcon = Font.system(size: 28, weight: .regular)

    /// Transport glyph sizes (slightly tighter than `.title3`).
    static let transport = Font.system(size: 15, weight: .regular)
    static let playPause = Font.system(size: 16, weight: .semibold)
}
