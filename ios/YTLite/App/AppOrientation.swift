import SwiftUI
import UIKit

/// App-wide interface orientation lock.
/// Portrait everywhere except AVPlayer full-screen video (landscape right).
enum AppOrientation {
    static var mask: UIInterfaceOrientationMask = defaultMask

    static var defaultMask: UIInterfaceOrientationMask { .portrait }

    private static weak var detailOrientationHost: UIViewController?
    private static weak var videoSurfaceHost: UIViewController?

    static func registerDetailOrientationHost(_ controller: UIViewController) {
        detailOrientationHost = controller
    }

    static func unregisterDetailOrientationHost(_ controller: UIViewController) {
        if detailOrientationHost === controller {
            detailOrientationHost = nil
        }
    }

    static func registerVideoSurfaceHost(_ controller: UIViewController) {
        videoSurfaceHost = controller
    }

    static func unregisterVideoSurfaceHost(_ controller: UIViewController) {
        if videoSurfaceHost === controller {
            videoSurfaceHost = nil
        }
    }

    static func beginVideoFullscreen() {
        mask = .landscapeRight
        applyRotation(.landscapeRight)
    }

    static func endVideoFullscreen(from surface: UIViewController? = nil) {
        mask = defaultMask
        if let surface {
            videoSurfaceHost = surface
        }
        applyRotation(.portrait)
    }

    private static func applyRotation(_ orientations: UIInterfaceOrientationMask) {
        func run() {
            request(orientations)
            for controller in orientationNotifyTargets() {
                controller.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
        run()
        DispatchQueue.main.async { run() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { run() }
    }

    private static func orientationNotifyTargets() -> [UIViewController] {
        var seen = Set<ObjectIdentifier>()
        var result: [UIViewController] = []

        func add(_ controller: UIViewController?) {
            guard let controller else { return }
            let id = ObjectIdentifier(controller)
            guard !seen.contains(id) else { return }
            seen.insert(id)
            result.append(controller)
        }

        add(detailOrientationHost)
        add(videoSurfaceHost)

        if let surface = videoSurfaceHost {
            var parent = surface.parent
            while let current = parent {
                add(current)
                parent = current.parent
            }
        }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        if let presented = scene?.windows.first(where: \.isKeyWindow)?.rootViewController?.presentedViewController {
            // fullScreenCover host for PlayerDetail — do not touch root itself.
            add(presented)
            presented.children.forEach { add($0) }
        }

        return result
    }

    private static func request(_ orientations: UIInterfaceOrientationMask) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard let scene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
    }
}

/// Keeps PlayerDetail on the app orientation mask (portrait outside video fullscreen).
struct PlayerDetailOrientationLockRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PlayerDetailOrientationLockController {
        PlayerDetailOrientationLockController()
    }

    func updateUIViewController(_ uiViewController: PlayerDetailOrientationLockController, context: Context) {}
}

final class PlayerDetailOrientationLockController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        AppOrientation.registerDetailOrientationHost(self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        AppOrientation.unregisterDetailOrientationHost(self)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        AppOrientation.mask
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        .portrait
    }

    override var shouldAutorotate: Bool { true }
}

final class YTLiteAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure before any Firebase SDK touches the default app (Analytics swizzling, etc.).
        FirebaseBootstrap.configure()
        application.beginReceivingRemoteControlEvents()
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientation.mask
    }
}
