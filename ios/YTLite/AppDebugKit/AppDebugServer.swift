import Foundation
import Network
import OSLog
import UIKit

#if DEBUG
private let appDebugLog = Logger(subsystem: "com.ytlite.player", category: "AppDebugKit")

/// Minimal localhost HTTP server for Mac MCP tooling. Listens on port `9876`.
@MainActor
final class AppDebugServer {
    static let shared = AppDebugServer()

    private let port: NWEndpoint.Port = 9876
    private var listener: NWListener?
    private var isStarting = false

    private init() {}

    func start() {
        appDebugLogNotice("start() called")
        if listener != nil {
            appDebugLogNotice("start() skipped — listener already exists")
            return
        }
        if isStarting {
            appDebugLogNotice("start() skipped — already starting")
            return
        }
        isStarting = true

        do {
            // Bind by port only. `requiredLocalEndpoint = 127.0.0.1` often fails to become
            // `.ready` on iOS Simulator; port bind still accepts localhost / USB tunnel.
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: port)
            appDebugLogNotice("NWListener created for port \(self.port.rawValue)")

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    self.appDebugLogNotice("listener state → \(Self.describe(state))")
                    switch state {
                    case .ready:
                        self.isStarting = false
                        let portValue = listener.port?.rawValue ?? self.port.rawValue
                        self.appDebugLogNotice("✅ READY — curl http://127.0.0.1:\(portValue)/state")
                    case .waiting(let error):
                        self.appDebugLogError("⏳ WAITING — \(error)")
                    case .failed(let error):
                        self.isStarting = false
                        self.listener = nil
                        self.appDebugLogError("❌ FAILED — \(error)")
                    case .cancelled:
                        self.isStarting = false
                        self.listener = nil
                        self.appDebugLogNotice("listener cancelled")
                    case .setup:
                        self.appDebugLogNotice("listener setup")
                    @unknown default:
                        self.appDebugLogNotice("listener unknown state")
                    }
                }
            }

            listener.newConnectionHandler = { connection in
                let endpoint = String(describing: connection.endpoint)
                appDebugLog.notice("new connection from \(endpoint, privacy: .public)")
                NSLog("[AppDebugKit] new connection from %@", endpoint)
                connection.start(queue: .global(qos: .userInitiated))
                AppDebugHTTPConnectionHandler.handle(connection)
            }

            listener.start(queue: .global(qos: .utility))
            self.listener = listener
            AppDebugActionRegistry.shared.register(id: "system.back") {
                _ = AppDebugSessionState.shared.back()
            }
            appDebugLogNotice("listener.start() invoked, waiting for .ready…")
        } catch {
            isStarting = false
            appDebugLogError("failed to create NWListener: \(error)")
        }
    }

    func stop() {
        appDebugLogNotice("stop() called")
        listener?.cancel()
        listener = nil
        isStarting = false
    }

    private func appDebugLogNotice(_ message: String) {
        appDebugLog.notice("\(message, privacy: .public)")
        NSLog("[AppDebugKit] %@", message)
        print("[AppDebugKit] \(message)")
    }

    private func appDebugLogError(_ message: String) {
        appDebugLog.error("\(message, privacy: .public)")
        NSLog("[AppDebugKit] ERROR %@", message)
        print("[AppDebugKit] ERROR \(message)")
    }

    private static func describe(_ state: NWListener.State) -> String {
        switch state {
        case .setup: return "setup"
        case .waiting(let error): return "waiting(\(error))"
        case .ready: return "ready"
        case .failed(let error): return "failed(\(error))"
        case .cancelled: return "cancelled"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Connection handling (off MainActor)

private enum AppDebugHTTPConnectionHandler {
    static func handle(_ connection: NWConnection) {
        receiveAll(on: connection, accumulated: Data()) { data in
            guard let data, !data.isEmpty else {
                NSLog("[AppDebugKit] connection closed with empty request")
                connection.cancel()
                return
            }
            Task {
                let preview = String(data: data.prefix(120), encoding: .utf8) ?? "<binary \(data.count) bytes>"
                NSLog("[AppDebugKit] request preview: %@", preview.replacingOccurrences(of: "\r\n", with: " | "))
                let response = await AppDebugHTTPRouter.route(requestData: data)
                send(response, on: connection)
            }
        }
    }

    private static func receiveAll(
        on connection: NWConnection,
        accumulated: Data,
        completion: @escaping (Data?) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { content, _, isComplete, error in
            if let error {
                NSLog("[AppDebugKit] receive error: %@", String(describing: error))
                completion(nil)
                return
            }

            var buffer = accumulated
            if let content {
                buffer.append(content)
            }

            if isComplete || Self.hasCompleteHTTPMessage(buffer) {
                completion(buffer)
                return
            }

            receiveAll(on: connection, accumulated: buffer, completion: completion)
        }
    }

    private static func hasCompleteHTTPMessage(_ data: Data) -> Bool {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let headerData = data.subdata(in: data.startIndex..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return true }

        let contentLength = headerText
            .split(separator: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("content-length:") })
            .flatMap { line -> Int? in
                Int(line.split(separator: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces))
            } ?? 0

        let bodyStart = headerEnd.upperBound
        let bodyCount = data.count - bodyStart
        return bodyCount >= contentLength
    }

    private static func send(_ response: Data, on connection: NWConnection) {
        connection.send(content: response, completion: .contentProcessed { error in
            if let error {
                NSLog("[AppDebugKit] send error: %@", String(describing: error))
            } else {
                NSLog("[AppDebugKit] response sent (%d bytes)", response.count)
            }
            connection.cancel()
        })
    }
}

// MARK: - Routing

private enum AppDebugHTTPRouter {
    static func route(requestData: Data) async -> Data {
        guard let request = AppDebugHTTPRequest.parse(requestData) else {
            NSLog("[AppDebugKit] route: bad request")
            return AppDebugHTTPResponse.text(status: 400, body: "Bad Request")
        }

        NSLog("[AppDebugKit] route: %@ %@", request.method, request.path)

        switch (request.method, request.path) {
        case ("GET", "/actions"):
            let ids = await MainActor.run {
                AppDebugActionRegistry.shared.availableActions()
            }
            NSLog("[AppDebugKit] /actions → %d items", ids.count)
            return AppDebugHTTPResponse.json(status: 200, object: ["actions": ids])

        case ("POST", "/activate"):
            guard let id = request.jsonStringValue(forKey: "id"), !id.isEmpty else {
                NSLog("[AppDebugKit] /activate missing id")
                return AppDebugHTTPResponse.json(status: 400, object: ["error": "missing id"])
            }
            let triggered = await MainActor.run {
                AppDebugActionRegistry.shared.trigger(id: id)
            }
            NSLog("[AppDebugKit] /activate id=%@ triggered=%@", id, triggered ? "true" : "false")
            if triggered {
                return AppDebugHTTPResponse.json(status: 200, object: ["ok": true, "id": id])
            }
            return AppDebugHTTPResponse.json(status: 404, object: ["error": "action not found", "id": id])

        case ("GET", "/screenshot"):
            let png = await MainActor.run { () -> Data? in
                AppDebugScreenshot.capturePNG()
            }
            guard let png else {
                NSLog("[AppDebugKit] /screenshot unavailable")
                return AppDebugHTTPResponse.text(status: 500, body: "Screenshot unavailable")
            }
            NSLog("[AppDebugKit] /screenshot → %d bytes", png.count)
            return AppDebugHTTPResponse.binary(status: 200, contentType: "image/png", body: png)

        case ("GET", "/state"):
            let snapshot = await MainActor.run {
                AppDebugSessionState.shared.snapshot()
            }
            return AppDebugHTTPResponse.json(status: 200, object: snapshot)

        default:
            NSLog("[AppDebugKit] route not found: %@ %@", request.method, request.path)
            return AppDebugHTTPResponse.text(status: 404, body: "Not Found")
        }
    }
}

// MARK: - Minimal HTTP parse / respond

private struct AppDebugHTTPRequest {
    let method: String
    let path: String
    let body: Data

    static func parse(_ data: Data) -> AppDebugHTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: data.startIndex..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0]).uppercased()
        let rawPath = String(parts[1])
        let path = rawPath.split(separator: "?").first.map(String.init) ?? rawPath
        let body = data.subdata(in: headerEnd.upperBound..<data.endIndex)
        return AppDebugHTTPRequest(method: method, path: path, body: body)
    }

    func jsonStringValue(forKey key: String) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            guard let text = String(data: body, encoding: .utf8) else { return nil }
            let pattern = "\"\(key)\"\\s*:\\s*\"([^\"]+)\""
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: text)
            else {
                return nil
            }
            return String(text[valueRange])
        }
        return object[key] as? String
    }
}

private enum AppDebugHTTPResponse {
    static func json(status: Int, object: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data("{}".utf8)
        return message(status: status, contentType: "application/json; charset=utf-8", body: body)
    }

    static func text(status: Int, body: String) -> Data {
        message(status: status, contentType: "text/plain; charset=utf-8", body: Data(body.utf8))
    }

    static func binary(status: Int, contentType: String, body: Data) -> Data {
        message(status: status, contentType: contentType, body: body)
    }

    private static func message(status: Int, contentType: String, body: Data) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 500: reason = "Internal Server Error"
        default: reason = "OK"
        }

        let header = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        var data = Data(header.utf8)
        data.append(body)
        return data
    }
}

// MARK: - Screenshot

private enum AppDebugScreenshot {
    @MainActor
    static func capturePNG() -> Data? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first

        guard let window else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { context in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            _ = context
        }
        return image.pngData()
    }
}
#endif
