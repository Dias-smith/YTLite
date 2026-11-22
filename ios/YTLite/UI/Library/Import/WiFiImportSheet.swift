import AVFoundation
import CoreImage.CIFilterBuiltins
import Network
import SwiftUI

struct WiFiImportSheet: View {
    var onImported: () -> Void

    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var server = WiFiImportServer.shared
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        Text(L("import.wifi.hint"))
                            .font(YTLiteType.body)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        if server.isRunning {
                            Text(L("import.wifi.running"))
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.accent)
                        }

                        if let url = server.listenURL {
                            Text(url.absoluteString)
                                .font(YTLiteType.sectionTitle)
                                .foregroundStyle(YTLiteColor.onSurface)
                                .textSelection(.enabled)
                                .contextMenu {
                                    Button(L("import.wifi.copy")) {
                                        UIPasteboard.general.string = url.absoluteString
                                    }
                                }
                            if let qr = mixtubeQRImage(for: url.absoluteString) {
                                Image(uiImage: qr)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 200, height: 200)
                                    .padding()
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                            }
                            Button(L("import.wifi.copy")) {
                                UIPasteboard.general.string = url.absoluteString
                            }
                            .font(YTLiteType.labelEmphasized)
                            .foregroundStyle(YTLiteColor.accent)
                        } else if let err = server.lastError {
                            Text(err)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Button(L("import.wifi.retry")) {
                                server.start()
                            }
                            .font(YTLiteType.labelEmphasized)
                            .foregroundStyle(YTLiteColor.accent)
                        } else if server.isRunning {
                            ProgressView()
                            Text(L("import.wifi.waiting_ip"))
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        }

                        Text(Lf("import.wifi.imported_count", server.importedCount))
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)

                        if server.failedCount > 0 {
                            Text(Lf("import.wifi.failed_count", server.failedCount))
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        }

                        if let message {
                            Text(message)
                                .font(YTLiteType.meta)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                }

                YTLiteSheetPrimaryButton(title: L("import.wifi.close_stop")) {
                    closeAndStop()
                }
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .ytLiteAppBackground()
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) {
                Text(L("import.source.wifi"))
                    .font(YTLiteType.sectionTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .interactiveDismissDisabled(true)
            .onAppear {
                message = nil
                server.onFileReceived = { data, filename in
                    guard let store else { return false }
                    let ext = (filename as NSString).pathExtension
                    do {
                        _ = try await ImportIngestService.shared.ingestData(
                            data,
                            fileExtension: ext.isEmpty ? "mp3" : ext,
                            fileName: filename,
                            sourceKind: .wifi,
                            store: store
                        )
                        message = nil
                        onImported()
                        return true
                    } catch {
                        message = error.localizedDescription
                        return false
                    }
                }
                server.start()
            }
            .onDisappear {
                server.stop()
                server.onFileReceived = nil
            }
        }
    }

    private func closeAndStop() {
        server.stop()
        server.onFileReceived = nil
        dismiss()
    }
}

func mixtubeQRImage(for string: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    let context = CIContext()
    guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: cg)
}

