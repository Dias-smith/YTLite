import Foundation
import WatchConnectivity
#if os(iOS)
import UIKit
#endif

/// Thin `WCSession` façade shared by iPhone host and Watch client.
@MainActor
final class WatchConnectivityBridge: NSObject, ObservableObject {
    static let shared = WatchConnectivityBridge()

    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    @Published private(set) var isReachable: Bool = false
    /// watchOS: whether the companion iPhone app is installed.
    @Published private(set) var isCompanionAppInstalled: Bool = true
    /// iOS: whether the paired Watch has this companion app installed.
    @Published private(set) var isWatchAppInstalled: Bool = false
    /// iOS: whether a Watch is paired.
    @Published private(set) var isPaired: Bool = false
    /// iOS: Watch sent us at least one interactive message this process (Xcode direct-install recovery).
    @Published private(set) var hasWatchCounterpartSession: Bool = false
    @Published private(set) var lastErrorMessage: String?

    private var session: WCSession?
    private var handlers: [@MainActor (WatchConnectivityProtocol.Envelope) -> Void] = []
    private var didActivate = false
    /// Latest Now Playing context to flush once `WCSession` activates.
    private var pendingApplicationContext: WatchConnectivityProtocol.Envelope?
    /// Interactive / queue payloads queued until activation completes.
    private var pendingTransfers: [WatchConnectivityProtocol.Envelope] = []
    #if os(iOS)
    private var didLogWaitingForWatchInstall = false
    #endif
    #if os(watchOS)
    /// `isReachable` can stay true while sendMessage always times out (Xcode sideload / stale WC).
    private var interactiveSendSuspended = false
    private var didLogInteractiveSuspend = false
    #endif
    private var lastBackgroundTransferAt: [String: Date] = [:]
    private var isFlushingPending = false
    #if targetEnvironment(simulator)
    private var simulatorLinkConnected = false
    #endif

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            lastErrorMessage = "WatchConnectivity unsupported"
            return
        }
        #if targetEnvironment(simulator)
        startSimulatorLinkIfNeeded()
        #endif
        let session = WCSession.default
        self.session = session
        session.delegate = self
        if session.activationState == .activated {
            activationState = .activated
            refreshReachability()
            flushPending()
            return
        }
        if !didActivate {
            didActivate = true
            session.activate()
        }
        refreshReachability()
    }

    #if targetEnvironment(simulator)
    private func startSimulatorLinkIfNeeded() {
        let link = SimulatorWatchLocalLink.shared
        link.onEnvelope = { [weak self] envelope in
            self?.dispatch(envelope)
        }
        link.onConnectedChange = { [weak self] connected in
            guard let self else { return }
            self.simulatorLinkConnected = connected
            self.refreshReachability()
            if connected {
                self.flushPending()
                print("[YTLite.WatchConnectivity] simulator link up — treating counterpart as reachable")
            }
        }
        link.start()
        simulatorLinkConnected = link.isConnected
    }

    @discardableResult
    private func sendViaSimulatorLink(_ envelope: WatchConnectivityProtocol.Envelope) -> Bool {
        SimulatorWatchLocalLink.shared.send(envelope)
    }
    #endif

    func onEnvelope(_ handler: @escaping @MainActor (WatchConnectivityProtocol.Envelope) -> Void) {
        handlers.append(handler)
    }

    /// Whether the phone should spend work pushing Watch snapshots / transfers.
    var isWatchDeliveryAvailable: Bool {
        #if targetEnvironment(simulator)
        return simulatorLinkConnected || isReachable
        #elseif os(iOS)
        // `isWatchAppInstalled` stays false when the Watch app was installed only via Xcode
        // Watch scheme (not through the iPhone Watch app). Still deliver if reachable or we've
        // already received an interactive message from the Watch.
        return isWatchAppInstalled || isReachable || hasWatchCounterpartSession
        #else
        return isReachable
        #endif
    }

    @discardableResult
    func send(_ envelope: WatchConnectivityProtocol.Envelope, reply: ((Result<WatchConnectivityProtocol.Envelope, Error>) -> Void)? = nil) -> Bool {
        #if targetEnvironment(simulator)
        if sendViaSimulatorLink(envelope) {
            if let reply {
                let ack = WatchConnectivityProtocol.Envelope(
                    kind: .ack,
                    payload: try? JSONEncoder().encode(
                        WatchConnectivityProtocol.AckBody(requestId: envelope.id, ok: true, message: "simulator-link")
                    )
                )
                reply(.success(ack))
            }
            return true
        }
        #endif

        guard let session, session.activationState == .activated else {
            pendingTransfers.append(envelope)
            // Cap queue to avoid unbounded growth while waiting for activate.
            if pendingTransfers.count > 32 {
                pendingTransfers.removeFirst(pendingTransfers.count - 32)
            }
            reply?(.failure(BridgeError.notActivated))
            return false
        }

        do {
            let data = try JSONEncoder().encode(envelope)
            let message: [String: Any] = ["envelope": data]

            #if os(watchOS)
            let allowInteractive = session.isReachable && !interactiveSendSuspended
            #else
            let allowInteractive = session.isReachable
            #endif

            if allowInteractive {
                // Prefer no-reply for fire-and-forget; reply timeouts drop Watch→Phone handshakes.
                if let reply {
                    session.sendMessage(message, replyHandler: { replyMessage in
                        Task { @MainActor in
                            do {
                                let replyEnvelope = try Self.decodeEnvelope(from: replyMessage)
                                reply(.success(replyEnvelope))
                            } catch {
                                reply(.failure(error))
                            }
                        }
                    }, errorHandler: { error in
                        Task { @MainActor in
                            self.noteInteractiveSendFailure(error)
                            self.queueBackgroundTransfer(message, kind: envelope.kind.rawValue)
                            reply(.failure(error))
                        }
                    })
                } else {
                    session.sendMessage(message, replyHandler: nil, errorHandler: { error in
                        Task { @MainActor in
                            self.noteInteractiveSendFailure(error)
                            self.queueBackgroundTransfer(message, kind: envelope.kind.rawValue)
                        }
                    })
                }
                return true
            }

            queueBackgroundTransfer(message, kind: envelope.kind.rawValue)
            if let reply {
                let ack = WatchConnectivityProtocol.Envelope(
                    kind: .ack,
                    payload: try? JSONEncoder().encode(
                        WatchConnectivityProtocol.AckBody(requestId: envelope.id, ok: true, message: "queued")
                    )
                )
                reply(.success(ack))
            }
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            reply?(.failure(error))
            return false
        }
    }

    private func noteInteractiveSendFailure(_ error: Error) {
        lastErrorMessage = error.localizedDescription
        #if os(watchOS)
        interactiveSendSuspended = true
        if !didLogInteractiveSuspend {
            didLogInteractiveSuspend = true
            print("[YTLite.WatchConnectivity] sendMessage failed: \(error.localizedDescription) — using background transfers until reachability flips")
        }
        #else
        print("[YTLite.WatchConnectivity] sendMessage failed: \(error.localizedDescription) — queued transferUserInfo")
        #endif
    }

    private func queueBackgroundTransfer(_ message: [String: Any], kind: String) {
        guard let session, session.activationState == .activated else { return }
        // Avoid flooding outstandingUserInfoTransfers from the Watch retry loop.
        if session.outstandingUserInfoTransfers.count >= 8 { return }
        let now = Date()
        if let last = lastBackgroundTransferAt[kind], now.timeIntervalSince(last) < 3.0 {
            return
        }
        lastBackgroundTransferAt[kind] = now
        session.transferUserInfo(message)
    }

    @discardableResult
    func updateApplicationContext(_ envelope: WatchConnectivityProtocol.Envelope) -> Bool {
        #if targetEnvironment(simulator)
        // Prefer localhost link on Simulator; WC applicationContext usually fails with "not installed".
        if sendViaSimulatorLink(envelope) {
            pendingApplicationContext = nil
            return true
        }
        pendingApplicationContext = envelope
        return false
        #else
        guard let session, session.activationState == .activated else {
            pendingApplicationContext = envelope
            return false
        }
        #if os(iOS)
        // applicationContext requires a recognized companion install; skip when only reachable.
        guard session.isWatchAppInstalled else {
            return false
        }
        #endif
        // watchOS: always allowed — used as Watch→Phone handshake when sendMessage times out.
        do {
            let data = try JSONEncoder().encode(envelope)
            try session.updateApplicationContext([
                "envelopeBase64": data.base64EncodedString(),
                "envelope": data
            ])
            pendingApplicationContext = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            pendingApplicationContext = envelope
            print("[YTLite.WatchConnectivity] updateApplicationContext failed: \(error.localizedDescription)")
            return false
        }
        #endif
    }

    func transferUserInfo(_ envelope: WatchConnectivityProtocol.Envelope) {
        #if targetEnvironment(simulator)
        if sendViaSimulatorLink(envelope) { return }
        pendingTransfers.append(envelope)
        if pendingTransfers.count > 32 {
            pendingTransfers.removeFirst(pendingTransfers.count - 32)
        }
        #else
        guard let session, session.activationState == .activated else { return }
        guard canAttemptWatchDelivery else { return }
        do {
            let data = try JSONEncoder().encode(envelope)
            queueBackgroundTransfer(["envelope": data], kind: envelope.kind.rawValue)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        #endif
    }

    /// True when WCSession APIs other than applicationContext may be used.
    private var canAttemptWatchDelivery: Bool {
        guard let session, session.activationState == .activated else { return false }
        #if os(iOS)
        #if targetEnvironment(simulator)
        return true
        #else
        return session.isWatchAppInstalled || session.isReachable || hasWatchCounterpartSession
        #endif
        #else
        return true
        #endif
    }

    private func flushPending() {
        guard !isFlushingPending else { return }
        isFlushingPending = true
        defer { isFlushingPending = false }
        #if targetEnvironment(simulator)
        guard simulatorLinkConnected else {
            print("[YTLite.WatchConnectivity] waiting for Simulator file-link peer")
            return
        }
        if let pending = pendingApplicationContext {
            _ = updateApplicationContext(pending)
        }
        let queued = pendingTransfers
        pendingTransfers.removeAll()
        for envelope in queued {
            _ = send(envelope)
        }
        print("[YTLite.WatchConnectivity] simulator flush link=true transfers=\(queued.count)")
        #else
        guard let session, session.activationState == .activated else { return }
        #if os(iOS)
        // Pick up Watch→Phone applicationContext that arrived before hosts bound.
        if let pendingContext = receivedApplicationContextEnvelope() {
            dispatch(pendingContext)
        }
        if !canAttemptWatchDelivery {
            if !didLogWaitingForWatchInstall {
                didLogWaitingForWatchInstall = true
                if session.isPaired, !session.isWatchAppInstalled {
                    print("[YTLite.WatchConnectivity] Watch not ready (paired=true installed=false reachable=\(session.isReachable)) — keep MixtubeWatch open; if this stays false, reinstall via iPhone scheme (embeds Watch) or Watch app → Available Apps")
                } else {
                    print("[YTLite.WatchConnectivity] Watch not ready (paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable)) — open MixtubeWatch on the Watch")
                }
            }
            return
        }
        didLogWaitingForWatchInstall = false
        #endif
        if let pending = pendingApplicationContext {
            _ = updateApplicationContext(pending)
        }
        let queued = pendingTransfers
        pendingTransfers.removeAll()
        for envelope in queued {
            _ = send(envelope)
        }
        #if os(iOS)
        print("[YTLite.WatchConnectivity] iPhone session ready paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable) pendingContext=\(pendingApplicationContext != nil) flushedTransfers=\(queued.count)")
        #else
        print("[YTLite.WatchConnectivity] Watch session ready companionInstalled=\(session.isCompanionAppInstalled) reachable=\(session.isReachable) flushedTransfers=\(queued.count)")
        #endif
        #endif
    }

    func receivedApplicationContextEnvelope() -> WatchConnectivityProtocol.Envelope? {
        guard let session, session.activationState == .activated else { return nil }
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return nil }
        return try? Self.decodeEnvelope(from: context)
    }

    private func refreshReachability() {
        #if os(iOS)
        let wasAvailable = isWatchDeliveryAvailable
        #endif
        #if os(watchOS)
        let wasReachable = isReachable
        #endif
        #if targetEnvironment(simulator)
        isReachable = simulatorLinkConnected || (session?.isReachable ?? false)
        #else
        isReachable = session?.isReachable ?? false
        #endif
        #if os(watchOS)
        // Clear stale interactive suspension when the system reports a reachability edge.
        if !wasReachable, isReachable {
            interactiveSendSuspended = false
            didLogInteractiveSuspend = false
        }
        #endif
        #if os(iOS)
        isPaired = session?.isPaired ?? false
        #if targetEnvironment(simulator)
        isWatchAppInstalled = simulatorLinkConnected || (session?.isWatchAppInstalled ?? false)
        #else
        isWatchAppInstalled = session?.isWatchAppInstalled ?? false
        #endif
        if !wasAvailable, isWatchDeliveryAvailable {
            print("[YTLite.WatchConnectivity] Watch counterpart available installed=\(isWatchAppInstalled) reachable=\(isReachable) counterpartSession=\(hasWatchCounterpartSession) — flushing")
            didLogWaitingForWatchInstall = false
            flushPending()
        }
        #endif
        #if os(watchOS)
        #if targetEnvironment(simulator)
        isCompanionAppInstalled = simulatorLinkConnected || (session?.isCompanionAppInstalled ?? true)
        #else
        isCompanionAppInstalled = session?.isCompanionAppInstalled ?? true
        #endif
        #endif
    }

    private func noteWatchCounterpartSession() {
        #if os(iOS)
        let wasAvailable = isWatchDeliveryAvailable
        if !hasWatchCounterpartSession {
            hasWatchCounterpartSession = true
            print("[YTLite.WatchConnectivity] interactive Watch session detected")
        }
        if !wasAvailable, isWatchDeliveryAvailable {
            didLogWaitingForWatchInstall = false
            flushPending()
        }
        #endif
    }

    private func dispatch(_ envelope: WatchConnectivityProtocol.Envelope) {
        noteWatchCounterpartSession()
        print("[YTLite.WatchConnectivity] recv kind=\(envelope.kind.rawValue)")
        for handler in handlers {
            handler(envelope)
        }
    }

    #if os(iOS)
    private func withBackgroundTask(_ work: @escaping @MainActor () -> Void) {
        var taskId = UIBackgroundTaskIdentifier.invalid
        taskId = UIApplication.shared.beginBackgroundTask(withName: "YTLiteWatchConnectivity") {
            if taskId != .invalid {
                UIApplication.shared.endBackgroundTask(taskId)
                taskId = .invalid
            }
        }
        Task { @MainActor in
            work()
            if taskId != .invalid {
                UIApplication.shared.endBackgroundTask(taskId)
                taskId = .invalid
            }
        }
    }
    #endif

    nonisolated private static func decodeEnvelope(from message: [String: Any]) throws -> WatchConnectivityProtocol.Envelope {
        if let data = message["envelope"] as? Data {
            let envelope = try JSONDecoder().decode(WatchConnectivityProtocol.Envelope.self, from: data)
            if envelope.version > WatchConnectivityProtocol.protocolVersion {
                throw WatchConnectivityProtocol.ProtocolError.unsupportedVersion(envelope.version)
            }
            return envelope
        }
        if let b64 = message["envelopeBase64"] as? String,
           let data = Data(base64Encoded: b64) {
            let envelope = try JSONDecoder().decode(WatchConnectivityProtocol.Envelope.self, from: data)
            if envelope.version > WatchConnectivityProtocol.protocolVersion {
                throw WatchConnectivityProtocol.ProtocolError.unsupportedVersion(envelope.version)
            }
            return envelope
        }
        throw BridgeError.invalidMessage
    }

    enum BridgeError: Error {
        case notActivated
        case invalidMessage
    }
}

