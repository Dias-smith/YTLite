import Foundation
import WebKit

/// WKWebView bridge mirroring Android `JsExtractorEngine` + `VsPlayerBridge`.
@MainActor
final class ExtractorBridge: NSObject, WKScriptMessageHandler {
    enum ExtractorError: LocalizedError {
        case missingBridgeAsset
        case notReady
        case timeout
        case extractFailed(String)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .missingBridgeAsset: return "Missing extractor bridge assets"
            case .notReady: return "Extractor not ready"
            case .timeout: return "Extractor timed out"
            case .extractFailed(let msg): return msg
            case .invalidResponse(let msg): return "Invalid extract response: \(msg)"
            }
        }
    }

    static let shared = ExtractorBridge()

    private var webView: WKWebView?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var isReady = false
    private var isPreparing = false
    private var pendingResults: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private let invokeTimeoutSeconds: TimeInterval = 45

    func ensureReady() async throws {
        if isReady { return }
        if !isPreparing {
            isPreparing = true
            try prepareWebView()
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            if isReady {
                cont.resume()
            } else {
                readyContinuation = cont
            }
        }
    }

    func extractPlayback(videoId: String) async throws -> VideoPlayback {
        do {
            return try await extractPlaybackViaBridge(videoId: videoId)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Self.shouldTryWatchPageFallback(error) {
                if let fallback = try? await WatchPagePlayerFallback.extract(videoId: videoId) {
                    return fallback
                }
            }
            throw error
        }
    }

    private static func shouldTryWatchPageFallback(_ error: Error) -> Bool {
        if Task.isCancelled { return false }
        let msg = error.localizedDescription.lowercased()
        return msg.contains("unplayable")
            || msg.contains("not available")
            || msg.contains("video unavailable")
            || msg.contains("unable to extract playable stream")
            || msg.contains("no formats")
            || msg.contains("missing payload")
    }

    private func extractPlaybackViaBridge(videoId: String) async throws -> VideoPlayback {
        try await ensureReady()
        // Match Android VsPlayerBridge.getVisitorData(): ensure fresh visitor before player calls.
        await refreshVisitorData()
        // Always extract via canonical watch URL (Shorts URLs → /watch?v=…).
        let id = YouTubeURL.videoId(from: videoId) ?? videoId
        let watchURL = YouTubeURL.canonicalWatchURL(YouTubeURL.watchURL(videoId: id))
        let uid = UUID().uuidString
        let envelope: [String: Any] = [
            "uid": uid,
            "event": 0,
            "source": 0,
            "data": ["url": watchURL],
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: envelope)
        guard let payloadString = String(data: payloadData, encoding: .utf8) else {
            throw ExtractorError.invalidResponse("encode failed")
        }

        do {
            let response: [String: Any] = try await withThrowingTaskGroup(of: [String: Any].self) { group in
                group.addTask { @MainActor in
                    try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String: Any], Error>) in
                            self.pendingResults[uid] = cont
                            let quoted = Self.jsonQuoted(payloadString)
                            let script =
                                "(function(){try{return window.extractor.postMessageToJSBridge(\(quoted));}" +
                                "catch(e){AndroidBridge.onExtractorError(String(e));}})()"
                            self.webView?.evaluateJavaScript(script, completionHandler: nil)
                        }
                    } onCancel: {
                        Task { @MainActor in
                            if let cont = self.pendingResults.removeValue(forKey: uid) {
                                cont.resume(throwing: CancellationError())
                            }
                        }
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(self.invokeTimeoutSeconds * 1_000_000_000))
                    throw ExtractorError.timeout
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
            return try ExtractResultMapper.map(envelope: response, fallbackVideoId: id)
        } catch {
            if let cont = pendingResults.removeValue(forKey: uid) {
                cont.resume(throwing: error)
            }
            throw error
        }
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let method = body["method"] as? String
        else { return }

        Task { @MainActor in
            switch method {
            case "onExtractorReady":
                self.markReady()
            case "onExtractorError":
                let msg = body["message"] as? String ?? "extractor error"
                self.markFailed(msg)
            case "requestWithCallback":
                await self.handleHTTPRequest(body)
            case "sendMessageToNative":
                self.handleSendMessage(body["message"] as? String ?? "")
            case "queryUserInfo":
                await self.completeSimpleCallback(
                    callbackId: body["callbackId"] as? String ?? "",
                    value: "{}"
                )
            case "queryFIRRemoteConfigThen":
                await self.completeSimpleCallback(
                    callbackId: body["callbackId"] as? String ?? "",
                    value: ""
                )
            default:
                break
            }
        }
    }

    // MARK: - Private

    private func prepareWebView() throws {
        guard let bridgeURL = Self.resolveAssetURL(named: "bridge-ios", ext: "html")
            ?? Self.resolveAssetURL(named: "bridge", ext: "html")
        else {
            throw ExtractorError.missingBridgeAsset
        }
        // Ensure extractor.js sits next to bridge when loading from disk.
        // Bundled folder resources preserve relative links from bridge-ios.html.
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.userContentController.add(self, name: "AndroidBridge")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isHidden = true
        webView = view

        // Prefer loading HTML from the directory that also contains extractor.js.
        let dir = bridgeURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("extractor.js").path) {
            view.loadFileURL(bridgeURL, allowingReadAccessTo: dir)
        } else if let jsURL = Self.resolveAssetURL(named: "extractor", ext: "js"),
                  let html = try? String(contentsOf: bridgeURL, encoding: .utf8)
        {
            let patched = html.replacingOccurrences(
                of: "src=\"extractor.js\"",
                with: "src=\"\(jsURL.absoluteString)\""
            )
            view.loadHTMLString(patched, baseURL: jsURL.deletingLastPathComponent())
        } else {
            view.loadFileURL(bridgeURL, allowingReadAccessTo: dir)
        }

        Task {
            await refreshVisitorData()
        }
    }

    private func markReady() {
        isReady = true
        isPreparing = false
        readyContinuation?.resume()
        readyContinuation = nil
        Task { await refreshVisitorData() }
    }

    private func markFailed(_ message: String) {
        isPreparing = false
        let error = ExtractorError.extractFailed(message)
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
        for (_, cont) in pendingResults {
            cont.resume(throwing: error)
        }
        pendingResults.removeAll()
    }

    private func handleSendMessage(_ messageJson: String) {
        guard let data = messageJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uid = obj["uid"] as? String,
              let cont = pendingResults.removeValue(forKey: uid)
        else { return }
        cont.resume(returning: obj)
    }

    private func handleHTTPRequest(_ body: [String: Any]) async {
        let callbackId = body["callbackId"] as? String ?? ""
        let url = body["url"] as? String ?? ""
        let method = body["httpMethod"] as? String ?? "GET"
        let headersJson = body["headers"] as? String ?? "{}"
        let requestBody = body["body"] as? String ?? ""
        let headers = Self.parseHeaders(headersJson)

        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: method,
            headers: headers,
            body: requestBody.isEmpty ? nil : requestBody
        )
        await completeHTTPCallback(callbackId: callbackId, result: result)
    }

    private func completeSimpleCallback(callbackId: String, value: String) async {
        await completeHTTPCallback(
            callbackId: callbackId,
            result: HttpStringResult(success: true, body: value, errCode: 0, errMsg: "")
        )
    }

    private func completeHTTPCallback(callbackId: String, result: HttpStringResult) async {
        guard let webView else { return }
        // WKWebView cannot sync-return like Android JavascriptInterface; bridge-ios.html
        // reads window.__requestResults[id]. Large player JSON must be chunked — a single
        // callAsyncJavaScript argument often fails and left music=null with success:true.
        let ok = await depositHTTPBody(callbackId: callbackId, body: result.body)
        let success = result.success && ok
        let errCode = ok ? result.errCode : -1
        let errMsg = ok ? result.errMsg : "Failed to deposit HTTP body into JS bridge"
        let script =
            "window.AndroidBridge_invokeCallback(" +
            "\(Self.jsonQuoted(callbackId)),\(success ? "true" : "false"),null," +
            "\(errCode),\(Self.jsonQuoted(errMsg)));"
        do {
            _ = try await webView.evaluateJavaScript(script)
        } catch {
            webView.evaluateJavaScript(
                "window.AndroidBridge_invokeCallback(\(Self.jsonQuoted(callbackId)),false,null,-1,\(Self.jsonQuoted(error.localizedDescription)));",
                completionHandler: nil
            )
        }
    }

    /// Splits large responses into JSON-safe chunks and assigns `window.__requestResults[id]`.
    private func depositHTTPBody(callbackId: String, body: String) async -> Bool {
        guard let webView else { return false }
        let idLit = Self.jsonQuoted(callbackId)
        do {
            _ = try await webView.evaluateJavaScript("window.__requestResults[\(idLit)]='';")
            // Keep chunks small enough for evaluateJavaScript / JSON escaping.
            let chunkSize = 80_000
            var start = body.startIndex
            while start < body.endIndex {
                let end = body.index(start, offsetBy: chunkSize, limitedBy: body.endIndex) ?? body.endIndex
                let chunk = String(body[start..<end])
                let script = "window.__requestResults[\(idLit)]+=\(Self.jsonQuoted(chunk));"
                _ = try await webView.evaluateJavaScript(script)
                start = end
            }
            return true
        } catch {
            return false
        }
    }

    private func refreshVisitorData() async {
        let result = await YouTubeHTTPClient.shared.request(
            url: "\(YouTubeConstants.baseURL)/",
            method: "GET",
            headers: [:],
            body: nil
        )
        guard result.success else { return }
        let pattern = #"VISITOR_DATA":"([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: result.body, range: NSRange(result.body.startIndex..., in: result.body)),
           let range = Range(match.range(at: 1), in: result.body)
        {
            await setVisitorData(String(result.body[range]))
        }
    }

    private func setVisitorData(_ value: String) async {
        guard let webView else { return }
        _ = try? await webView.callAsyncJavaScript(
            "window.__visitorData = value; return true;",
            arguments: ["value": value],
            contentWorld: .page
        )
    }

    private static func resolveAssetURL(named name: String, ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        // Folder resource group may nest under ExtractorAssets /
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "ExtractorAssets") {
            return url
        }
        if let root = Bundle.main.resourceURL {
            let candidates = [
                root.appendingPathComponent("\(name).\(ext)"),
                root.appendingPathComponent("extractor/\(name).\(ext)"),
                root.appendingPathComponent("ExtractorAssets/\(name).\(ext)"),
                root.appendingPathComponent("shared/extractor/\(name).\(ext)"),
            ]
            return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
        }
        return nil
    }

    private static func parseHeaders(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in obj {
            out[k] = "\(v)"
        }
        return out
    }

    private static func jsonQuoted(_ string: String) -> String {
        // JSONSerialization rejects String as a top-level object; encode via array and unwrap.
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let wrapped = String(data: data, encoding: .utf8),
              wrapped.count >= 2
        else {
            return "\"\""
        }
        return String(wrapped.dropFirst().dropLast())
    }
}
