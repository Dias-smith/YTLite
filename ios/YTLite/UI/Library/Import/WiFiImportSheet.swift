import CoreImage.CIFilterBuiltins
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
                            if let qr = qrImage(for: url.absoluteString) {
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

    private func qrImage(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
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
                    Text(L("import.mac.code_hint"))
                        .font(YTLiteType.body)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Text(server.pairingCode)
                        .font(YTLiteType.pageTitle)
                        .monospacedDigit()
                        .foregroundStyle(YTLiteColor.onSurface)
                    Text(L("import.mac.waiting"))
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.accent)
                    Text(Lf("import.mac.cached_count", songCount))
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
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
    @State private var code = ""
    @State private var session: MacCacheTransferSession?
    @State private var tracks: [MacCacheTrackRecord] = []
    @State private var selected: Set<String> = []
    @State private var message: String?
    @State private var isBusy = false
    @State private var progressText: String?

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
                .disabled(isBusy)
            }
            .ytLiteAppBackground()
            .navigationBarHidden(true)
            .interactiveDismissDisabled(true)
            .onAppear { browser.start() }
            .onDisappear { browser.stop() }
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
            TextField(L("import.mac.enter_code"), text: $code)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            Button(L("import.mac.pair")) {
                Task { await pair() }
            }
            .font(YTLiteType.labelEmphasized)
            .foregroundStyle(YTLiteColor.accent)
            .disabled(isBusy || selectedDevice == nil || code.trimmingCharacters(in: .whitespaces).count < 4)
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
                    Task { await importSelected() }
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

    private func pair() async {
        guard let device = selectedDevice else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let paired = try await MacCacheTransferSession.pair(
                endpoint: device.endpoint,
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
            let uri = "mac-cache:\(track.videoId)"
            if store.importedTrack(remoteURI: uri) != nil { continue }
            let ext = track.fileExtension.filter { $0.isLetter || $0.isNumber }
            let safeExt = ext.isEmpty ? "m4a" : ext.lowercased()
            let audioURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(safeExt)
            do {
                try await session.download(videoId: track.videoId, kind: "audio", to: audioURL)
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
            } catch {
                failed += 1
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
        progressText = nil
        if failed > 0 {
            message = Lf("import.wifi.failed_count", failed)
        }
        onImported()
    }

    private func close() {
        browser.stop()
        dismiss()
    }
}
#endif
