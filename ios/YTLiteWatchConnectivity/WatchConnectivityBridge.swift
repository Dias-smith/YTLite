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
    @Published private(set) var lastErrorMessage: String?

    private var session: WCSession?
    private var handlers: [@MainActor (WatchConnectivityProtocol.Envelope) -> Void] = []
    private var didActivate = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            lastErrorMessage = "WatchConnectivity unsupported"
            return
        }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        if !didActivate {
            didActivate = true
            session.activate()
        }
        refreshReachability()
    }

    func onEnvelope(_ handler: @escaping @MainActor (WatchConnectivityProtocol.Envelope) -> Void) {
        handlers.append(handler)
    }

    @discardableResult
    func send(_ envelope: WatchConnectivityProtocol.Envelope, reply: ((Result<WatchConnectivityProtocol.Envelope, Error>) -> Void)? = nil) -> Bool {
        guard let session, session.activationState == .activated else {
            reply?(.failure(BridgeError.notActivated))
            return false
        }

        do {
            let data = try JSONEncoder().encode(envelope)
            let message: [String: Any] = ["envelope": data]

            if session.isReachable {
                session.sendMessage(message, replyHandler: { replyMessage in
                    Task { @MainActor in
                        do {
                            let replyEnvelope = try Self.decodeEnvelope(from: replyMessage)
                            reply?(.success(replyEnvelope))
                        } catch {
                            reply?(.failure(error))
                        }
                    }
                }, errorHandler: { error in
                    Task { @MainActor in
                        self.lastErrorMessage = error.localizedDescription
                        // Interactive path failed — still queue for later delivery.
                        session.transferUserInfo(message)
                        reply?(.failure(error))
                    }
                })
                return true
            }

            session.transferUserInfo(message)
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

    func updateApplicationContext(_ envelope: WatchConnectivityProtocol.Envelope) {
        guard let session, session.activationState == .activated else { return }
        do {
            let data = try JSONEncoder().encode(envelope)
            try session.updateApplicationContext(["envelope": data])
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func transferUserInfo(_ envelope: WatchConnectivityProtocol.Envelope) {
        guard let session, session.activationState == .activated else { return }
        do {
            let data = try JSONEncoder().encode(envelope)
            session.transferUserInfo(["envelope": data])
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func receivedApplicationContextEnvelope() -> WatchConnectivityProtocol.Envelope? {
        guard let session else { return nil }
        return try? Self.decodeEnvelope(from: session.receivedApplicationContext)
    }

    private func refreshReachability() {
        isReachable = session?.isReachable ?? false
        #if os(watchOS)
        isCompanionAppInstalled = session?.isCompanionAppInstalled ?? true
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

    private static func decodeEnvelope(from message: [String: Any]) throws -> WatchConnectivityProtocol.Envelope {
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
    #endif

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshReachability()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        #if os(iOS)
        Task { @MainActor in
            self.withBackgroundTask {
                do {
                    let envelope = try Self.decodeEnvelope(from: message)
                    self.dispatch(envelope)
                } catch {
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
        #else
        Task { @MainActor in
            do {
                let envelope = try Self.decodeEnvelope(from: message)
                self.dispatch(envelope)
            } catch {
                self.lastErrorMessage = error.localizedDescription
            }
        }
        #endif
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        #if os(iOS)
        Task { @MainActor in
            self.withBackgroundTask {
                self.handleMessage(message, replyHandler: replyHandler)
            }
        }
        #else
        Task { @MainActor in
            self.handleMessage(message, replyHandler: replyHandler)
        }
        #endif
    }

    @MainActor
    private func handleMessage(_ message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        do {
            let envelope = try Self.decodeEnvelope(from: message)
            dispatch(envelope)
            let ack = WatchConnectivityProtocol.Envelope(
                kind: .ack,
                payload: try JSONEncoder().encode(
                    WatchConnectivityProtocol.AckBody(requestId: envelope.id, ok: true, message: nil)
                )
            )
            let data = try JSONEncoder().encode(ack)
            replyHandler(["envelope": data])
        } catch {
            lastErrorMessage = error.localizedDescription
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
