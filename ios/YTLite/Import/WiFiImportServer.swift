import Darwin
import Foundation
import Network

/// Lightweight LAN HTTP server for browser → phone music upload.
@MainActor
final class WiFiImportServer: ObservableObject {
    static let shared = WiFiImportServer()

    @Published private(set) var isRunning = false
    @Published private(set) var listenURL: URL?
    @Published private(set) var lastError: String?
    /// Successfully ingested tracks this session (upload accepted + import OK).
    @Published private(set) var importedCount: Int = 0
    @Published private(set) var failedCount: Int = 0

    /// Return `true` when the file was ingested into the library.
    var onFileReceived: ((Data, String) async -> Bool)?

    private var listener: NWListener?
    private let port: UInt16 = 8787
    private let bonjourType = "_ytlite-import._tcp"

    private init() {}

    func start() {
        stop()
        lastError = nil
        importedCount = 0
        failedCount = 0
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.includePeerToPeer = true

            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            // Advertising Bonjour is required for the iOS Local Network permission prompt.
            listener.service = NWListener.Service(name: "Mixtube Import", type: bonjourType)
            listener.newConnectionHandler = { [weak self] connection in
                // Connection I/O stays off the main actor; only UI state hops back.
                Self.accept(connection) { request in
                    await self?.handleRequest(request, connection: connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.refreshListenURL()
                        if self.listenURL == nil {
                            self.lastError = L("import.wifi.no_wifi_ip")
                        }
                    case .failed(let error):
                        self.lastError = error.localizedDescription
                        self.isRunning = false
                        self.listenURL = nil
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener.start(queue: DispatchQueue(label: "ytlite.wifi.import", qos: .userInitiated))
            self.listener = listener
            // IP can appear slightly after Wi‑Fi is up.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                if self.isRunning { self.refreshListenURL() }
            }
        } catch {
            lastError = error.localizedDescription
            isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        listenURL = nil
    }

    private func refreshListenURL() {
        if let ip = Self.primaryLANAddress() {
            listenURL = URL(string: "http://\(ip):\(port)/")
            lastError = nil
        } else {
            listenURL = nil
        }
    }

    private nonisolated static func accept(
        _ connection: NWConnection,
        onRequest: @escaping @Sendable (HTTPRequest) async -> Void
    ) {
        connection.start(queue: DispatchQueue(label: "ytlite.wifi.conn", qos: .userInitiated))
        readHTTP(connection: connection, buffer: Data(), onRequest: onRequest)
    }

    /// Read until a full HTTP request is buffered, then respond.
    /// Important: do **not** wait for TCP EOF — browsers keep connections open waiting for the response.
    private nonisolated static func readHTTP(
        connection: NWConnection,
        buffer: Data,
        onRequest: @escaping @Sendable (HTTPRequest) async -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, isComplete, error in
            if error != nil {
                connection.cancel()
                return
            }
            var next = buffer
            if let data, !data.isEmpty {
                next.append(data)
            }

            if let request = tryParseHTTPRequest(next) {
                Task {
                    await onRequest(request)
                }
                return
            }

            if isComplete {
                connection.cancel()
                return
            }
            if next.count > 200 * 1024 * 1024 {
                connection.cancel()
                return
            }
            readHTTP(connection: connection, buffer: next, onRequest: onRequest)
        }
    }

    struct HTTPRequest: Sendable {
        let method: String
        let path: String
        let headers: String
        let body: Data
    }

    nonisolated static func tryParseHTTPRequest(_ raw: Data) -> HTTPRequest? {
        guard let headerEnd = raw.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = raw.subdata(in: raw.startIndex..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        let contentLength: Int = {
            for line in lines.dropFirst() {
                let lower = line.lowercased()
                if lower.hasPrefix("content-length:") {
                    let value = lower.dropFirst("content-length:".count)
                        .trimmingCharacters(in: .whitespaces)
                    return Int(value) ?? 0
                }
            }
            return 0
        }()

        let bodyStart = headerEnd.upperBound
        let available = raw.distance(from: bodyStart, to: raw.endIndex)
        guard available >= contentLength else { return nil }
        let bodyEnd = raw.index(bodyStart, offsetBy: contentLength)
        let body = raw.subdata(in: bodyStart..<bodyEnd)
        return HTTPRequest(method: method, path: path, headers: headerText, body: body)
    }

    private func handleRequest(_ request: HTTPRequest, connection: NWConnection) async {
        let pathOnly = request.path.split(separator: "?").first.map(String.init) ?? request.path
        if request.method == "GET", pathOnly == "/" || pathOnly.hasPrefix("/index") {
            respond(connection, status: 200, reason: "OK", contentType: "text/html; charset=utf-8", body: Data(Self.uploadHTML.utf8))
            return
        }

        if request.method == "POST", pathOnly.hasPrefix("/upload") {
            if let file = parseMultipart(body: request.body, headers: request.headers) {
                let ok = await onFileReceived?(file.data, file.filename) ?? false
                if ok {
                    importedCount += 1
                    respond(connection, status: 200, reason: "OK", contentType: "text/plain; charset=utf-8", body: Data("OK".utf8))
                } else {
                    failedCount += 1
                    respond(connection, status: 500, reason: "Import Failed", contentType: "text/plain; charset=utf-8", body: Data("Import failed".utf8))
                }
            } else {
                respond(connection, status: 400, reason: "Bad Request", body: Data("No file".utf8))
            }
            return
        }

        respond(connection, status: 404, reason: "Not Found", body: Data("Not Found".utf8))
    }

    private nonisolated func respond(
        _ connection: NWConnection,
        status: Int,
        reason: String,
        contentType: String = "text/plain; charset=utf-8",
        body: Data
    ) {
        let header = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.count)\r
        Connection: close\r
        Access-Control-Allow-Origin: *\r
        \r

        """
        var payload = Data(header.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private struct UploadedFile {
        let filename: String
        let data: Data
    }

    private func parseMultipart(body: Data, headers: String) -> UploadedFile? {
        let lower = headers.lowercased()
        guard let boundaryRange = lower.range(of: "boundary=") else { return nil }
        var boundary = String(headers[boundaryRange.upperBound...])
            .split(whereSeparator: { $0.isNewline || $0 == ";" })
            .first
            .map(String.init) ?? ""
        boundary = boundary.trimmingCharacters(in: CharacterSet(charactersIn: "\" \t"))
        guard !boundary.isEmpty else { return nil }

        let marker = Data("--\(boundary)".utf8)
        guard let first = body.range(of: marker) else { return nil }
        var cursor = first.upperBound
        if body[cursor..<body.endIndex].starts(with: Data("\r\n".utf8)) {
            cursor = body.index(cursor, offsetBy: 2)
        }
        guard let nextBoundary = body.range(of: marker, in: cursor..<body.endIndex) else { return nil }
        let part = body.subdata(in: cursor..<nextBoundary.lowerBound)
        guard let partHeaderEnd = part.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let partHeaders = String(data: part.subdata(in: part.startIndex..<partHeaderEnd.lowerBound), encoding: .utf8) ?? ""
        var fileData = part.subdata(in: partHeaderEnd.upperBound..<part.endIndex)
        if fileData.count >= 2, fileData.suffix(2) == Data("\r\n".utf8) {
            fileData.removeLast(2)
        }
        var filename = "upload.bin"
        if let nameRange = partHeaders.range(of: "filename=\"", options: .caseInsensitive) {
            let rest = partHeaders[nameRange.upperBound...]
            if let end = rest.firstIndex(of: "\"") {
                filename = String(rest[..<end])
            }
        }
        // Prefer first file part if multiple; skip non-file fields.
        if !partHeaders.lowercased().contains("filename=") {
            // Try next part recursively by slicing remaining body.
            let restStart = nextBoundary.lowerBound
            if restStart < body.endIndex {
                return parseMultipart(body: body.subdata(in: restStart..<body.endIndex), headers: headers)
            }
            return nil
        }
        return UploadedFile(filename: filename, data: fileData)
    }

    private static let uploadHTML = #"""
    <!doctype html>
    <html lang="en"><head>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width,initial-scale=1"/>
    <title>Mixtube Wi‑Fi Import</title>
    <style>
      :root { color-scheme: dark; }
      * { box-sizing: border-box; }
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        background: #111; color: #eee;
        padding: 24px; max-width: 640px; margin: 0 auto;
      }
      h1 { margin: 0 0 8px; font-size: 28px; }
      .sub { color: #aaa; margin: 0 0 20px; line-height: 1.4; }
      .box {
        border: 2px dashed #555; border-radius: 14px;
        padding: 28px 20px; text-align: center; background: #1a1a1a;
      }
      .box.drag { border-color: #f97316; background: #22180f; }
      #file { display: none; }
      .pick {
        display: inline-block; margin-top: 8px; padding: 12px 18px;
        border-radius: 10px; background: #f97316; color: #111;
        font-weight: 700; cursor: pointer; border: 0;
      }
      .summary { margin: 18px 0 8px; color: #bbb; font-size: 14px; }
      #list { list-style: none; padding: 0; margin: 0; display: grid; gap: 10px; }
      .row {
        background: #1c1c1c; border: 1px solid #2a2a2a; border-radius: 12px;
        padding: 12px 14px;
      }
      .top { display: flex; justify-content: space-between; gap: 12px; align-items: baseline; }
      .name {
        font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
      }
      .meta { color: #888; font-size: 12px; flex-shrink: 0; }
      .bar {
        margin-top: 10px; height: 8px; border-radius: 999px; background: #333; overflow: hidden;
      }
      .fill {
        height: 100%; width: 0%; border-radius: 999px; background: #f97316;
        transition: width .12s linear;
      }
      .fill.done { background: #22c55e; }
      .fill.fail { background: #ef4444; width: 100% !important; }
      .status { margin-top: 8px; font-size: 12px; color: #aaa; }
      .status.ok { color: #86efac; }
      .status.err { color: #fca5a5; }
      .status.run { color: #fdba74; }
    </style>
    </head><body>
    <h1>Mixtube</h1>
    <p class="sub">Choose audio files to import onto this phone. Progress for each track appears below.</p>
    <div class="box" id="drop">
      <div>Drop files here or</div>
      <label class="pick" for="file">Select files</label>
      <input id="file" type="file" accept="audio/*,video/mp4,video/quicktime,.mp3,.m4a,.flac,.wav,.aac,.ogg,.opus" multiple/>
    </div>
    <div class="summary" id="summary">No files yet.</div>
    <ul id="list"></ul>
    <script>
    const input = document.getElementById('file');
    const listEl = document.getElementById('list');
    const summaryEl = document.getElementById('summary');
    const drop = document.getElementById('drop');
    const queue = [];
    let running = false;

    function fmtSize(n) {
      if (n < 1024) return n + ' B';
      if (n < 1024 * 1024) return (n / 1024).toFixed(1) + ' KB';
      return (n / (1024 * 1024)).toFixed(1) + ' MB';
    }

    function updateSummary() {
      const total = queue.length;
      const done = queue.filter(i => i.state === 'done').length;
      const fail = queue.filter(i => i.state === 'fail').length;
      const active = queue.filter(i => i.state === 'uploading' || i.state === 'pending').length;
      if (!total) { summaryEl.textContent = 'No files yet.'; return; }
      summaryEl.textContent = total + ' track(s) · ' + done + ' imported · ' + fail + ' failed · ' + active + ' in progress';
    }

    function renderItem(item) {
      const pct = Math.max(0, Math.min(100, Math.round(item.progress || 0)));
      let statusText = 'Waiting…';
      let statusClass = '';
      let fillClass = 'fill';
      if (item.state === 'uploading') {
        statusText = 'Uploading ' + pct + '%';
        statusClass = 'run';
      } else if (item.state === 'done') {
        statusText = 'Imported';
        statusClass = 'ok';
        fillClass = 'fill done';
      } else if (item.state === 'fail') {
        statusText = item.error || 'Failed';
        statusClass = 'err';
        fillClass = 'fill fail';
      }
      item.row.innerHTML =
        '<div class="top"><div class="name"></div><div class="meta"></div></div>' +
        '<div class="bar"><div class="' + fillClass + '" style="width:' + (item.state === 'fail' ? 100 : pct) + '%"></div></div>' +
        '<div class="status ' + statusClass + '"></div>';
      item.row.querySelector('.name').textContent = item.file.name;
      item.row.querySelector('.meta').textContent = fmtSize(item.file.size);
      item.row.querySelector('.status').textContent = statusText;
    }

    function enqueue(files) {
      const arr = [...files].filter(Boolean);
      if (!arr.length) return;
      for (const file of arr) {
        const row = document.createElement('li');
        row.className = 'row';
        listEl.appendChild(row);
        const item = { file, row, state: 'pending', progress: 0, error: '' };
        queue.push(item);
        renderItem(item);
      }
      updateSummary();
      pump();
    }

    function uploadOne(item) {
      return new Promise((resolve) => {
        item.state = 'uploading';
        item.progress = 0;
        renderItem(item);
        updateSummary();
        const fd = new FormData();
        fd.append('file', item.file, item.file.name);
        const xhr = new XMLHttpRequest();
        xhr.open('POST', '/upload');
        xhr.upload.onprogress = (ev) => {
          if (!ev.lengthComputable) return;
          item.progress = (ev.loaded / ev.total) * 100;
          renderItem(item);
        };
        xhr.onload = () => {
          if (xhr.status >= 200 && xhr.status < 300) {
            item.state = 'done';
            item.progress = 100;
          } else {
            item.state = 'fail';
            item.error = 'Server error ' + xhr.status;
          }
          renderItem(item);
          updateSummary();
          resolve();
        };
        xhr.onerror = () => {
          item.state = 'fail';
          item.error = 'Network error';
          renderItem(item);
          updateSummary();
          resolve();
        };
        xhr.send(fd);
      });
    }

    async function pump() {
      if (running) return;
      running = true;
      while (true) {
        const next = queue.find(i => i.state === 'pending');
        if (!next) break;
        await uploadOne(next);
      }
      running = false;
      updateSummary();
    }

    input.addEventListener('change', () => {
      enqueue(input.files);
      input.value = '';
    });

    ;['dragenter','dragover'].forEach(type => {
      drop.addEventListener(type, (e) => {
        e.preventDefault(); e.stopPropagation();
        drop.classList.add('drag');
      });
    });
    ;['dragleave','drop'].forEach(type => {
      drop.addEventListener(type, (e) => {
        e.preventDefault(); e.stopPropagation();
        drop.classList.remove('drag');
      });
    });
    drop.addEventListener('drop', (e) => {
      enqueue(e.dataTransfer && e.dataTransfer.files);
    });
    </script>
    </body></html>
    """#

    /// Prefer Wi‑Fi (en0), then other en* / bridge / personal hotspot interfaces.
    private static func primaryLANAddress() -> String? {
        var candidates: [(priority: Int, ip: String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0, (flags & IFF_LOOPBACK) == 0 else {
                continue
            }
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = String(cString: hostname)
            guard !ip.hasPrefix("127."), !ip.hasPrefix("169.254.") else { continue }
            let priority: Int
            if name == "en0" { priority = 0 }
            else if name.hasPrefix("en") { priority = 1 }
            else if name.hasPrefix("bridge") || name.hasPrefix("ap") { priority = 2 }
            else { priority = 3 }
            candidates.append((priority, ip))
        }
        return candidates.sorted { $0.priority < $1.priority }.first?.ip
    }
}

/// One finished Mac cache file offered to Mixtube on iPhone. Not used by the system share sheet.
struct MacCacheTrackRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String { videoId }
    let videoId: String
    let title: String
    let artist: String
    let durationSeconds: Int
    let byteCount: Int64
    let fileExtension: String
    let hasCover: Bool
}

private struct MacCacheTrackListBody: Codable {
    let tracks: [MacCacheTrackRecord]
}

private struct MacCachePairRequest: Codable {
    let code: String
}

private struct MacCachePairResponse: Codable {
    let token: String
}

enum MacCacheTransferError: Error {
    case unauthorized
    case failed
}

enum MacCacheHTTP {
    static func peerParameters() -> NWParameters {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        params.allowLocalEndpointReuse = true
        return params
    }

    static func exchange(
        endpoint: NWEndpoint,
        requestData: Data,
        fileDestination: URL?
    ) async throws -> (status: Int, data: Data) {
        let connection = NWConnection(to: endpoint, using: peerParameters())
        let queue = DispatchQueue(label: "ytlite.mac-cache.client")
        try await waitUntilReady(connection, queue: queue)
        defer { connection.cancel() }
        try await send(connection, data: requestData)
        return try await readResponse(connection, fileDestination: fileDestination)
    }

    static func requestData(method: String, path: String, token: String?, body: Data?) -> Data {
        var lines = [
            "\(method) \(path) HTTP/1.1",
            "Host: mixtube.local",
            "Connection: close",
        ]
        if let token {
            lines.append("Authorization: Bearer \(token)")
        }
        if let body {
            lines.append("Content-Type: application/json")
            lines.append("Content-Length: \(body.count)")
        }
        var data = Data(lines.joined(separator: "\r\n").utf8)
        data.append(Data("\r\n\r\n".utf8))
        if let body { data.append(body) }
        return data
    }

    private static func waitUntilReady(_ connection: NWConnection, queue: DispatchQueue) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ResumeOnce()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.run { continuation.resume() }
                case .failed(let error):
                    gate.run { continuation.resume(throwing: error) }
                case .cancelled:
                    gate.run { continuation.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private static func send(_ connection: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private static func receive(_ connection: NWConnection) async throws -> (Data?, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data, isComplete))
                }
            }
        }
    }

    private static func readResponse(
        _ connection: NWConnection,
        fileDestination: URL?
    ) async throws -> (status: Int, data: Data) {
        let marker = Data("\r\n\r\n".utf8)
        var buffer = Data()
        var status = 0
        var contentLength = 0
        var headerParsed = false
        var body = Data()
        var receivedBody = 0
        var file: FileHandle?
        if let fileDestination {
            FileManager.default.createFile(atPath: fileDestination.path, contents: nil)
            file = try FileHandle(forWritingTo: fileDestination)
        }
        defer { try? file?.close() }

        while true {
            try Task.checkCancellation()
            let (chunk, isComplete) = try await receive(connection)
            if let chunk, !chunk.isEmpty { buffer.append(chunk) }
            if !headerParsed, let headerEnd = buffer.range(of: marker) {
                let headerText = String(data: buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound), encoding: .utf8) ?? ""
                status = statusCode(from: headerText)
                contentLength = lengthValue(from: headerText)
                guard contentLength <= 512 * 1024 * 1024 else { throw MacCacheTransferError.failed }
                headerParsed = true
                let prefix = buffer.subdata(in: headerEnd.upperBound..<buffer.endIndex)
                buffer.removeAll(keepingCapacity: false)
                receivedBody += try appendBody(prefix, file: file, memory: &body)
            } else if headerParsed, !buffer.isEmpty {
                receivedBody += try appendBody(buffer, file: file, memory: &body)
                buffer.removeAll(keepingCapacity: false)
            }
            if headerParsed, receivedBody >= contentLength { break }
            if isComplete { break }
        }
        return (status, body)
    }

    private static func appendBody(_ data: Data, file: FileHandle?, memory: inout Data) throws -> Int {
        guard !data.isEmpty else { return 0 }
        if let file {
            try file.write(contentsOf: data)
        } else {
            memory.append(data)
        }
        return data.count
    }

    private static func statusCode(from header: String) -> Int {
        let line = header.split(separator: "\r\n", maxSplits: 1).first ?? ""
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return 0 }
        return Int(parts[1]) ?? 0
    }

    private static func lengthValue(from header: String) -> Int {
        for line in header.split(separator: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            let raw = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
            return Int(raw) ?? 0
        }
        return 0
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private var done = false
    func run(_ body: () -> Void) {
        guard !done else { return }
        done = true
        body()
    }
}

#if targetEnvironment(macCatalyst)
/// Mac listens only while “Send to iPhone” is open. A pairing code is required before any file is sent.
@MainActor
final class MacCacheTransferServer: ObservableObject {
    static let shared = MacCacheTransferServer()

    @Published private(set) var pairingCode = ""
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var servedCount = 0

    private var listener: NWListener?
    private var token = ""
    private var tracks: [MacCacheTrackRecord] = []
    private var audioFiles: [String: URL] = [:]
    private var coverFiles: [String: URL] = [:]
    private let port: UInt16 = 8788
    private let bonjourType = "_mixtube-cache._tcp"

    private init() {}

    func start(tracks: [MacCacheTrackRecord], audio: [String: URL], covers: [String: URL]) {
        stop()
        self.tracks = tracks
        audioFiles = audio
        coverFiles = covers
        pairingCode = String(format: "%06d", Int.random(in: 0...999_999))
        token = UUID().uuidString
        servedCount = 0
        lastError = nil
        do {
            let listener = try NWListener(using: MacCacheHTTP.peerParameters(), on: NWEndpoint.Port(rawValue: port)!)
            listener.service = NWListener.Service(name: "Mixtube Mac", type: bonjourType)
            listener.newConnectionHandler = { [weak self] connection in
                Self.accept(connection) { request in
                    await self?.handle(request, connection: connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                    case .failed(let error):
                        self.lastError = error.localizedDescription
                        self.isRunning = false
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener.start(queue: DispatchQueue(label: "ytlite.mac-cache.listen", qos: .userInitiated))
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
            isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        token = ""
        tracks = []
        audioFiles = [:]
        coverFiles = [:]
    }

    private nonisolated static func accept(
        _ connection: NWConnection,
        onRequest: @escaping @Sendable (WiFiImportServer.HTTPRequest) async -> Void
    ) {
        connection.start(queue: DispatchQueue(label: "ytlite.mac-cache.conn", qos: .userInitiated))
        readHTTP(connection: connection, buffer: Data(), onRequest: onRequest)
    }

    private nonisolated static func readHTTP(
        connection: NWConnection,
        buffer: Data,
        onRequest: @escaping @Sendable (WiFiImportServer.HTTPRequest) async -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, isComplete, error in
            if error != nil {
                connection.cancel()
                return
            }
            var next = buffer
            if let data, !data.isEmpty { next.append(data) }
            if let request = WiFiImportServer.tryParseHTTPRequest(next) {
                Task { await onRequest(request) }
                return
            }
            if isComplete || next.count > 2 * 1024 * 1024 {
                connection.cancel()
                return
            }
            readHTTP(connection: connection, buffer: next, onRequest: onRequest)
        }
    }

    private func handle(_ request: WiFiImportServer.HTTPRequest, connection: NWConnection) {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        let parts = path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        if request.method == "POST", parts == ["v1", "pair"] {
            let code = (try? JSONDecoder().decode(MacCachePairRequest.self, from: request.body))?.code
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard code == pairingCode, !token.isEmpty,
                  let body = try? JSONEncoder().encode(MacCachePairResponse(token: token))
            else {
                Self.respond(connection, status: 401, body: Data("{}".utf8))
                return
            }
            Self.respond(connection, status: 200, type: "application/json", body: body)
            return
        }

        guard bearer(request.headers) == token, !token.isEmpty else {
            Self.respond(connection, status: 401, body: Data("{}".utf8))
            return
        }
        if request.method == "GET", parts == ["v1", "tracks"],
           let body = try? JSONEncoder().encode(MacCacheTrackListBody(tracks: tracks)) {
            Self.respond(connection, status: 200, type: "application/json", body: body)
            return
        }
        if request.method == "GET", parts.count == 4, parts[0] == "v1", parts[1] == "tracks",
           Self.isSafeVideoID(parts[2]) {
            let videoId = parts[2]
            if parts[3] == "audio", let url = audioFiles[videoId] {
                servedCount += 1
                Self.respondFile(connection, url: url, type: Self.audioType(for: url))
                return
            }
            if parts[3] == "cover", let url = coverFiles[videoId] {
                Self.respondFile(connection, url: url, type: "image/jpeg")
                return
            }
        }
        Self.respond(connection, status: 404, body: Data())
    }

    private func bearer(_ headers: String) -> String? {
        for line in headers.split(separator: "\r\n") {
            let lower = line.lowercased()
            guard lower.hasPrefix("authorization:") else { continue }
            let value = line.dropFirst("authorization:".count).trimmingCharacters(in: .whitespaces)
            guard value.lowercased().hasPrefix("bearer ") else { return nil }
            return String(value.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func isSafeVideoID(_ id: String) -> Bool {
        guard (6...64).contains(id.count) else { return false }
        return id.allSatisfy { ch in
            ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-" || ch == "_")
        }
    }

    private static func audioType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "mp4", "aac": return "audio/mp4"
        default: return "application/octet-stream"
        }
    }

    private nonisolated static func respond(
        _ connection: NWConnection,
        status: Int,
        type: String = "application/json",
        body: Data
    ) {
        let reason = status == 200 ? "OK" : (status == 401 ? "Unauthorized" : "Not Found")
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private nonisolated static func respondFile(_ connection: NWConnection, url: URL, type: String) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            respond(connection, status: 404, body: Data())
            return
        }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: 0)
        let header = Data("HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(size)\r\nConnection: close\r\n\r\n".utf8)
        FileSender(connection: connection, handle: handle).send(next: header, readingFileAfter: true)
    }
}

private final class FileSender: @unchecked Sendable {
    private let connection: NWConnection
    private let handle: FileHandle
    private let chunkSize = 64 * 1024

    init(connection: NWConnection, handle: FileHandle) {
        self.connection = connection
        self.handle = handle
    }

    func send(next: Data, readingFileAfter: Bool) {
        if next.isEmpty {
            try? handle.close()
            connection.cancel()
            return
        }
        connection.send(content: next, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                try? self.handle.close()
                self.connection.cancel()
                return
            }
            guard readingFileAfter else {
                try? self.handle.close()
                self.connection.cancel()
                return
            }
            let nextChunk = (try? self.handle.read(upToCount: self.chunkSize)) ?? Data()
            self.send(next: nextChunk, readingFileAfter: !nextChunk.isEmpty)
        })
    }
}
#endif

#if !targetEnvironment(macCatalyst)
@MainActor
final class MacCacheTransferBrowser: ObservableObject {
    struct Device: Identifiable {
        let id: String
        let name: String
        let endpoint: NWEndpoint
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var lastError: String?
    private var browser: NWBrowser?

    func start() {
        stop()
        let browser = NWBrowser(
            for: .bonjour(type: "_mixtube-cache._tcp", domain: nil),
            using: MacCacheHTTP.peerParameters()
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found: [Device] = results.compactMap { result in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                return Device(id: name, name: name, endpoint: result.endpoint)
            }
            Task { @MainActor in
                self?.devices = found
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case let .failed(error) = state {
                Task { @MainActor in
                    self?.lastError = error.localizedDescription
                }
            }
        }
        browser.start(queue: DispatchQueue(label: "ytlite.mac-cache.browse"))
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}

struct MacCacheTransferSession {
    let endpoint: NWEndpoint
    let token: String

    static func pair(endpoint: NWEndpoint, code: String) async throws -> MacCacheTransferSession {
        let body = try JSONEncoder().encode(MacCachePairRequest(code: code))
        let request = MacCacheHTTP.requestData(method: "POST", path: "/v1/pair", token: nil, body: body)
        let (status, data) = try await MacCacheHTTP.exchange(
            endpoint: endpoint,
            requestData: request,
            fileDestination: nil
        )
        guard status == 200, let decoded = try? JSONDecoder().decode(MacCachePairResponse.self, from: data) else {
            throw MacCacheTransferError.unauthorized
        }
        return MacCacheTransferSession(endpoint: endpoint, token: decoded.token)
    }

    func tracks() async throws -> [MacCacheTrackRecord] {
        let request = MacCacheHTTP.requestData(method: "GET", path: "/v1/tracks", token: token, body: nil)
        let (status, data) = try await MacCacheHTTP.exchange(
            endpoint: endpoint,
            requestData: request,
            fileDestination: nil
        )
        guard status == 200, let decoded = try? JSONDecoder().decode(MacCacheTrackListBody.self, from: data) else {
            throw status == 401 ? MacCacheTransferError.unauthorized : MacCacheTransferError.failed
        }
        return decoded.tracks
    }

    func download(videoId: String, kind: String, to destination: URL) async throws {
        let request = MacCacheHTTP.requestData(
            method: "GET",
            path: "/v1/tracks/\(videoId)/\(kind)",
            token: token,
            body: nil
        )
        let (status, _) = try await MacCacheHTTP.exchange(
            endpoint: endpoint,
            requestData: request,
            fileDestination: destination
        )
        guard status == 200 else {
            throw status == 401 ? MacCacheTransferError.unauthorized : MacCacheTransferError.failed
        }
    }
}
#endif
