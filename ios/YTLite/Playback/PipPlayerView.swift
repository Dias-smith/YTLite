import SwiftUI
import AVKit
import AVFoundation

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

    func makeUIViewController(context: Context) -> PlayerSurfaceController {
        let controller = PlayerSurfaceController()
        controller.configure(
            player: player,
            videoGravity: videoGravity,
            isPlaying: isPlaying,
            playbackSpeed: playbackSpeed
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
            playbackSpeed: playbackSpeed
        )
        context.coordinator.surface = uiViewController
        if pipRequestID != context.coordinator.lastPipRequestID {
            context.coordinator.lastPipRequestID = pipRequestID
            uiViewController.startPictureInPicture()
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
    private weak var configuredPlayer: AVPlayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        playerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: view.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Heal black canvas if fullscreen flag got stuck or layer was detached.
        if !isFullscreenActive, let configuredPlayer {
            attachInlinePlayer(configuredPlayer, forceRefresh: true)
        }
    }

    func configure(
        player: AVPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspect,
        isPlaying: Bool = false,
        playbackSpeed: Float = 1.0
    ) {
        prefersPlaying = isPlaying
        self.playbackSpeed = playbackSpeed
        configuredPlayer = player

        // Self-heal if dismiss callback never ran.
        if isFullscreenActive, presentedViewController == nil, fullscreenController == nil {
            isFullscreenActive = false
            fullscreenPlayer = nil
        }

        // AVPlayer may only drive one surface; do not steal it back from fullscreen.
        if !isFullscreenActive {
            attachInlinePlayer(player)
        }
        playerView.playerLayer.videoGravity = videoGravity
        if pipController == nil, AVPictureInPictureController.isPictureInPictureSupported() {
            let pip = AVPictureInPictureController(playerLayer: playerView.playerLayer)
            pip?.delegate = self
            pipController = pip
        }
    }

    func startPictureInPicture() {
        guard !isFullscreenActive else { return }
        guard let pip = pipController, pip.isPictureInPicturePossible else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    func enterFullscreen() {
        guard !isFullscreenActive, presentedViewController == nil else { return }
        guard let player = playerView.playerLayer.player ?? configuredPlayer else { return }
        guard view.window != nil else { return }

        isFullscreenActive = true
        fullscreenPlayer = player
        // Detach inline layer so AVPlayerViewController exclusively owns the player.
        playerView.playerLayer.player = nil

        let vc = FullscreenPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = true
        vc.modalPresentationStyle = .fullScreen
        // Only fire on real dismiss — not when the view loads before `present`.
        vc.onDidDismiss = { [weak self] in
            self?.restoreAfterFullscreen()
        }
        fullscreenController = vc
        present(vc, animated: true) { [weak self] in
            guard let self else { return }
            // Present failed / was cancelled — put the player back on the inline layer.
            if self.presentedViewController !== vc {
                self.restoreAfterFullscreen()
            }
        }
    }

    private func restoreAfterFullscreen() {
        let player = fullscreenPlayer ?? fullscreenController?.player ?? configuredPlayer
        fullscreenController?.player = nil
        fullscreenController = nil
        fullscreenPlayer = nil
        isFullscreenActive = false
        guard let player else { return }
        attachInlinePlayer(player, forceRefresh: true)
        // AVPlayerViewController pauses on dismiss; restore app intent.
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
}

/// Detects Done dismiss so we can reattach the player to the inline layer.
private final class FullscreenPlayerViewController: AVPlayerViewController {
    var onDidDismiss: (() -> Void)?

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
