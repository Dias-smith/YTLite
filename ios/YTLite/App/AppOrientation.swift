import UIKit

/// App-wide interface orientation lock.
/// iPhone stays portrait except during video fullscreen (landscape).
/// iPad remains free to rotate; fullscreen still *prefers* landscape.
enum AppOrientation {
    static var mask: UIInterfaceOrientationMask = defaultMask

    static var defaultMask: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }

    static func beginVideoFullscreen() {
        mask = .landscape
        request(.landscapeRight)
    }

    static func endVideoFullscreen() {
        mask = defaultMask
        request(.portrait)
    }

    private static func request(_ orientations: UIInterfaceOrientationMask) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard let scene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
        // Do not call `setNeedsUpdateOfSupportedInterfaceOrientations` on the
        // window root — it can dismiss the player sheet while `isPresented`
        // stays true, so the mini player can no longer open PlayerDetail.
    }
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
