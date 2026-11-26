import SwiftUI
import AVKit
import AVFoundation
import UIKit

extension Notification.Name {
    /// Posted when the user toggles Picture in Picture in Settings.
    static let ytlitePictureInPictureSettingDidChange = Notification.Name("ytlitePictureInPictureSettingDidChange")
}

/// Shared PiP preference (must match `AppModel.pictureInPictureKey`).
enum PictureInPictureSettings {
    static let defaultsKey = "picture_in_picture_enabled"

    /// Default OFF when the user has never toggled the setting. Mac has no system PiP.
    static var isEnabled: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        if UserDefaults.standard.object(forKey: defaultsKey) != nil {
            return UserDefaults.standard.bool(forKey: defaultsKey)
        }
        return false
        #endif
    }
}

/// Inline player surface: no system chrome; supports programmatic PiP + fullscreen.
struct PipPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var pipRequestID: Int = 0
    var fullscreenRequestID: Int = 0
    /// App playback intent — used to resume after fullscreen dismiss (AVPVC pauses on close).
    var isPlaying: Bool = false
    var playbackSpeed: Float = 1.0
    /// Android mini uses ZOOM; detail canvas uses fit.
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var pictureInPictureEnabled: Bool = false

    func makeUIViewController(context: Context) -> PlayerSurfaceController {
        let controller = PlayerSurfaceController()
        controller.configure(
            player: player,
            videoGravity: videoGravity,
            isPlaying: isPlaying,
            playbackSpeed: playbackSpeed,
            pictureInPictureEnabled: pictureInPictureEnabled
        )
        // Avoid treating leftover request IDs as new taps after the representable is recreated.
        context.coordinator.lastPipRequestID = pipRequestID
        context.coordinator.lastFullscreenRequestID = fullscreenRequestID
        context.coordinator.surface = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: PlayerSurfaceController, context: Context) {
        uiViewController.configure(
            player: player,
            videoGravity: videoGravity,
            isPlaying: isPlaying,
            playbackSpeed: playbackSpeed,
            pictureInPictureEnabled: pictureInPictureEnabled
        )
        context.coordinator.surface = uiViewController
        if pipRequestID != context.coordinator.lastPipRequestID {
            context.coordinator.lastPipRequestID = pipRequestID
            if PictureInPictureSettings.isEnabled {
                uiViewController.startPictureInPicture()
            }
        }
        if fullscreenRequestID != context.coordinator.lastFullscreenRequestID {
            context.coordinator.lastFullscreenRequestID = fullscreenRequestID
            uiViewController.enterFullscreen()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var surface: PlayerSurfaceController?
        var lastPipRequestID = 0
        var lastFullscreenRequestID = 0
    }
}