#if targetEnvironment(macCatalyst)
struct MacCacheSendSheet: View {
    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var server = MacCacheTransferServer.shared
    @State private var songCount = 0
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if !loaded {
                    ProgressView()
                } else if songCount == 0 {
                    Text(L("import.mac.no_songs"))
                        .font(YTLiteType.body)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            Text(L("import.mac.code_hint"))
                                .font(YTLiteType.body)
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                .multilineTextAlignment(.center)
                            Text(server.pairingCode)
                                .font(YTLiteType.pageTitle)
                                .monospacedDigit()
                                .foregroundStyle(YTLiteColor.onSurface)
                            if let address = server.listenAddress {
                                Text(L("import.mac.address_hint"))
                                    .font(YTLiteType.body)
                                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                    .multilineTextAlignment(.center)
                                Text(address)
                                    .font(YTLiteType.sectionTitle)
                                    .monospacedDigit()
                                    .foregroundStyle(YTLiteColor.onSurface)
                                Text(L("import.mac.qr_hint"))
                                    .font(YTLiteType.body)
                                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                    .multilineTextAlignment(.center)
                                if let qr = mixtubeQRImage(for: MacCacheLink.payload(host: address, code: server.pairingCode)) {
                                    Image(uiImage: qr)
                                        .interpolation(.none)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 200, height: 200)
                                        .padding()
                                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            Text(L("import.mac.waiting"))
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.accent)
                            Text(Lf("import.mac.cached_count", songCount))
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            if let progress = server.sendProgress, progress.totalBytes > 0 {
                                Text(progress.title)
                                    .font(YTLiteType.rowTitle)
                                    .foregroundStyle(YTLiteColor.onSurface)
                                    .lineLimit(1)
                                ProgressView(
                                    value: Double(progress.sentBytes),
                                    total: Double(progress.totalBytes)
                                )
                                .tint(YTLiteColor.accent)
                                Text("\(min(100, Int((Double(progress.sentBytes) / Double(progress.totalBytes) * 100).rounded())))%")
                                    .font(YTLiteType.meta)
                                    .monospacedDigit()
                                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            }
                            if server.servedCount > 0 {
                                Text(Lf("import.mac.sent_count", server.servedCount))
                                    .font(YTLiteType.meta)
                                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            }
                            if let lastError = server.lastError {
                                Text(lastError)
                                    .font(YTLiteType.meta)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, YTLiteLayout.screenPadding)
                    }
                }
                Spacer(minLength: 0)
                YTLiteSheetPrimaryButton(title: L("common.close")) {
                    server.stop()
                    dismiss()
                }
                .padding(.bottom, 28)
            }
            .padding(.top, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ytLiteAppBackground()
            .navigationBarHidden(true)
            .interactiveDismissDisabled(true)
            .task { await reload() }
            .onDisappear { server.stop() }
        }
    }

    private func reload() async {
        let snapshots = await PlaybackMediaStore.shared.cachedSnapshots()
        var records: [MacCacheTrackRecord] = []
        var audio: [String: URL] = [:]
        var covers: [String: URL] = [:]
        for snapshot in snapshots {
            guard let file = await PlaybackMediaStore.shared.localFileURL(videoId: snapshot.videoId) else { continue }
            let row = store?.track(id: snapshot.videoId)
            let title = row?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let ext = file.pathExtension.isEmpty ? "m4a" : file.pathExtension.lowercased()
            let cover = PlaybackCachedCover.fileURL(videoId: snapshot.videoId)
            let hasCover = FileManager.default.fileExists(atPath: cover.path)
            records.append(
                MacCacheTrackRecord(
                    videoId: snapshot.videoId,
                    title: (title?.isEmpty == false ? title! : snapshot.videoId),
                    artist: row?.primaryArtistName ?? "",
                    durationSeconds: row?.durationSeconds ?? 0,
                    byteCount: snapshot.fileSize,
                    fileExtension: ext,
                    hasCover: hasCover
                )
            )
            audio[snapshot.videoId] = file
            if hasCover { covers[snapshot.videoId] = cover }
        }
        var seen = Set(records.map(\.videoId))
        for track in store?.importedTracks() ?? [] {
            guard seen.insert(track.trackId).inserted else { continue }
            guard MacCacheHTTP.isSafeTrackID(track.trackId) else { continue }
            guard let file = LocalMediaStore.shared.audioURL(
                trackId: track.trackId,
                relativePath: track.localRelativePath
            ) else { continue }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            guard size > 0 else { continue }
            let ext = file.pathExtension.isEmpty ? "m4a" : file.pathExtension.lowercased()
            let cover = ImportCoverStorage.fileURL(trackId: track.trackId)
            let hasCover = FileManager.default.fileExists(atPath: cover.path)
            let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
            records.append(
                MacCacheTrackRecord(
                    videoId: track.trackId,
                    title: title.isEmpty ? track.trackId : title,
                    artist: track.primaryArtistName ?? "",
                    durationSeconds: track.durationSeconds,
                    byteCount: size,
                    fileExtension: ext,
                    hasCover: hasCover
                )
            )
            audio[track.trackId] = file
            if hasCover { covers[track.trackId] = cover }
        }
        songCount = records.count
        loaded = true
        if records.isEmpty {
            server.stop()
        } else {
            server.start(tracks: records, audio: audio, covers: covers)
        }
    }
}
#endif

