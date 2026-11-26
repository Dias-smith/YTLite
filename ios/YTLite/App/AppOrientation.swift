import SwiftUI
import UIKit
import ObjectiveC

/// App-wide interface orientation lock.
/// Portrait everywhere except landscape AVPlayer full-screen (landscape right).
/// Portrait / square videos stay portrait when entering video fullscreen.
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

    /// - Parameter portrait: vertical/square video → keep portrait fullscreen; landscape → rotate.
    static func beginVideoFullscreen(portrait: Bool) {
        if portrait {
            mask = .portrait
            applyRotation(.portrait)
        } else {
            mask = .landscapeRight
            applyRotation(.landscapeRight)
        }
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
        #if targetEnvironment(macCatalyst)
        return
        #else
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard let scene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
        #endif
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
        #if targetEnvironment(macCatalyst)
        MacAppLifetime.install()
        #endif
        // Activate WCSession early so Watch can connect before first frame / consent.
        Task { @MainActor in
            WatchConnectivityBridge.shared.activate()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientation.mask
    }
}

#if targetEnvironment(macCatalyst)
/// The red close button hides the window. The process keeps running, and a Dock
/// click shows the window again. Command-Q still quits.
/// AppKit types are unavailable to Catalyst Swift, so this uses the Objective-C runtime.
private enum MacAppLifetime {
    private static var proxy: MacAppDelegateProxy?
    private static var didSwizzle = false
    /// Set only while Command-Q (or another real terminate) is closing windows.
    static var allowRealClose = false
    private static var hiddenTerminationHeld = false

    static func install() {
        if NSClassFromString("NSApplication") == nil {
            Bundle(path: "/System/Library/Frameworks/AppKit.framework")?.load()
        }
        swizzleIfNeeded()
        wrapCurrentDelegate()
        DispatchQueue.main.async {
            wrapCurrentDelegate()
        }
    }

    static func hidesOnClose(_ window: NSObject) -> Bool {
        if let panel = NSClassFromString("NSPanel") as? AnyClass, window.isKind(of: panel) {
            return false
        }
        if window.value(forKey: "parentWindow") != nil { return false }
        if (window.value(forKey: "isSheet") as? Bool) == true { return false }
        return true
    }

    static func hide(_ window: NSObject) {
        window.perform(NSSelectorFromString("orderOut:"), with: nil)
        holdAutomaticTermination()
    }

    static func showHiddenWindows() {
        guard let app = sharedApplication() else { return }
        let windows = app.value(forKey: "windows") as? [NSObject] ?? []
        let orderFront = NSSelectorFromString("makeKeyAndOrderFront:")
        for window in windows where hidesOnClose(window) {
            window.perform(orderFront, with: nil)
        }
        releaseAutomaticTerminationHold()
        let session = UIApplication.shared.openSessions.first
        UIApplication.shared.requestSceneSessionActivation(
            session,
            userActivity: nil,
            options: nil,
            errorHandler: nil
        )
    }

    private static func holdAutomaticTermination() {
        guard !hiddenTerminationHeld else { return }
        let process = ProcessInfo.processInfo as NSObject
        let disable = NSSelectorFromString("disableAutomaticTermination:")
        guard process.responds(to: disable) else { return }
        process.perform(disable, with: "MixtubeHiddenWindow")
        hiddenTerminationHeld = true
    }

    private static func releaseAutomaticTerminationHold() {
        guard hiddenTerminationHeld else { return }
        let process = ProcessInfo.processInfo as NSObject
        let enable = NSSelectorFromString("enableAutomaticTermination:")
        guard process.responds(to: enable) else { return }
        process.perform(enable, with: "MixtubeHiddenWindow")
        hiddenTerminationHeld = false
    }

    private static func sharedApplication() -> NSObject? {
        guard let appClass = NSClassFromString("NSApplication") as? NSObject.Type else { return nil }
        return appClass.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() as? NSObject
    }