extension WatchConnectivityBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.activationState = activationState
            if let error {
                self.lastErrorMessage = error.localizedDescription
                print("[YTLite.WatchConnectivity] activation error: \(error.localizedDescription)")
            }
            self.refreshReachability()
            if activationState == .activated {
                self.flushPending()
            }
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.refreshReachability()
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            session.activate()
            self.refreshReachability()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            print("[YTLite.WatchConnectivity] watchStateDidChange paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")
            self.refreshReachability()
        }
    }
    #endif

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshReachability()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let decoded = Result { try Self.decodeEnvelope(from: message) }
        Task { @MainActor in
            #if os(iOS)
            self.withBackgroundTask {
                self.applyDecodedMessage(decoded)
            }
            #else
            self.applyDecodedMessage(decoded)
            #endif
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        // Reply immediately on the WCSession queue — delayed MainActor hops time out on Watch.
        let decoded = Result { try Self.decodeEnvelope(from: message) }
        switch decoded {
        case .success(let envelope):
            let ack = WatchConnectivityProtocol.Envelope(
                kind: .ack,
                payload: try? JSONEncoder().encode(
                    WatchConnectivityProtocol.AckBody(requestId: envelope.id, ok: true, message: nil)
                )
            )
            if let data = try? JSONEncoder().encode(ack) {
                replyHandler(["envelope": data])
            } else {
                replyHandler([:])
            }
        case .failure(let error):
            let err = WatchConnectivityProtocol.Envelope(
                kind: .error,
                payload: try? JSONEncoder().encode(
                    WatchConnectivityProtocol.ErrorBody(
                        requestId: nil,
                        code: "decode",
                        message: error.localizedDescription
                    )
                )
            )
            if let data = try? JSONEncoder().encode(err) {
                replyHandler(["envelope": data])
            } else {
                replyHandler([:])
            }
        }
        Task { @MainActor in
            #if os(iOS)
            self.withBackgroundTask {
                self.applyDecodedMessage(decoded)
            }
            #else
            self.applyDecodedMessage(decoded)
            #endif
        }
    }

    @MainActor
    private func applyDecodedMessage(_ decoded: Result<WatchConnectivityProtocol.Envelope, Error>) {
        switch decoded {
        case .success(let envelope):
            dispatch(envelope)
        case .failure(let error):
            lastErrorMessage = error.localizedDescription
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        #if os(iOS)
        Task { @MainActor in
            self.withBackgroundTask {
                do {
                    let envelope = try Self.decodeEnvelope(from: userInfo)
                    self.dispatch(envelope)
                } catch {
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
        #else
        Task { @MainActor in
            do {
                let envelope = try Self.decodeEnvelope(from: userInfo)
                self.dispatch(envelope)
            } catch {
                self.lastErrorMessage = error.localizedDescription
            }
        }
        #endif
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            do {
                let envelope = try Self.decodeEnvelope(from: applicationContext)
                self.dispatch(envelope)
            } catch {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }
}

#if targetEnvironment(simulator)
/// Simulator-only file IPC via `/tmp` (shared by iPhone + Watch simulators on the Mac).
/// TCP localhost fails because Watch Simulator does not share the phone's loopback.
@MainActor
final class SimulatorWatchLocalLink {
    static let shared = SimulatorWatchLocalLink()

    private static let rootPath = "/tmp/ytlite.watchsim"
    private static let peerTimeout: TimeInterval = 6

    private(set) var isConnected = false
    var onConnectedChange: (@MainActor (Bool) -> Void)?
    var onEnvelope: (@MainActor (WatchConnectivityProtocol.Envelope) -> Void)?

    private var didStart = false
    private var pollTask: Task<Void, Never>?
    private let fileManager = FileManager.default

    #if os(iOS)
    private var outboxName: String { "to-watch" }
    private var inboxName: String { "to-phone" }
    private var selfAliveName: String { "phone.alive" }
    private var peerAliveName: String { "watch.alive" }
    #else
    private var outboxName: String { "to-phone" }
    private var inboxName: String { "to-watch" }
    private var selfAliveName: String { "watch.alive" }
    private var peerAliveName: String { "phone.alive" }
    #endif

    private init() {}

    func start() {
        guard !didStart else { return }
        didStart = true
        ensureDirectories()
        touchAlive()
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            print("[YTLite.WatchConnectivity] simulator file-link ready at \(Self.rootPath)")
            while !Task.isCancelled {
                self.touchAlive()
                self.drainInbox()
                self.refreshPeerConnection()
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    @discardableResult
    func send(_ envelope: WatchConnectivityProtocol.Envelope) -> Bool {
        ensureDirectories()
        do {
            let data = try JSONEncoder().encode(envelope)
            let name = String(format: "%.6f-%@.json", Date().timeIntervalSince1970, UUID().uuidString)
            let url = outboxURL().appendingPathComponent(name)
            let tmp = url.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            try fileManager.moveItem(at: tmp, to: url)
            return true
        } catch {
            print("[YTLite.WatchConnectivity] simulator file-link send error: \(error)")
            return false
        }
    }

    private func ensureDirectories() {
        for name in ["to-watch", "to-phone"] {
            let url = URL(fileURLWithPath: Self.rootPath).appendingPathComponent(name)
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func outboxURL() -> URL {
        URL(fileURLWithPath: Self.rootPath).appendingPathComponent(outboxName)
    }

    private func inboxURL() -> URL {
        URL(fileURLWithPath: Self.rootPath).appendingPathComponent(inboxName)
    }

    private func aliveURL(_ name: String) -> URL {
        URL(fileURLWithPath: Self.rootPath).appendingPathComponent(name)
    }

    private func touchAlive() {
        let payload = String(Date().timeIntervalSince1970).data(using: .utf8) ?? Data()
        try? payload.write(to: aliveURL(selfAliveName), options: .atomic)
    }

    private func refreshPeerConnection() {
        let peerURL = aliveURL(peerAliveName)
        guard
            let data = try? Data(contentsOf: peerURL),
            let text = String(data: data, encoding: .utf8),
            let stamp = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            setConnected(false)
            return
        }
        setConnected(Date().timeIntervalSince1970 - stamp <= Self.peerTimeout)
    }

    private func setConnected(_ connected: Bool) {
        guard isConnected != connected else { return }
        isConnected = connected
        onConnectedChange?(connected)
        print("[YTLite.WatchConnectivity] simulator file-link peer \(connected ? "up" : "down")")
    }

    private func drainInbox() {
        let inbox = inboxURL()
        guard let files = try? fileManager.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let jsonFiles = files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for file in jsonFiles {
            defer { try? fileManager.removeItem(at: file) }
            do {
                let data = try Data(contentsOf: file)
                let envelope = try JSONDecoder().decode(WatchConnectivityProtocol.Envelope.self, from: data)
                onEnvelope?(envelope)
            } catch {
                print("[YTLite.WatchConnectivity] simulator file-link decode error: \(error)")
            }
        }
    }
}
#endif