#if !targetEnvironment(macCatalyst)
struct MacCacheReceiveSheet: View {
    var onImported: () -> Void

    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = MacCacheTransferBrowser()
    @State private var selectedDeviceID: String?
    @State private var address = ""
    @State private var code = ""
    @State private var session: MacCacheTransferSession?
    @State private var tracks: [MacCacheTrackRecord] = []
    @State private var selected: Set<String> = []
    @State private var message: String?
    @State private var isBusy = false
    @State private var progressText: String?
    @StateObject private var transfer = MacCacheImportProgress()
    @State private var importTask: Task<Void, Never>?
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if session == nil {
                            browseBody
                        } else {
                            trackBody
                        }
                        if let message {
                            Text(message)
                                .font(YTLiteType.meta)
                                .foregroundStyle(.red)
                        }
                        if let progressText {
                            Text(progressText)
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        }
                        if isBusy, !transfer.title.isEmpty {
                            Text(transfer.title)
                                .font(YTLiteType.rowTitle)
                                .foregroundStyle(YTLiteColor.onSurface)
                                .lineLimit(1)
                            ProgressView(value: transfer.fraction)
                                .tint(YTLiteColor.accent)
                            Text("\(transfer.percent)%")
                                .font(YTLiteType.meta)
                                .monospacedDigit()
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                }
                YTLiteSheetPrimaryButton(title: L("common.close")) {
                    close()
                }
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .ytLiteAppBackground()
            .navigationBarHidden(true)
            .interactiveDismissDisabled(isBusy)
            .onAppear { browser.start() }
            .onDisappear {
                importTask?.cancel()
                browser.stop()
            }
            .sheet(isPresented: $showScanner) {
                MacCacheQRScanner { raw in
                    guard let link = MacCacheLink.parse(raw) else { return false }
                    address = link.host
                    code = link.code
                    showScanner = false
                    importTask = Task { await pair() }
                    return true
                }
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    YTLiteSheetPrimaryButton(title: L("common.close")) {
                        showScanner = false
                    }
                    .padding(.bottom, 28)
                }
            }
        }
    }

    private var browseBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("import.source.mac_receive.hint"))
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            if browser.devices.isEmpty {
                Text(L("import.mac.no_devices"))
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            } else {
                ForEach(browser.devices) { device in
                    Button {
                        selectedDeviceID = device.id
                    } label: {
                        HStack {
                            Text(device.name)
                                .font(YTLiteType.rowTitle)
                                .foregroundStyle(YTLiteColor.onSurface)
                            Spacer()
                            if selectedDeviceID == device.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(YTLiteColor.accent)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField(L("import.mac.enter_address"), text: $address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
            TextField(L("import.mac.enter_code"), text: $code)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            Button(L("import.mac.pair")) {
                Task { await pair() }
            }
            .font(YTLiteType.labelEmphasized)
            .foregroundStyle(YTLiteColor.accent)
            .disabled(isBusy || pairEndpoint == nil || code.trimmingCharacters(in: .whitespaces).count < 4)
            Button(L("import.mac.scan")) {
                Task { await openScanner() }
            }
            .font(YTLiteType.labelEmphasized)
            .foregroundStyle(YTLiteColor.accent)
            .disabled(isBusy)
        }
    }

    private var trackBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tracks.isEmpty {
                Text(L("import.mac.no_songs"))
                    .font(YTLiteType.body)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            } else {
                ForEach(tracks) { track in
                    Button {
                        if selected.contains(track.videoId) {
                            selected.remove(track.videoId)
                        } else {
                            selected.insert(track.videoId)
                        }
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(track.videoId) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(YTLiteColor.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(YTLiteType.rowTitle)
                                    .foregroundStyle(YTLiteColor.onSurface)
                                    .lineLimit(1)
                                if !track.artist.isEmpty {
                                    Text(track.artist)
                                        .font(YTLiteType.meta)
                                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
                Button(L("import.mac.import_songs")) {
                    importTask?.cancel()
                    importTask = Task { await importSelected() }
                }
                .font(YTLiteType.labelEmphasized)
                .foregroundStyle(YTLiteColor.accent)
                .disabled(isBusy || selected.isEmpty)
            }
        }
    }

    private var selectedDevice: MacCacheTransferBrowser.Device? {
        browser.devices.first { $0.id == selectedDeviceID } ?? browser.devices.first
    }

    /// A typed address wins, so a Bonjour miss does not block the transfer.
    private var pairEndpoint: NWEndpoint? {
        let host = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isIPv4(host) {
            return .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: MacCacheHTTP.port)!)
        }
        return selectedDevice?.endpoint
    }

    private static func isIPv4(_ raw: String) -> Bool {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), (0...255).contains(value), part.count <= 3 else { return false }
            return true
        }
    }

    private func pair() async {
        guard let endpoint = pairEndpoint else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let paired = try await MacCacheTransferSession.pair(
                endpoint: endpoint,
                code: code.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let listed = try await paired.tracks()
            session = paired
            tracks = listed
            selected = Set(listed.map(\.videoId))
        } catch is CancellationError {
            return
        } catch MacCacheTransferError.unauthorized {
            message = L("import.mac.pair_failed")
        } catch {
            message = error.localizedDescription
        }
    }

    private func importSelected() async {
        guard let session, let store else { return }
        let chosen = tracks.filter { selected.contains($0.videoId) }
        guard !chosen.isEmpty else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        var done = 0
        var failed = 0
        for track in chosen {
            if Task.isCancelled { break }
            done += 1
            progressText = Lf("import.mac.progress", Int64(done), Int64(chosen.count))
            transfer.begin(title: track.title)
            let uri = "mac-cache:\(track.videoId)"
            if store.importedTrack(remoteURI: uri) != nil { continue }
            let ext = track.fileExtension.filter { $0.isLetter || $0.isNumber }
            let safeExt = ext.isEmpty ? "m4a" : ext.lowercased()
            let audioURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(safeExt)
            do {
                try Task.checkCancellation()
                try await session.download(videoId: track.videoId, kind: "audio", to: audioURL) { received, total in
                    transfer.note(received: received, total: total)
                }
                try Task.checkCancellation()
                transfer.flush()
                MacCacheProbe.log("ingest-start", "title=\(track.title) pct=\(transfer.percent)")
                let result = try await ImportIngestService.shared.ingestFileURL(
                    audioURL,
                    sourceKind: .mac,
                    store: store,
                    titleHint: track.title,
                    artistHint: track.artist,
                    remoteURI: uri,
                    cacheEligible: false
                )
                if let row = store.track(id: result.trackId),
                   row.remoteURI == nil || row.remoteURI?.isEmpty == true {
                    row.remoteURI = uri
                    store.saveLocalOnly()
                }
                if track.hasCover, ImportCoverStorage.existingURL(trackId: result.trackId) == nil {
                    let coverURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("jpg")
                    try? await session.download(videoId: track.videoId, kind: "cover", to: coverURL)
                    if let data = try? Data(contentsOf: coverURL), !data.isEmpty {
                        try? ImportIngestService.shared.attachCover(
                            trackId: result.trackId,
                            jpeg: data,
                            store: store
                        )
                    }
                    try? FileManager.default.removeItem(at: coverURL)
                }
                try? FileManager.default.removeItem(at: audioURL)
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: audioURL)
                break
            } catch {
                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: audioURL)
                    break
                }
                failed += 1
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
        progressText = nil
        transfer.begin(title: "")
        if Task.isCancelled { return }
        if failed > 0 {
            message = Lf("import.wifi.failed_count", failed)
        }
        onImported()
    }

    private func close() {
        importTask?.cancel()
        browser.stop()
        dismiss()
    }

    private func openScanner() async {
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        if allowed {
            showScanner = true
        } else {
            message = L("import.mac.camera_denied")
        }
    }
}
#endif

