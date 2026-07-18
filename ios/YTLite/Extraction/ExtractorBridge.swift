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
        case bundleUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .missingBridgeAsset: return "Extractor not downloaded yet"
            case .notReady: return "Extractor not ready"
            case .timeout: return "Extractor timed out"
            case .extractFailed(let msg): return msg
            case .invalidResponse(let msg): return "Invalid extract response: \(msg)"
            case .bundleUnavailable(let msg): return msg
            }
        }
    }

    static let shared = ExtractorBridge()

    private var webView: WKWebView?
    private var readyContinuations: [CheckedContinuation<Void, Error>] = []
    private var isReady = false
    private var isPreparing = false
    private var pendingResults: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private let invokeTimeoutSeconds: TimeInterval = 45
    private let visitorTTL: TimeInterval = 30 * 60
    private let visitorRefreshDeadlineSeconds: TimeInterval = 5
    private var visitorData: String?
    private var visitorFetchedAt: Date?
    /// Single WKWebView cannot safely run concurrent extracts (HTTP callbacks interleave).
    private var bridgeLocked = false
    private var bridgeWaiters: [CheckedContinuation<Void, Never>] = []

    /// Probe-only: which bridge invoke is currently running (for correlating HTTP logs).
    private var probeActiveInvokeUID: String?
    private var probeActiveInvokeVideoId: String?
    private var probeActiveInvokeStartedAt: CFAbsoluteTime?

    func ensureReady() async throws {
        if isReady {
            PlayProbe.log("extract.bridge.ensureReady.hit", "alreadyReady=1")
            return
        }
        let t0 = PlayProbe.now()
        PlayProbe.log(
            "extract.bridge.ensureReady.wait",
            "preparing=\(isPreparing) waiters=\(readyContinuations.count)"
        )
        if !isPreparing {
            isPreparing = true
            Task { @MainActor in
                do {
                    try await self.prepareWebViewFromRemoteBundle()
                } catch {
                    self.markFailed(error.localizedDescription)
                }
            }
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            if isReady {
                cont.resume()
            } else {
                readyContinuations.append(cont)
            }
        }
        PlayProbe.log(
            "extract.bridge.ensureReady.done",
            "ms=\(PlayProbe.ms(since: t0)) ready=\(isReady)"
        )
    }

    func extractPlayback(videoId: String, preferLiveHLS: Bool = false) async throws -> VideoPlayback {
        let id = YouTubeURL.videoId(from: videoId) ?? videoId
        let trace = PlayProbe.newTraceId()
        let t0 = PlayProbe.now()
        let inflight = PlayProbe.markExtractEnter()
        PlayProbe.log(
            "extract.start",
            videoId: id,
            trace: trace,
            "raw=\(videoId) preferLiveHLS=\(preferLiveHLS) inflight=\(inflight) \(PlayProbe.concurrencySnapshot())"
        )
        defer {
            let left = PlayProbe.markExtractLeave()
            PlayProbe.log(
                "extract.end",
                videoId: id,
                trace: trace,
                "ms=\(PlayProbe.ms(since: t0)) inflightLeft=\(left)"
            )
        }
        if preferLiveHLS {
            PlayProbe.log("extract.live.preferFallback", videoId: id, trace: trace)
            do {
                let fallback = try await WatchPagePlayerFallback.extract(videoId: id)
                if fallback.hlsManifestURL != nil
                    || fallback.formats.contains(where: \.isMuxed)
                {
                    PlayProbe.log(
                        "extract.live.fallback.ok",
                        videoId: fallback.videoId,
                        trace: trace,
                        "formats=\(fallback.formats.count) hls=\(fallback.hlsManifestURL != nil) ms=\(PlayProbe.ms(since: t0))"
                    )
                    return fallback
                }
                PlayProbe.log(
                    "extract.live.fallback.weak",
                    videoId: id,
                    trace: trace,
                    "no hls/muxed → try bridge"
                )
            } catch {
                PlayProbe.log(
                    "extract.live.fallback.fail",
                    videoId: id,
                    trace: trace,
                    error.localizedDescription
                )
            }
        }
        if !preferLiveHLS {
            let fastT0 = PlayProbe.now()
            PlayProbe.log("extract.path.fast.try", videoId: id, trace: trace)
            if let fast = await WatchPagePlayerFallback.extractFast(videoId: id) {
                PlayProbe.log(
                    "extract.fast.ok",
                    videoId: fast.videoId,
                    trace: trace,
                    "formats=\(fast.formats.count) ms=\(PlayProbe.ms(since: fastT0)) totalMs=\(PlayProbe.ms(since: t0))"
                )
                return fast
            }
            PlayProbe.log(
                "extract.path.fast.miss",
                videoId: id,
                trace: trace,
                "ms=\(PlayProbe.ms(since: fastT0)) → bridge"
            )
        }
        do {
            let bridgeT0 = PlayProbe.now()
            PlayProbe.log("extract.path.bridge.try", videoId: id, trace: trace)
            let result = try await extractPlaybackViaBridge(videoId: videoId, trace: trace)
            PlayProbe.log(
                "extract.bridge.ok",
                videoId: result.videoId,
                trace: trace,
                "formats=\(result.formats.count) hls=\(result.hlsManifestURL != nil) ms=\(PlayProbe.ms(since: bridgeT0)) totalMs=\(PlayProbe.ms(since: t0))"
            )
            // Live / HLS-only: bridge may still return empty muxed — fall through to player.
            if preferLiveHLS,
               result.hlsManifestURL == nil,
               !result.formats.contains(where: \.isMuxed)
            {
                PlayProbe.log("extract.live.bridge.noHls", videoId: id, trace: trace, "try fallback")
                if let fallback = try? await WatchPagePlayerFallback.extract(videoId: id),
                   fallback.hlsManifestURL != nil || fallback.formats.contains(where: \.isMuxed)
                {
                    return fallback
                }
            }
            return result
        } catch is CancellationError {
            PlayProbe.log(
                "extract.cancelled",
                videoId: id,
                trace: trace,
                "ms=\(PlayProbe.ms(since: t0))"
            )
            throw CancellationError()
        } catch {
            let isTimeout: Bool = {
                if case ExtractorError.timeout = error { return true }
                let lower = error.localizedDescription.lowercased()
                return lower.contains("timed out") || lower.contains("timeout")
            }()
            PlayProbe.log(
                isTimeout ? "extract.timeout" : "extract.bridge.fail",
                videoId: id,
                trace: trace,
                "err=\(error.localizedDescription) ms=\(PlayProbe.ms(since: t0)) \(PlayProbe.concurrencySnapshot()) visitor=\(visitorData != nil) ready=\(isReady) locked=\(bridgeLocked) waiters=\(bridgeWaiters.count) pending=\(pendingResults.count)"
            )
            if Self.shouldTryWatchPageFallback(error) || preferLiveHLS {
                PlayProbe.log("extract.fallback.eligible", videoId: id, trace: trace)
                do {
                    let fallback = try await WatchPagePlayerFallback.extract(videoId: id)
                    PlayProbe.log(
                        "extract.fallback.return",
                        videoId: fallback.videoId,
                        trace: trace,
                        "formats=\(fallback.formats.count) hls=\(fallback.hlsManifestURL != nil) ms=\(PlayProbe.ms(since: t0))"
                    )
                    return fallback
                } catch {
                    PlayProbe.log(
                        "extract.fallback.throw",
                        videoId: id,
                        trace: trace,
                        error.localizedDescription
                    )
                }
            } else {
                PlayProbe.log(
                    "extract.fallback.skip",
                    videoId: id,
                    trace: trace,
                    "error not eligible timeout=\(isTimeout)"
                )
            }
            throw error
        }
    }

    private static func shouldTryWatchPageFallback(_ error: Error) -> Bool {
        if Task.isCancelled { return false }
        if case ExtractorError.timeout = error { return false }
        let cfg = ExtractorRemoteConfigStore.current
        guard cfg.enableWatchPageFallback || cfg.enableAndroidPlayerFallback else { return false }
        let msg = error.localizedDescription.lowercased()
        if msg.contains("timed out") || msg.contains("timeout") { return false }
        return msg.contains("unplayable")
            || msg.contains("not available")
            || msg.contains("video unavailable")
            || msg.contains("unable to extract playable stream")
            || msg.contains("no formats")
            || msg.contains("missing payload")
            || msg.contains("extractor not downloaded")
            || msg.contains("extractor download failed")
            || msg.contains("bundle")
            || msg.contains("login required")
            || msg.contains("login_required")
            || msg.contains("sign in to confirm")
            || msg.contains("confirm you're not a bot")
            || msg.contains("confirm you")
    }

    private func extractPlaybackViaBridge(
        videoId: String,
        trace: String? = nil
    ) async throws -> VideoPlayback {
        let phaseT0 = PlayProbe.now()
        PlayProbe.log("extract.bridge.ensureReady", videoId: videoId, trace: trace)
        try await ensureReady()
        PlayProbe.log(
            "extract.bridge.ensureReady.elapsed",
            videoId: videoId,
            trace: trace,
            "ms=\(PlayProbe.ms(since: phaseT0))"
        )
        // Inject cached visitor (or refresh briefly) before JS InnerTube — avoids per-song
        // homepage fetch races and empty-visitor hangs inside the bridge.
        let visitorT0 = PlayProbe.now()
        await ensureVisitorData(trace: trace, videoId: videoId)
        PlayProbe.log(
            "extract.bridge.visitor.elapsed",
            videoId: videoId,
            trace: trace,
            "ms=\(PlayProbe.ms(since: visitorT0)) hasVisitor=\(visitorData != nil)"
        )
        let lockT0 = PlayProbe.now()
        await acquireBridgeLock(trace: trace, videoId: videoId)
        defer { releaseBridgeLock(trace: trace, videoId: videoId) }
        PlayProbe.log(
            "extract.bridge.lock.acquired",
            videoId: videoId,
            trace: trace,
            "waitMs=\(PlayProbe.ms(since: lockT0)) waitersLeft=\(bridgeWaiters.count)"
        )
        PlayProbe.log("extract.bridge.ready", videoId: videoId, trace: trace)
        // Always extract via canonical watch URL (Shorts URLs → /watch?v=…).
        let id = YouTubeURL.videoId(from: videoId) ?? videoId
        let watchURL = YouTubeURL.canonicalWatchURL(YouTubeURL.watchURL(videoId: id))
        PlayProbe.log("extract.normalize", videoId: id, trace: trace, "url=\(watchURL)")
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
            let invokeT0 = PlayProbe.now()
            let bridgeInflight = PlayProbe.markBridgeInvokeEnter()
            probeActiveInvokeUID = uid
            probeActiveInvokeVideoId = id
            probeActiveInvokeStartedAt = invokeT0
            PlayProbe.log(
                "extract.bridge.invoke",
                videoId: id,
                trace: trace,
                "uid=\(uid) timeoutSec=\(Int(invokeTimeoutSeconds)) bridgeInflight=\(bridgeInflight) \(PlayProbe.concurrencySnapshot())"
            )
            defer {
                if probeActiveInvokeUID == uid {
                    probeActiveInvokeUID = nil
                    probeActiveInvokeVideoId = nil
                    probeActiveInvokeStartedAt = nil
                }
                PlayProbe.markBridgeInvokeLeave()
            }
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
            let dataKeys = (response["data"] as? [String: Any])?.keys.sorted().joined(separator: ",") ?? "-"
            PlayProbe.log(
                "extract.bridge.response",
                videoId: id,
                trace: trace,
                "uid=\(uid) dataKeys=\(dataKeys) invokeMs=\(PlayProbe.ms(since: invokeT0))"
            )
            return try ExtractResultMapper.map(envelope: response, fallbackVideoId: id)
        } catch {
            if let cont = pendingResults.removeValue(forKey: uid) {
                cont.resume(throwing: error)
            }
            let isTimeout: Bool = {
                if case ExtractorError.timeout = error { return true }
                let lower = error.localizedDescription.lowercased()
                return lower.contains("timed out") || lower.contains("timeout")
            }()
            let invokeMs = probeActiveInvokeStartedAt.map { PlayProbe.ms(since: $0) } ?? -1
            PlayProbe.log(
                isTimeout ? "extract.bridge.invoke.timeout" : "extract.bridge.invoke.fail",
                videoId: id,
                trace: trace,
                "uid=\(uid) err=\(error.localizedDescription) invokeMs=\(invokeMs) timeoutSec=\(Int(invokeTimeoutSeconds)) pending=\(pendingResults.count) \(PlayProbe.concurrencySnapshot())"
            )
            throw error
        }
    }

    private func acquireBridgeLock(trace: String? = nil, videoId: String? = nil) async {
        if !bridgeLocked {
            bridgeLocked = true
            PlayProbe.log(
                "extract.bridge.lock.free",
                videoId: videoId,
                trace: trace,
                "waiters=\(bridgeWaiters.count)"
            )
            return
        }
        let waitT0 = PlayProbe.now()
        PlayProbe.log(
            "extract.bridge.wait",
            videoId: videoId,
            trace: trace,
            "queueDepth=\(bridgeWaiters.count) activeUid=\(probeActiveInvokeUID ?? "-") activeId=\(probeActiveInvokeVideoId ?? "-")"
        )
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            bridgeWaiters.append(cont)
        }
        PlayProbe.log(
            "extract.bridge.wait.done",
            videoId: videoId,
            trace: trace,
            "waitMs=\(PlayProbe.ms(since: waitT0))"
        )
    }

    private func releaseBridgeLock(trace: String? = nil, videoId: String? = nil) {
        if let next = bridgeWaiters.first {
            bridgeWaiters.removeFirst()
            PlayProbe.log(
                "extract.bridge.lock.handoff",
                videoId: videoId,
                trace: trace,
                "waitersLeft=\(bridgeWaiters.count)"
            )
            next.resume()
        } else {
            bridgeLocked = false
            PlayProbe.log(
                "extract.bridge.lock.release",
                videoId: videoId,
                trace: trace
            )
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

    private func prepareWebViewFromRemoteBundle() async throws {
        PlayProbe.log("extractor.bundle.ensure")
        let dir: URL
        do {
            dir = try await ExtractorBundleStore.shared.ensureBundle()
        } catch {
            PlayProbe.log("extractor.bundle.fail", error.localizedDescription)
            throw ExtractorError.bundleUnavailable(error.localizedDescription)
        }
        let bridgeURL = dir.appendingPathComponent("bridge-ios.html")
        let jsURL = dir.appendingPathComponent("extractor.js")
        guard FileManager.default.fileExists(atPath: bridgeURL.path),
              FileManager.default.fileExists(atPath: jsURL.path)
        else {
            throw ExtractorError.missingBridgeAsset
        }
        PlayProbe.log("extractor.bundle.ready", "dir=\(dir.lastPathComponent)")

        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.userContentController.add(self, name: "AndroidBridge")
        let view = WKWebView(frame: .zero, configuration: config)
        view.isHidden = true
        webView = view
        view.loadFileURL(bridgeURL, allowingReadAccessTo: dir)
    }

    private func injectExtractorConfig() async {
        guard let webView else { return }
        let cfg = ExtractorRemoteConfigStore.current
        guard let data = try? JSONEncoder().encode(cfg),
              let json = String(data: data, encoding: .utf8)
        else { return }
        _ = try? await webView.evaluateJavaScript("window.__extractorConfig = \(json);")
    }

    private func markReady() {
        isReady = true
        isPreparing = false
        let waiters = readyContinuations
        readyContinuations.removeAll()
        waiters.forEach { $0.resume() }
        Task {
            await injectExtractorConfig()
            await refreshVisitorData()
        }
    }

    private func markFailed(_ message: String) {
        isPreparing = false
        let error = ExtractorError.extractFailed(message)
        let waiters = readyContinuations
        readyContinuations.removeAll()
        waiters.forEach { $0.resume(throwing: error) }
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
        else {
            PlayProbe.log(
                "extract.bridge.message.drop",
                "activeUid=\(probeActiveInvokeUID ?? "-") pending=\(pendingResults.count) bytes=\(messageJson.utf8.count)"
            )
            return
        }
        let invokeMs = probeActiveInvokeStartedAt.map { PlayProbe.ms(since: $0) } ?? -1
        PlayProbe.log(
            "extract.bridge.message",
            videoId: probeActiveInvokeVideoId,
            "uid=\(uid) invokeMs=\(invokeMs) pendingLeft=\(pendingResults.count)"
        )
        cont.resume(returning: obj)
    }

    private func handleHTTPRequest(_ body: [String: Any]) async {
        let callbackId = body["callbackId"] as? String ?? ""
        let url = body["url"] as? String ?? ""
        let method = body["httpMethod"] as? String ?? "GET"
        let headersJson = body["headers"] as? String ?? "{}"
        let requestBody = body["body"] as? String ?? ""
        let headers = Self.parseHeaders(headersJson)

        let shortURL = url.count > 120 ? String(url.prefix(120)) + "…" : url
        let kind = PlayProbe.httpKind(url: url)
        let httpInflight = PlayProbe.markHTTPEnter()
        let t0 = PlayProbe.now()
        PlayProbe.log(
            "extract.http.req",
            videoId: probeActiveInvokeVideoId,
            "\(method) kind=\(kind) \(shortURL) cb=\(callbackId.prefix(8)) activeUid=\(probeActiveInvokeUID ?? "-") httpInflight=\(httpInflight) \(PlayProbe.concurrencySnapshot())"
        )

        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: method,
            headers: headers,
            body: requestBody.isEmpty ? nil : requestBody
        )
        PlayProbe.markHTTPLeave()
        PlayProbe.log(
            "extract.http.res",
            videoId: probeActiveInvokeVideoId,
            "ok=\(result.success) code=\(result.errCode) bytes=\(result.body.utf8.count) ms=\(PlayProbe.ms(since: t0)) kind=\(kind) err=\(result.errMsg) activeUid=\(probeActiveInvokeUID ?? "-")"
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

    private func ensureVisitorData(trace: String? = nil, videoId: String? = nil) async {
        if let visitorData,
           let visitorFetchedAt,
           Date().timeIntervalSince(visitorFetchedAt) < visitorTTL
        {
            let age = Int(Date().timeIntervalSince(visitorFetchedAt))
            PlayProbe.log(
                "extract.visitor.cache",
                videoId: videoId,
                trace: trace,
                "ageSec=\(age) ttlSec=\(Int(visitorTTL))"
            )
            await setVisitorData(visitorData)
            return
        }
        PlayProbe.log(
            "extract.visitor.refresh",
            videoId: videoId,
            trace: trace,
            "deadlineSec=\(Int(visitorRefreshDeadlineSeconds))"
        )
        let t0 = PlayProbe.now()
        await withTaskGroup(of: Void.self) { group in
            let deadline = visitorRefreshDeadlineSeconds
            group.addTask { @MainActor in
                await self.refreshVisitorData()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(deadline * 1_000_000_000))
            }
            await group.next()
            group.cancelAll()
        }
        PlayProbe.log(
            "extract.visitor.done",
            videoId: videoId,
            trace: trace,
            "ms=\(PlayProbe.ms(since: t0)) hasVisitor=\(visitorData != nil)"
        )
    }

    private func refreshVisitorData() async {
        if let visitorData,
           let visitorFetchedAt,
           Date().timeIntervalSince(visitorFetchedAt) < visitorTTL
        {
            await setVisitorData(visitorData)
            return
        }
        let t0 = PlayProbe.now()
        let result = await YouTubeHTTPClient.shared.request(
            url: "\(YouTubeConstants.baseURL)/",
            method: "GET",
            headers: [:],
            body: nil,
            timeout: visitorRefreshDeadlineSeconds
        )
        guard result.success else {
            PlayProbe.log(
                "extract.visitor.http.fail",
                "ms=\(PlayProbe.ms(since: t0)) code=\(result.errCode) err=\(result.errMsg)"
            )
            return
        }
        let pattern = #"VISITOR_DATA":"([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: result.body, range: NSRange(result.body.startIndex..., in: result.body)),
           let range = Range(match.range(at: 1), in: result.body)
        {
            let value = String(result.body[range])
            visitorData = value
            visitorFetchedAt = Date()
            PlayProbe.log(
                "extract.visitor.http.ok",
                "ms=\(PlayProbe.ms(since: t0)) bytes=\(result.body.utf8.count)"
            )
            await setVisitorData(value)
        } else {
            PlayProbe.log(
                "extract.visitor.parse.miss",
                "ms=\(PlayProbe.ms(since: t0)) bytes=\(result.body.utf8.count)"
            )
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
