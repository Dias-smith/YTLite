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
enum MacAppLifetime {
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
        for delay in [0.6, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated {
                    maximizeAtLaunch()
                }
            }
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

    private static func mainWindow() -> NSObject? {
        guard let app = sharedApplication() else { return nil }
        let raw = app.value(forKey: "windows")
        let windows = raw as? [NSObject] ?? (raw as? NSArray)?.compactMap { $0 as? NSObject } ?? []
        return windows.first { hidesOnClose($0) }
    }

    /// NSWindowStyleMaskFullScreen
    private static func isFullScreen(_ window: NSObject) -> Bool {
        let mask = (window.value(forKey: "styleMask") as? NSNumber)?.uintValue ?? 0
        return mask & (1 << 14) != 0
    }

    private static func toggleFullScreen(_ window: NSObject) {
        window.perform(NSSelectorFromString("toggleFullScreen:"), with: nil)
    }

    @MainActor
    private static func leaveFullScreen(_ window: NSObject, then: @escaping @MainActor () -> Void) {
        if !isFullScreen(window) {
            then()
            return
        }
        if let fullscreenExitObserver {
            NotificationCenter.default.removeObserver(fullscreenExitObserver)
        }
        fullscreenExitAction = then
        fullscreenExitObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("NSWindowDidExitFullScreenNotification"),
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                finishFullscreenExit(from: window)
            }
        }
        toggleFullScreen(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated {
                finishFullscreenExit(from: window)
            }
        }
    }

    @MainActor
    private static func finishFullscreenExit(from window: NSObject) {
        guard fullscreenExitAction != nil, !isFullScreen(window) else { return }
        let action = fullscreenExitAction
        fullscreenExitAction = nil
        if let fullscreenExitObserver {
            NotificationCenter.default.removeObserver(fullscreenExitObserver)
            self.fullscreenExitObserver = nil
        }
        action?()
    }

    private static var fullscreenExitAction: (@MainActor () -> Void)?

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
            swizzleMiniaturize(on: cls)
            swizzleZoom(on: cls)
            swizzleSetStyleMask(on: cls)
        }
    }

    private static let miniSize = CGSize(width: 460, height: 74)
    private static var savedFrame: CGRect?
    private static var savedLevel: Int?
    private static var savedBehavior: UInt?
    private static var savedStyleMask: UInt?
    private static var savedTitle: String?
    private static var savedTitleVisibility: Int?
    private static var savedTitlebarTransparent: Bool?
    private static var savedSeparatorStyle: Int?
    private static var savedOpaque: Bool?
    private static var savedBackground: AnyObject?
    private static var savedMinimumSize: CGSize?
    private static var savedMaximumSize: CGSize?
    private static var dragMonitor: AnyObject?
    private static var dragWindowOrigin: CGPoint?
    private static var dragMouseOrigin: CGPoint?
    private static var applyingChrome = false
    private static var savedWasFullScreen = false
    private static var didMaximizeAtLaunch = false
    private static var fullscreenExitObserver: NSObjectProtocol?
    private static weak var shrunkWindow: NSObject?

    /// Fill the screen under the menu bar. This stays a normal window, not a fullscreen space.
    @MainActor
    private static func maximizeAtLaunch() {
        guard !didMaximizeAtLaunch else { return }
        guard !MacWindowChrome.shared.isMinimizedToPlayer else { return }
        guard let window = mainWindow() else { return }
        if (window.value(forKey: "isVisible") as? Bool) == false { return }
        didMaximizeAtLaunch = true
        if isFullScreen(window) {
            leaveFullScreen(window) {
                applyMaximizedFrame(to: window)
            }
            return
        }
        applyMaximizedFrame(to: window)
    }

    private static func applyMaximizedFrame(to window: NSObject) {
        let current = rect(window.value(forKey: "frame"))
        guard let visible = screenVisibleFrame(containing: current) ?? visibleScreenFrames().first else { return }
        if let restrictions = scene()?.sizeRestrictions {
            var maxSize = restrictions.maximumSize
            if maxSize.width < visible.width { maxSize.width = visible.width }
            if maxSize.height < visible.height { maxSize.height = visible.height }
            restrictions.maximumSize = maxSize
        }
        requestFrame(visible, of: window)
    }

    /// Yellow button keeps a small player on screen instead of sending the window to the Dock.
    @MainActor
    static func shrinkToMiniPlayer(_ window: NSObject, resumedAfterFullscreenExit: Bool = false) {
        guard !MacWindowChrome.shared.isMinimizedToPlayer else { return }
        didMaximizeAtLaunch = true
        if isFullScreen(window) {
            savedWasFullScreen = true
            leaveFullScreen(window) {
                shrinkToMiniPlayer(window, resumedAfterFullscreenExit: true)
            }
            return
        }
        if !resumedAfterFullscreenExit {
            savedWasFullScreen = false
        }
        savedFrame = rect(window.value(forKey: "frame"))
        savedLevel = (window.value(forKey: "level") as? NSNumber)?.intValue
        savedBehavior = (window.value(forKey: "collectionBehavior") as? NSNumber)?.uintValue
        saveChrome(of: window)
        saveSizeRestrictions()
        shrunkWindow = window
        stopDragMonitor()
        setLevel(3, of: window)
        // All Spaces, stays up in full screen, skipped by the window cycle.
        setCollectionBehavior(1 | (1 << 8) | (1 << 6), of: window)
        window.setValue(true, forKey: "movableByWindowBackground")
        window.setValue(true, forKey: "hasShadow")
        applyMiniChrome(to: window)
        applyMiniFrame(miniFrame(near: savedFrame), of: window)
        MacWindowChrome.shared.isMinimizedToPlayer = true
        holdAutomaticTermination()
        DispatchQueue.main.async {
            guard MacWindowChrome.shared.isMinimizedToPlayer, shrunkWindow === window, dragMonitor == nil else { return }
            applyMiniChrome(to: window)
            guard let current = rect(window.value(forKey: "frame")) else { return }
            let wrongSize = abs(current.width - miniSize.width) > 2 || abs(current.height - miniSize.height) > 2
            guard wrongSize else { return }
            var frame = current
            frame.size = miniSize
            applyMiniFrame(frame, of: window)
        }
    }

    @MainActor
    static func restoreShrunkWindow() {
        let window = shrunkWindow ?? sharedApplication().flatMap { app in
            (app.value(forKey: "windows") as? [NSObject])?.first { hidesOnClose($0) }
        }
        rememberMiniOrigin()
        MacWindowChrome.shared.isMinimizedToPlayer = false
        stopDragMonitor()
        guard let window else { return }
        restoreChrome(of: window)
        restoreSizeRestrictions()
        setLevel(savedLevel ?? 0, of: window)
        if let savedBehavior {
            setCollectionBehavior(savedBehavior, of: window)
        }
        if let savedFrame {
            requestFrame(savedFrame, of: window)
        }
        savedFrame = nil
        savedLevel = nil
        savedBehavior = nil
        shrunkWindow = nil
        window.perform(NSSelectorFromString("makeKeyAndOrderFront:"), with: nil)
        releaseAutomaticTerminationHold()
        if savedWasFullScreen {
            savedWasFullScreen = false
            DispatchQueue.main.async {
                if !isFullScreen(window) {
                    toggleFullScreen(window)
                }
            }
        }
    }

    /// Follow the pointer in screen coordinates. SwiftUI's drag translation is in the moving window, so it jitters.
    @MainActor
    static func beginMiniPlayerDrag() {
        guard dragMonitor == nil, let window = shrunkWindow else { return }
        guard let mouse = quartzMouseLocation(), let frame = rect(window.value(forKey: "frame")) else { return }
        dragWindowOrigin = frame.origin
        dragMouseOrigin = mouse
        guard let eventClass = NSClassFromString("NSEvent"),
              let method = class_getClassMethod(eventClass, NSSelectorFromString("addLocalMonitorForEventsMatchingMask:handler:"))
        else { return }
        let selector = NSSelectorFromString("addLocalMonitorForEventsMatchingMask:handler:")
        // leftMouseDragged | leftMouseUp
        let mask: UInt = (1 << 6) | (1 << 2)
        let handler: @convention(block) (AnyObject) -> AnyObject? = { event in
            MainActor.assumeIsolated {
                MacAppLifetime.trackMiniPlayerDrag(event)
            }
            return event
        }
        typealias AddMonitorIMP = @convention(c) (
            AnyClass, Selector, UInt, @convention(block) (AnyObject) -> AnyObject?
        ) -> AnyObject?
        let function = unsafeBitCast(method_getImplementation(method), to: AddMonitorIMP.self)
        dragMonitor = function(eventClass, selector, mask, handler)
    }

    @MainActor
    private static func trackMiniPlayerDrag(_ event: AnyObject) {
        guard let window = shrunkWindow,
              let origin = dragWindowOrigin,
              let start = dragMouseOrigin,
              let mouse = quartzMouseLocation()
        else {
            stopDragMonitor()
            return
        }
        var frame = CGRect(origin: origin, size: miniSize)
        frame.origin.x = origin.x + (mouse.x - start.x)
        frame.origin.y = origin.y - (mouse.y - start.y)
        setFrame(frame, of: window)
        if eventType(event) == 2 {
            rememberMiniOrigin()
            stopDragMonitor()
        }
    }

    @MainActor
    static func endMiniDrag() {
        rememberMiniOrigin()
        stopDragMonitor()
    }

    private static func stopDragMonitor() {
        if let monitor = dragMonitor, let eventClass = NSClassFromString("NSEvent") as? NSObject.Type {
            _ = eventClass.perform(NSSelectorFromString("removeMonitor:"), with: monitor)
        }
        dragMonitor = nil
        dragWindowOrigin = nil
        dragMouseOrigin = nil
    }

    /// Quartz global location, origin at the top-left of the main display. Deltas are flipped into AppKit's y-up space.
    private static func quartzMouseLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    private static func eventType(_ event: AnyObject) -> UInt? {
        guard let object = event as? NSObject else { return nil }
        let selector = NSSelectorFromString("type")
        guard object.responds(to: selector) else { return nil }
        typealias TypeIMP = @convention(c) (AnyObject, Selector) -> UInt
        let function = unsafeBitCast(object.method(for: selector), to: TypeIMP.self)
        return function(object, selector)
    }

    private static let miniOriginXKey = "ytlite.mac.mini-player.x"
    private static let miniOriginYKey = "ytlite.mac.mini-player.y"

    private static func miniFrame(near current: CGRect?) -> CGRect {
        let visible = screenVisibleFrame(containing: current)
            ?? CGRect(x: 0, y: 80, width: 1280, height: 800)
        let fallback = CGRect(
            x: visible.midX - miniSize.width / 2,
            y: visible.minY + 28,
            width: miniSize.width,
            height: miniSize.height
        )
        guard let origin = savedMiniOrigin() else { return fallback }
        return clampedMiniFrame(CGRect(origin: origin, size: miniSize), fallback: fallback)
    }

    private static func savedMiniOrigin() -> CGPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: miniOriginXKey) != nil,
              defaults.object(forKey: miniOriginYKey) != nil else { return nil }
        return CGPoint(x: defaults.double(forKey: miniOriginXKey), y: defaults.double(forKey: miniOriginYKey))
    }

    @MainActor
    private static func rememberMiniOrigin() {
        guard MacWindowChrome.shared.isMinimizedToPlayer,
              let window = shrunkWindow,
              let frame = rect(window.value(forKey: "frame")) else { return }
        let defaults = UserDefaults.standard
        defaults.set(Double(frame.origin.x), forKey: miniOriginXKey)
        defaults.set(Double(frame.origin.y), forKey: miniOriginYKey)
    }

    /// Keep a remembered origin on a connected display. A missing screen falls back to the bottom center.
    private static func clampedMiniFrame(_ frame: CGRect, fallback: CGRect) -> CGRect {
        let screens = visibleScreenFrames()
        guard !screens.isEmpty else { return frame }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = screens.first(where: { $0.contains(center) }) ?? screens.first(where: { $0.intersects(frame) }) else {
            return fallback
        }
        var result = frame
        result.origin.x = min(max(frame.origin.x, screen.minX), screen.maxX - frame.width)
        result.origin.y = min(max(frame.origin.y, screen.minY), screen.maxY - frame.height)
        return result
    }

    private static func scene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    private static func saveSizeRestrictions() {
        guard savedMinimumSize == nil, let restrictions = scene()?.sizeRestrictions else { return }
        savedMinimumSize = restrictions.minimumSize
        savedMaximumSize = restrictions.maximumSize
    }

    private static func restoreSizeRestrictions() {
        guard let restrictions = scene()?.sizeRestrictions else { return }
        if let savedMinimumSize {
            restrictions.minimumSize = savedMinimumSize
        }
        if let savedMaximumSize {
            restrictions.maximumSize = savedMaximumSize
        }
        savedMinimumSize = nil
        savedMaximumSize = nil
    }

    /// Scene limits are what actually resize a Catalyst window. Set the floor before the ceiling.
    private static func applyMiniFrame(_ frame: CGRect, of window: NSObject) {
        if let restrictions = scene()?.sizeRestrictions {
            restrictions.minimumSize = frame.size
            restrictions.maximumSize = frame.size
        }
        setSize(frame.size, "setContentMinSize:", of: window)
        setSize(frame.size, "setMinSize:", of: window)
        setSize(frame.size, "setContentMaxSize:", of: window)
        setSize(frame.size, "setMaxSize:", of: window)
        requestFrame(frame, of: window)
    }

    private static func requestFrame(_ frame: CGRect, of window: NSObject) {
        scene()?.requestGeometryUpdate(UIWindowScene.GeometryPreferences.Mac(systemFrame: frame)) { _ in }
        setFrame(frame, of: window)
    }

    private static func saveChrome(of window: NSObject) {
        guard savedStyleMask == nil else { return }
        savedStyleMask = (window.value(forKey: "styleMask") as? NSNumber)?.uintValue
        savedTitle = window.value(forKey: "title") as? String
        savedTitleVisibility = (window.value(forKey: "titleVisibility") as? NSNumber)?.intValue
        savedTitlebarTransparent = window.value(forKey: "titlebarAppearsTransparent") as? Bool
        savedSeparatorStyle = (window.value(forKey: "titlebarSeparatorStyle") as? NSNumber)?.intValue
        savedOpaque = window.value(forKey: "opaque") as? Bool
        savedBackground = window.value(forKey: "backgroundColor") as? AnyObject
    }

    private static func applyMiniChrome(to window: NSObject) {
        if applyingChrome { return }
        applyingChrome = true
        defer { applyingChrome = false }
        var mask = (window.value(forKey: "styleMask") as? NSNumber)?.uintValue ?? 0
        mask |= 1 << 15 // fullSizeContentView, so the player fills the title-bar area
        setUInt(mask, "setStyleMask:", of: window)
        setInt(1, "setTitleVisibility:", of: window)
        window.setValue(true, forKey: "titlebarAppearsTransparent")
        setInt(1, "setTitlebarSeparatorStyle:", of: window)
        window.setValue("", forKey: "title")
        window.setValue(false, forKey: "opaque")
        if let clear = clearColor() {
            window.setValue(clear, forKey: "backgroundColor")
        }
        for kind: UInt in 0...2 {
            setStandardButton(kind, hidden: true, of: window)
        }
    }

    private static func restoreChrome(of window: NSObject) {
        applyingChrome = true
        defer { applyingChrome = false }
        if let savedStyleMask {
            setUInt(savedStyleMask, "setStyleMask:", of: window)
        }
        if let savedTitleVisibility {
            setInt(savedTitleVisibility, "setTitleVisibility:", of: window)
        }
        if let savedTitlebarTransparent {
            window.setValue(savedTitlebarTransparent, forKey: "titlebarAppearsTransparent")
        }
        if let savedSeparatorStyle {
            setInt(savedSeparatorStyle, "setTitlebarSeparatorStyle:", of: window)
        }
        if let savedTitle {
            window.setValue(savedTitle, forKey: "title")
        }
        if let savedOpaque {
            window.setValue(savedOpaque, forKey: "opaque")
        }
        if let savedBackground {
            window.setValue(savedBackground, forKey: "backgroundColor")
        }
        for kind: UInt in 0...2 {
            setStandardButton(kind, hidden: false, of: window)
        }
        let minSize = savedMinimumSize ?? CGSize(width: 720, height: 480)
        let maxSize = savedMaximumSize ?? CGSize(width: 16_000, height: 16_000)
        setSize(minSize, "setContentMinSize:", of: window)
        setSize(minSize, "setMinSize:", of: window)
        setSize(maxSize, "setContentMaxSize:", of: window)
        setSize(maxSize, "setMaxSize:", of: window)
        savedStyleMask = nil
        savedTitle = nil
        savedTitleVisibility = nil
        savedTitlebarTransparent = nil
        savedSeparatorStyle = nil
        savedOpaque = nil
        savedBackground = nil
    }

    private static func clearColor() -> AnyObject? {
        guard let colorClass = NSClassFromString("NSColor") as? NSObject.Type else { return nil }
        return colorClass.perform(NSSelectorFromString("clearColor"))?.takeUnretainedValue()
    }

    private static func setStandardButton(_ kind: UInt, hidden: Bool, of window: NSObject) {
        let selector = NSSelectorFromString("standardWindowButton:")
        guard window.responds(to: selector) else { return }
        typealias ButtonIMP = @convention(c) (AnyObject, Selector, UInt) -> AnyObject?
        let function = unsafeBitCast(window.method(for: selector), to: ButtonIMP.self)
        guard let button = function(window, selector, kind) as? NSObject else { return }
        button.setValue(hidden, forKey: "hidden")
    }

    private static func setUInt(_ value: UInt, _ name: String, of window: NSObject) {
        let selector = NSSelectorFromString(name)
        guard window.responds(to: selector) else { return }
        typealias SetterIMP = @convention(c) (AnyObject, Selector, UInt) -> Void
        let function = unsafeBitCast(window.method(for: selector), to: SetterIMP.self)
        function(window, selector, value)
    }

    private static func setInt(_ value: Int, _ name: String, of window: NSObject) {
        let selector = NSSelectorFromString(name)
        guard window.responds(to: selector) else { return }
        typealias SetterIMP = @convention(c) (AnyObject, Selector, Int) -> Void
        let function = unsafeBitCast(window.method(for: selector), to: SetterIMP.self)
        function(window, selector, value)
    }

    private static func setSize(_ size: CGSize, _ name: String, of window: NSObject) {
        let selector = NSSelectorFromString(name)
        guard window.responds(to: selector) else { return }
        typealias SetterIMP = @convention(c) (AnyObject, Selector, CGSize) -> Void
        let function = unsafeBitCast(window.method(for: selector), to: SetterIMP.self)
        function(window, selector, size)
    }

    /// UIKit puts the title bar back after layout. Put the player chrome back while the window is shrunk.
    private static func swizzleSetStyleMask(on cls: AnyClass) {
        let selector = NSSelectorFromString("setStyleMask:")
        guard ownsMethod(selector, on: cls),
              let method = class_getInstanceMethod(cls, selector)
        else { return }
        typealias StyleIMP = @convention(c) (AnyObject, Selector, UInt) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: StyleIMP.self)
        let block: @convention(block) (AnyObject, UInt) -> Void = { window, mask in
            original(window, selector, mask)
            if MacAppLifetime.applyingChrome { return }
            guard let object = window as? NSObject else { return }
            let shouldHide = MainActor.assumeIsolated {
                MacWindowChrome.shared.isMinimizedToPlayer && MacAppLifetime.hidesOnClose(object)
            }
            if shouldHide {
                MainActor.assumeIsolated {
                    MacAppLifetime.applyMiniChrome(to: object)
                }
            }
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private static func screenVisibleFrame(containing rect: CGRect?) -> CGRect? {
        let screens = visibleScreenFrames()
        if let rect {
            for screen in screens where screen.intersects(rect) {
                return screen
            }
        }
        return screens.first
    }

    private static func visibleScreenFrames() -> [CGRect] {
        guard let screenClass = NSClassFromString("NSScreen") as? NSObject.Type else { return [] }
        let raw = screenClass.perform(NSSelectorFromString("screens"))?.takeUnretainedValue()
        let screens = raw as? [NSObject] ?? (raw as? NSArray)?.compactMap { $0 as? NSObject } ?? []
        let frames = screens.compactMap { rect($0.value(forKey: "visibleFrame")) }
        if !frames.isEmpty { return frames }
        let main = screenClass.perform(NSSelectorFromString("mainScreen"))?.takeUnretainedValue() as? NSObject
        return main.flatMap { rect($0.value(forKey: "visibleFrame")) }.map { [$0] } ?? []
    }

    private static func rect(_ value: Any?) -> CGRect? {
        (value as? NSValue)?.cgRectValue
    }

    private static func setFrame(_ rect: CGRect, of window: NSObject) {
        let selector = NSSelectorFromString("setFrame:display:")
        guard window.responds(to: selector) else { return }
        typealias SetFrameIMP = @convention(c) (AnyObject, Selector, CGRect, Bool) -> Void
        let function = unsafeBitCast(window.method(for: selector), to: SetFrameIMP.self)
        function(window, selector, rect, true)
    }

    private static func setLevel(_ level: Int, of window: NSObject) {
        let selector = NSSelectorFromString("setLevel:")
        guard window.responds(to: selector) else { return }
        typealias SetLevelIMP = @convention(c) (AnyObject, Selector, Int) -> Void
        let function = unsafeBitCast(window.method(for: selector), to: SetLevelIMP.self)
        function(window, selector, level)
    }

    private static func setCollectionBehavior(_ behavior: UInt, of window: NSObject) {
        let selector = NSSelectorFromString("setCollectionBehavior:")
        guard window.responds(to: selector) else { return }
        typealias SetBehaviorIMP = @convention(c) (AnyObject, Selector, UInt) -> Void
        let function = unsafeBitCast(window.method(for: selector), to: SetBehaviorIMP.self)
        function(window, selector, behavior)
    }

    private static func swizzleMiniaturize(on cls: AnyClass) {
        let selector = NSSelectorFromString("miniaturize:")
        guard ownsMethod(selector, on: cls),
              let method = class_getInstanceMethod(cls, selector)
        else { return }
        typealias MiniaturizeIMP = @convention(c) (AnyObject, Selector, Any?) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: MiniaturizeIMP.self)
        let block: @convention(block) (AnyObject, Any?) -> Void = { window, sender in
            guard let object = window as? NSObject else {
                original(window, selector, sender)
                return
            }
            let shrink = MainActor.assumeIsolated {
                let chrome = MacWindowChrome.shared
                return !chrome.isMinimizedToPlayer && chrome.hasNowPlaying && MacAppLifetime.hidesOnClose(object)
            }
            if shrink {
                MainActor.assumeIsolated {
                    MacAppLifetime.shrinkToMiniPlayer(object)
                }
            } else {
                original(window, selector, sender)
            }
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private static func swizzleZoom(on cls: AnyClass) {
        let selector = NSSelectorFromString("zoom:")
        guard ownsMethod(selector, on: cls),
              let method = class_getInstanceMethod(cls, selector)
        else { return }
        typealias ZoomIMP = @convention(c) (AnyObject, Selector, Any?) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: ZoomIMP.self)
        let block: @convention(block) (AnyObject, Any?) -> Void = { window, sender in
            let shrunk = MainActor.assumeIsolated { MacWindowChrome.shared.isMinimizedToPlayer }
            if shrunk {
                MainActor.assumeIsolated {
                    MacAppLifetime.restoreShrunkWindow()
                }
                return
            }
            original(window, selector, sender)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
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

@MainActor
final class MacWindowChrome: ObservableObject {
    static let shared = MacWindowChrome()
    @Published var isMinimizedToPlayer = false
    var hasNowPlaying = false
}
#endif
