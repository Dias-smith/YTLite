import MediaPlayer
import UIKit

/// Sets iPhone system output volume (0…1) via `MPVolumeView` for Watch remote control.
@MainActor
enum SystemOutputVolume {
    private static var hiddenVolumeView: MPVolumeView?

    static func set(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        let view = volumeView()
        guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
        // Avoid sending `.valueChanged` storms when already at target.
        guard abs(slider.value - clamped) > 0.004 else { return }
        slider.value = clamped
    }

    private static func volumeView() -> MPVolumeView {
        if let hiddenVolumeView { return hiddenVolumeView }
        let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        if let host = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        {
            host.addSubview(view)
        }
        hiddenVolumeView = view
        return view
    }
}