    private static func wrapCurrentDelegate() {
        guard let app = sharedApplication() else { return }
        let current = app.value(forKey: "delegate") as? NSObject
        if current is MacAppDelegateProxy { return }
        let proxy = MacAppDelegateProxy()
        proxy.original = current
        self.proxy = proxy
        app.setValue(proxy, forKey: "delegate")
    }

    private static func swizzleIfNeeded() {
        guard !didSwizzle else { return }
        didSwizzle = true
        swizzleSetDelegate()
        for name in ["NSWindow", "UINSWindow"] {
            guard let cls = NSClassFromString(name) else { continue }
            swizzleClose(on: cls)
            swizzlePerformClose(on: cls)
        }
    }

    private static func swizzleSetDelegate() {
        guard let appClass = NSClassFromString("NSApplication"),
              let method = class_getInstanceMethod(appClass, NSSelectorFromString("setDelegate:"))
        else { return }
        typealias SetDelegateIMP = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        let selector = NSSelectorFromString("setDelegate:")
        let original = unsafeBitCast(method_getImplementation(method), to: SetDelegateIMP.self)
        let block: @convention(block) (AnyObject, AnyObject?) -> Void = { app, delegate in
            let installed: AnyObject?
            if let delegate = delegate as? NSObject, !(delegate is MacAppDelegateProxy) {
                let proxy = MacAppDelegateProxy()
                proxy.original = delegate
                MacAppLifetime.proxy = proxy
                installed = proxy
            } else {
                installed = delegate
            }
            original(app, selector, installed)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private static func swizzleClose(on cls: AnyClass) {
        let selector = NSSelectorFromString("close")
        guard ownsMethod(selector, on: cls),
              let method = class_getInstanceMethod(cls, selector)
        else { return }
        typealias CloseIMP = @convention(c) (AnyObject, Selector) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: CloseIMP.self)
        let block: @convention(block) (AnyObject) -> Void = { window in
            guard let object = window as? NSObject else {
                original(window, selector)
                return
            }
            if MacAppLifetime.allowRealClose || !MacAppLifetime.hidesOnClose(object) {
                original(window, selector)
                return
            }
            MacAppLifetime.hide(object)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private static func swizzlePerformClose(on cls: AnyClass) {
        let selector = NSSelectorFromString("performClose:")
        guard ownsMethod(selector, on: cls),
              let method = class_getInstanceMethod(cls, selector)
        else { return }
        typealias PerformCloseIMP = @convention(c) (AnyObject, Selector, Any?) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: PerformCloseIMP.self)
        let block: @convention(block) (AnyObject, Any?) -> Void = { window, sender in
            guard let object = window as? NSObject else {
                original(window, selector, sender)
                return
            }
            if MacAppLifetime.allowRealClose || !MacAppLifetime.hidesOnClose(object) {
                original(window, selector, sender)
                return
            }
            MacAppLifetime.hide(object)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private static func ownsMethod(_ selector: Selector, on cls: AnyClass) -> Bool {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else { return false }
        defer { free(methods) }
        for index in 0..<Int(count) where method_getName(methods[index]) == selector {
            return true
        }
        return false
    }
}

private final class MacAppDelegateProxy: NSObject {
    weak var original: NSObject?

    /// NSTerminateNow. Returning this lets Command-Q close the hidden window for real.
    @objc func applicationShouldTerminate(_ sender: Any) -> UInt {
        let selector = NSSelectorFromString("applicationShouldTerminate:")
        var reply: UInt = 1
        if let original, original.responds(to: selector) {
            typealias TerminateIMP = @convention(c) (AnyObject, Selector, Any) -> UInt
            let function = unsafeBitCast(original.method(for: selector), to: TerminateIMP.self)
            reply = function(original, selector, sender)
        }
        MacAppLifetime.allowRealClose = (reply == 1)
        return reply
    }

    @objc func applicationShouldTerminateAfterLastWindowClosed(_ sender: Any) -> Bool {
        false
    }

    @objc func applicationShouldHandleReopen(_ sender: Any, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MacAppLifetime.showHiddenWindows()
        }
        return true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return original?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if super.responds(to: aSelector) { return nil }
        return original
    }
}
#endif