final class PlayerSurfaceController: UIViewController, AVPictureInPictureControllerDelegate {
    private let playerView = PlayerLayerView()
    private var pipController: AVPictureInPictureController?
    private var fullscreenController: FullscreenPlayerViewController?
    /// Strong ref so restore still works if AVPVC clears `player` during dismiss.
    private var fullscreenPlayer: AVPlayer?
    private var isFullscreenActive = false
    private var prefersPlaying = false
    private var playbackSpeed: Float = 1.0
    private var pictureInPictureEnabled = false
    private weak var configuredPlayer: AVPlayer?
    private var lifecycleObservers: [NSObjectProtocol] = []
    /// When PiP is off, detach the layer on resign-active so iOS cannot open a floating window;
    /// AVPlayer keeps playing audio without a layer.
    private var detachedLayerForAudioOnlyBackground = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // Inline surface never needs touches — SwiftUI owns controls; UIKit otherwise steals hits.
        view.isUserInteractionEnabled = false
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.isUserInteractionEnabled = false
        view.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: view.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Tear down auto-PiP *before* backgrounding. Leaving from player detail otherwise
        // still starts a floating window even when the setting is off.
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.suppressAutomaticPictureInPictureForBackground()
            },
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.suppressAutomaticPictureInPictureForBackground()
            },
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.restoreLayerAfterAudioOnlyBackgroundIfNeeded()
            },
            center.addObserver(
                forName: .ytlitePictureInPictureSettingDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // Setting flipped while foreground — destroy controller only; do not detach layer.
                self?.applyPictureInPictureSetting(destroyControllerIfDisabled: true)
            },
        ]
    }

    deinit {
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppOrientation.registerVideoSurfaceHost(self)
        // Heal black canvas if fullscreen flag got stuck or layer was detached.
        if !isFullscreenActive, let configuredPlayer {
            attachInlinePlayer(configuredPlayer, forceRefresh: true)
            detachedLayerForAudioOnlyBackground = false
        }
        applyPictureInPictureSetting(destroyControllerIfDisabled: true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        AppOrientation.unregisterVideoSurfaceHost(self)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        AppOrientation.mask
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        AppOrientation.mask == .landscapeRight ? .landscapeRight : .portrait
    }

    override var shouldAutorotate: Bool { true }

    func configure(
        player: AVPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspect,
        isPlaying: Bool = false,
        playbackSpeed: Float = 1.0,
        pictureInPictureEnabled: Bool = false
    ) {
        prefersPlaying = isPlaying
        self.playbackSpeed = playbackSpeed
        self.pictureInPictureEnabled = PictureInPictureSettings.isEnabled && pictureInPictureEnabled
        configuredPlayer = player

        // Self-heal if dismiss callback never ran.
        if isFullscreenActive, presentedViewController == nil, fullscreenController == nil {
            isFullscreenActive = false
            fullscreenPlayer = nil
            AppOrientation.endVideoFullscreen(from: self)
        }

        // AVPlayer may only drive one surface; do not steal it back from fullscreen.
        // Also skip while intentionally detached for audio-only background (PiP off).
        if !isFullscreenActive, !detachedLayerForAudioOnlyBackground {
            attachInlinePlayer(player)
        }
        playerView.playerLayer.videoGravity = videoGravity
        applyPictureInPictureSetting(destroyControllerIfDisabled: true)
    }

    func startPictureInPicture() {
        guard PictureInPictureSettings.isEnabled, !isFullscreenActive else { return }
        restoreLayerAfterAudioOnlyBackgroundIfNeeded()
        applyPictureInPictureSetting(destroyControllerIfDisabled: false)
        guard let pip = pipController, pip.isPictureInPicturePossible else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    func enterFullscreen() {
        guard !isFullscreenActive, presentedViewController == nil else { return }
        restoreLayerAfterAudioOnlyBackgroundIfNeeded()
        guard let player = playerView.playerLayer.player ?? configuredPlayer else { return }
        guard view.window != nil else { return }

        let pipEnabled = PictureInPictureSettings.isEnabled
        pictureInPictureEnabled = pipEnabled
        let preferPortrait = Self.isPortraitVideo(player: player)

        isFullscreenActive = true
        fullscreenPlayer = player
        // Detach inline layer so AVPlayerViewController exclusively owns the player.
        playerView.playerLayer.player = nil
        // Inline PiP controller must not survive across fullscreen / Home.
        destroyPipController()

        AppOrientation.beginVideoFullscreen(portrait: preferPortrait)

        let vc = FullscreenPlayerViewController()
        vc.preferPortrait = preferPortrait
        vc.player = player
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = pipEnabled
        vc.modalPresentationStyle = .fullScreen
        vc.modalPresentationCapturesStatusBarAppearance = true
        vc.onDidDismiss = { [weak self] in
            self?.restoreAfterFullscreen()
        }
        fullscreenController = vc
        present(vc, animated: true) { [weak self] in
            vc.setNeedsUpdateOfSupportedInterfaceOrientations()
            guard let self else { return }
            if self.presentedViewController !== vc {
                self.restoreAfterFullscreen()
            }
        }
    }

    /// Uses `presentationSize` (includes preferred transform). Square → portrait fullscreen.
    private static func isPortraitVideo(player: AVPlayer) -> Bool {
        guard let item = player.currentItem else { return false }
        let size = item.presentationSize
        guard size.width > 1, size.height > 1 else { return false }
        return size.height >= size.width
    }

    // MARK: - AVPictureInPictureControllerDelegate

    func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        // Last-chance block: if the setting is off, stop immediately after start.
        if !PictureInPictureSettings.isEnabled {
            DispatchQueue.main.async {
                pictureInPictureController.stopPictureInPicture()
            }
        }
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        if !PictureInPictureSettings.isEnabled {
            pictureInPictureController.stopPictureInPicture()
            destroyPipController()
        }
    }

    // MARK: - Private

    private func restoreAfterFullscreen() {
        AppOrientation.endVideoFullscreen(from: self)
        let player = fullscreenPlayer ?? fullscreenController?.player ?? configuredPlayer
        fullscreenController?.player = nil
        fullscreenController = nil
        fullscreenPlayer = nil
        isFullscreenActive = false
        detachedLayerForAudioOnlyBackground = false
        guard let player else { return }
        attachInlinePlayer(player, forceRefresh: true)
        applyPictureInPictureSetting(destroyControllerIfDisabled: true)
        if prefersPlaying {
            player.playImmediately(atRate: playbackSpeed)
        } else {
            player.pause()
        }
    }

    private func attachInlinePlayer(_ player: AVPlayer, forceRefresh: Bool = false) {
        if forceRefresh || playerView.playerLayer.player !== player {
            playerView.playerLayer.player = nil
            playerView.playerLayer.player = player
        }
    }

    /// Destroy the PiP controller and detach the video layer so the system cannot open a
    /// floating window from the player detail surface. Audio continues on `AVPlayer`.
    private func suppressAutomaticPictureInPictureForBackground() {
        guard !PictureInPictureSettings.isEnabled else {
            // Keep auto-PiP armed when the setting is on.
            applyPictureInPictureSetting(destroyControllerIfDisabled: false)
            return
        }
        stopPictureInPictureIfSettingDisabled()
        destroyPipController()
        guard !isFullscreenActive else {
            fullscreenController?.allowsPictureInPicturePlayback = false
            return
        }
        if playerView.playerLayer.player != nil {
            playerView.playerLayer.player = nil
            detachedLayerForAudioOnlyBackground = true
        }
    }

    private func restoreLayerAfterAudioOnlyBackgroundIfNeeded() {
        guard detachedLayerForAudioOnlyBackground else { return }
        detachedLayerForAudioOnlyBackground = false
        guard !isFullscreenActive, let configuredPlayer else { return }
        attachInlinePlayer(configuredPlayer, forceRefresh: true)
        applyPictureInPictureSetting(destroyControllerIfDisabled: true)
    }

    /// When PiP is off, destroy the controller entirely — leaving `canStart…=false` on a live
    /// controller is not enough; Home from player detail can still open a floating window.
    private func applyPictureInPictureSetting(destroyControllerIfDisabled: Bool) {
        let enabled = PictureInPictureSettings.isEnabled
        pictureInPictureEnabled = enabled
        fullscreenController?.allowsPictureInPicturePlayback = enabled

        if !enabled {
            stopPictureInPictureIfSettingDisabled()
            if destroyControllerIfDisabled {
                destroyPipController()
            }
            return
        }

        ensurePipController()
        if let pip = pipController, #available(iOS 14.2, *) {
            pip.canStartPictureInPictureAutomaticallyFromInline = true
        }
    }

    private func ensurePipController() {
        guard PictureInPictureSettings.isEnabled else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        if pipController == nil {
            let pip = AVPictureInPictureController(playerLayer: playerView.playerLayer)
            pip?.delegate = self
            if #available(iOS 14.2, *) {
                pip?.canStartPictureInPictureAutomaticallyFromInline = true
            }
            pipController = pip
        }
    }

    private func destroyPipController() {
        guard let pip = pipController else { return }
        if #available(iOS 14.2, *) {
            pip.canStartPictureInPictureAutomaticallyFromInline = false
        }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        }
        pip.delegate = nil
        pipController = nil
    }

    private func stopPictureInPictureIfSettingDisabled() {
        guard !PictureInPictureSettings.isEnabled else { return }
        if let pip = pipController, pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        }
    }
}

/// Detects Done dismiss so we can reattach the player to the inline layer.
private final class FullscreenPlayerViewController: AVPlayerViewController {
    var onDidDismiss: (() -> Void)?
    /// Vertical / square video stays upright; landscape video locks landscape right.
    var preferPortrait = false

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        preferPortrait ? .portrait : .landscapeRight
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        preferPortrait ? .portrait : .landscapeRight
    }

    override var shouldAutorotate: Bool { false }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Do NOT use `presentingViewController == nil` — that is true before present
        // and was clearing the inline layer permanently (black canvas, audio still plays).
        guard isBeingDismissed else { return }
        let callback = onDidDismiss
        onDidDismiss = nil
        callback?()
    }
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
