import SwiftUI
import AVKit
import AVFoundation

/// Inline player surface: no system chrome; supports programmatic PiP + fullscreen.
struct PipPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var pipRequestID: Int = 0
    var fullscreenRequestID: Int = 0
    /// Android mini uses ZOOM; detail canvas uses fit.
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIViewController(context: Context) -> PlayerSurfaceController {
        let controller = PlayerSurfaceController()
        controller.configure(player: player, videoGravity: videoGravity)
        context.coordinator.surface = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: PlayerSurfaceController, context: Context) {
        uiViewController.configure(player: player, videoGravity: videoGravity)
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
    private var fullscreenController: AVPlayerViewController?

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

    func configure(player: AVPlayer, videoGravity: AVLayerVideoGravity = .resizeAspect) {
        playerView.playerLayer.player = player
        playerView.playerLayer.videoGravity = videoGravity
        if pipController == nil, AVPictureInPictureController.isPictureInPictureSupported() {
            let pip = AVPictureInPictureController(playerLayer: playerView.playerLayer)
            pip?.delegate = self
            pipController = pip
        }
    }

    func startPictureInPicture() {
        guard let pip = pipController, pip.isPictureInPicturePossible else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    func enterFullscreen() {
        guard let player = playerView.playerLayer.player else { return }
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = true
        vc.modalPresentationStyle = .fullScreen
        fullscreenController = vc
        present(vc, animated: true)
    }
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