/// Phone-side transfer meter. Socket callbacks publish through this object.
/// Writing `@State` from those callbacks captured a view copy that stayed at 0%.
final class MacCacheImportProgress: ObservableObject, @unchecked Sendable {
    @MainActor @Published private(set) var fraction: Double = 0
    @MainActor @Published private(set) var title = ""
    @MainActor var percent: Int { Int((fraction * 100).rounded()) }

    private let lock = NSLock()
    private var latestReceived: Int64 = 0
    private var latestTotal: Int64 = 0

    @MainActor
    func begin(title: String) {
        self.title = title
        fraction = 0
        lock.lock()
        latestReceived = 0
        latestTotal = 0
        lock.unlock()
        MacCacheProbe.reset()
        MacCacheProbe.log("ui-reset", "title=\(title)")
    }

    /// Called from the socket queue. The sample is stored immediately and published on the main queue.
    func note(received: Int64, total: Int64) {
        lock.lock()
        latestReceived = received
        latestTotal = total
        lock.unlock()
        MacCacheProbe.logProgress("cb", received: received, total: total)
        DispatchQueue.main.async { [weak self] in
            self?.publish(received: received, total: total, stage: "ui")
        }
    }

    /// Paint the latest sample before the main actor starts the slow local save.
    @MainActor
    func flush() {
        lock.lock()
        let received = latestReceived
        let total = latestTotal
        lock.unlock()
        guard total > 0 else {
            MacCacheProbe.log("ui-flush", "no samples — callback never reported a length")
            return
        }
        publish(received: received, total: total, stage: "ui-flush")
    }

    @MainActor
    private func publish(received: Int64, total: Int64, stage: String) {
        let next = total > 0 ? min(1, Double(received) / Double(total)) : 0
        fraction = next
        MacCacheProbe.logProgress(stage, received: received, total: total)
    }
}

#if !targetEnvironment(macCatalyst)
private struct MacCacheQRScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Bool

    func makeUIViewController(context: Context) -> MacCacheQRScannerController {
        let controller = MacCacheQRScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ controller: MacCacheQRScannerController, context: Context) {
        controller.onCode = onCode
    }
}

private final class MacCacheQRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Bool)?
    private let session = AVCaptureSession()
    private let preview = AVCaptureVideoPreviewLayer()
    private var didEmit = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        preview.session = session
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didEmit,
              let value = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first?.stringValue,
              onCode?(value) == true
        else { return }
        didEmit = true
        session.stopRunning()
    }
}
#endif
