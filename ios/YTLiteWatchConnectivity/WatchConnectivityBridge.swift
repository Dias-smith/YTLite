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
    @Published private(set) var lastErrorMessage: String?

    private var session: WCSession?
    private var handlers: [@MainActor (WatchConnectivityProtocol.Envelope) -> Void] = []
    private var didActivate = false
    /// Latest Now Playing context to flush once `WCSession` activates.
    private var pendingApplicationContext: WatchConnectivityProtocol.Envelope?
    /// Interactive / queue payloads queued until activation completes.
    private var pendingTransfers: [WatchConnectivityProtocol.Envelope] = []
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
        return isWatchAppInstalled || isReachable
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
            enqueuePending(envelope)
            reply?(.failure(BridgeError.notActivated))
            return false
        }

        do {
            let data = try JSONEncoder().encode(envelope)
            let message: [String: Any] = ["envelope": data]

            if session.isReachable {
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
                    }, errorHandler: { _ in
                        Task { @MainActor in
                            // Stale isReachable is common; background delivery still works — don't surface WC noise.
                            self.deliverViaBackground(message, kind: envelope.kind.rawValue, requestId: envelope.id, reply: reply)
                        }
                    })
                } else {
                    session.sendMessage(message, replyHandler: nil, errorHandler: { _ in
                        Task { @MainActor in
                            self.deliverViaBackground(message, kind: envelope.kind.rawValue, requestId: envelope.id, reply: nil)
                        }
                    })
                }
                return true
            }

            deliverViaBackground(message, kind: envelope.kind.rawValue, requestId: envelope.id, reply: reply)
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            reply?(.failure(error))
            return false
        }
    }

    /// Queues `transferUserInfo` without treating interactive-send failure as a user-visible error.
    private func deliverViaBackground(
        _ message: [String: Any],
        kind: String,
        requestId: String,
        reply: ((Result<WatchConnectivityProtocol.Envelope, Error>) -> Void)?
    ) {
        queueBackgroundTransfer(message, kind: kind)
        guard let reply else { return }
        let ack = WatchConnectivityProtocol.Envelope(
            kind: .ack,
            payload: try? JSONEncoder().encode(
                WatchConnectivityProtocol.AckBody(requestId: requestId, ok: true, message: "queued")
            )
        )
        reply(.success(ack))
    }

    private func queueBackgroundTransfer(_ message: [String: Any], kind: String) {
        guard let session, session.activationState == .activated else { return }
        // Playback uses applicationContext (latest-wins). Queuing transferUserInfo for every
        // track change makes Watch animate through the backlog when the phone reconnects.
        if kind == WatchConnectivityProtocol.Kind.playbackSnapshot.rawValue {
            return
        }
        if session.outstandingUserInfoTransfers.count >= 8 { return }
        let now = Date()
        if let last = lastBackgroundTransferAt[kind], now.timeIntervalSince(last) < 2.0 {
            return
        }
        lastBackgroundTransferAt[kind] = now
        session.transferUserInfo(message)
    }

    private func enqueuePending(_ envelope: WatchConnectivityProtocol.Envelope) {
        pendingTransfers.removeAll { $0.kind == envelope.kind }
        pendingTransfers.append(envelope)
        if pendingTransfers.count > 32 {
            pendingTransfers.removeFirst(pendingTransfers.count - 32)
        }
    }

    /// Keep only the latest envelope per kind (order preserved by first appearance).
    private func coalescePending(_ items: [WatchConnectivityProtocol.Envelope]) -> [WatchConnectivityProtocol.Envelope] {
        var latest: [WatchConnectivityProtocol.Kind: WatchConnectivityProtocol.Envelope] = [:]
        var order: [WatchConnectivityProtocol.Kind] = []
        for envelope in items {
            if latest[envelope.kind] == nil {
                order.append(envelope.kind)
            }
            latest[envelope.kind] = envelope
        }
        return order.compactMap { latest[$0] }
    }

    @discardableResult
    func updateApplicationContext(_ envelope: WatchConnectivityProtocol.Envelope) -> Bool {
        #if targetEnvironment(simulator)
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
        guard session.isWatchAppInstalled else {
            return false
        }
        #endif
        do {
            let data = try JSONEncoder().encode(envelope)
            try session.updateApplicationContext(["envelope": data])
            pendingApplicationContext = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            pendingApplicationContext = envelope
            return false
        }
        #endif
    }

    func transferUserInfo(_ envelope: WatchConnectivityProtocol.Envelope) {
        #if targetEnvironment(simulator)
        if sendViaSimulatorLink(envelope) { return }
        enqueuePending(envelope)
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

    private var canAttemptWatchDelivery: Bool {
        guard let session, session.activationState == .activated else { return false }
        #if os(iOS)
        #if targetEnvironment(simulator)
        return true
        #else
        return session.isWatchAppInstalled || session.isReachable
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
        guard simulatorLinkConnected else { return }
        if let pending = pendingApplicationContext {
            _ = updateApplicationContext(pending)
        }
        let queued = coalescePending(pendingTransfers)
        pendingTransfers.removeAll()
        for envelope in queued {
            _ = send(envelope)
        }
        #else
        guard let session, session.activationState == .activated else { return }
        #if os(iOS)
        if let pendingContext = receivedApplicationContextEnvelope() {
            dispatch(pendingContext)
        }
        guard canAttemptWatchDelivery else { return }
        #endif
        if let pending = pendingApplicationContext {
            _ = updateApplicationContext(pending)
        }
        let queued = coalescePending(pendingTransfers)
        pendingTransfers.removeAll()
        for envelope in queued {
            _ = send(envelope)
        }
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
        #if targetEnvironment(simulator)
        isReachable = simulatorLinkConnected || (session?.isReachable ?? false)
        #else
        isReachable = session?.isReachable ?? false
        #endif
        #if os(iOS)
        isPaired = session?.isPaired ?? false
        #if targetEnvironment(simulator)
        isWatchAppInstalled = simulatorLinkConnected || (session?.isWatchAppInstalled ?? false)
        #else
        isWatchAppInstalled = session?.isWatchAppInstalled ?? false
        #endif
        if !wasAvailable, isWatchDeliveryAvailable {
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

    private func dispatch(_ envelope: WatchConnectivityProtocol.Envelope) {
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
        guard let data = message["envelope"] as? Data else {
            throw BridgeError.invalidMessage
        }
        let envelope = try JSONDecoder().decode(WatchConnectivityProtocol.Envelope.self, from: data)
        if envelope.version > WatchConnectivityProtocol.protocolVersion {
            throw WatchConnectivityProtocol.ProtocolError.unsupportedVersion(envelope.version)
        }
        return envelope
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
                // Ignore corrupt simulator link payloads.
            }
        }
    }
}
#endif
