import AVFoundation
import CoreImage.CIFilterBuiltins
import Network
import SwiftUI
import UIKit

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
    /// Sidebar page has no cover to dismiss. The transfer still stops when the page disappears.
    var showsCloseButton: Bool = true
    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var server = MacCacheTransferServer.shared
    @State private var tracks: [MacCacheTrackRecord] = []
    @State private var audioById: [String: URL] = [:]
    @State private var coverById: [String: URL] = [:]
    @State private var selected: Set<String> = []
    @State private var loaded = false
    @State private var offerStarted = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if !loaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if tracks.isEmpty {
                    Text(L("import.mac.no_songs"))
                        .font(YTLiteType.body)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        pairingColumn
                            .frame(minWidth: 320, idealWidth: 380, maxWidth: 440)
                            .frame(maxHeight: .infinity)
                        Divider()
                        offerColumn
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if showsCloseButton {
                    YTLiteSheetPrimaryButton(title: L("common.close")) {
                        server.stop()
                        dismiss()
                    }
                    .padding(.bottom, 28)
                }
            }
            .padding(.top, showsCloseButton ? 28 : YTLiteLayout.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ytLiteAppBackground()
            .navigationBarHidden(true)
            .interactiveDismissDisabled(true)
            .task { await reload() }
            .onDisappear { server.stop() }
        }
    }

    private var pairingColumn: some View {
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
                Text(connectionStatus)
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.accent)
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

    private var connectionStatus: String {
        switch server.connectedCount {
        case 0:
            return L("import.mac.waiting")
        case 1:
            return L("import.mac.connected_one")
        default:
            return Lf("import.mac.connected", Int64(server.connectedCount))
        }
    }

    private var offerColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Text(Lf("import.mac.cached_count", Int64(selected.count)))
                    .font(YTLiteType.sectionTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                Spacer(minLength: 8)
                Button(L("common.select_all")) {
                    let next = Set(tracks.map(\.videoId))
                    selected = next
                    publishOffer(next, restart: false)
                }
                .buttonStyle(.plain)
                .font(YTLiteType.labelEmphasized)
                .foregroundStyle(YTLiteColor.accent)
                .disabled(selected.count == tracks.count)
                Button(L("common.deselect_all")) {
                    selected = []
                    publishOffer([], restart: false)
                }
                .buttonStyle(.plain)
                .font(YTLiteType.labelEmphasized)
                .foregroundStyle(YTLiteColor.accent)
                .disabled(selected.isEmpty)
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(tracks) { track in
                        Button {
                            var next = selected
                            if next.contains(track.videoId) {
                                next.remove(track.videoId)
                            } else {
                                next.insert(track.videoId)
                            }
                            selected = next
                            publishOffer(next, restart: false)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: selected.contains(track.videoId) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(YTLiteColor.accent)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(track.title)
                                        .font(YTLiteType.rowTitle)
                                        .foregroundStyle(YTLiteColor.onSurface)
                                        .lineLimit(1)
                                    HStack(spacing: 8) {
                                        if !track.artist.isEmpty {
                                            Text(track.artist)
                                                .lineLimit(1)
                                        }
                                        if let duration = DurationFormat.text(seconds: track.durationSeconds) {
                                            Text(duration)
                                        }
                                    }
                                    .font(YTLiteType.meta)
                                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                    transferStatus(videoId: track.videoId)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, YTLiteLayout.screenPadding)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func transferStatus(videoId: String) -> some View {
        let sends = server.activeSends.filter { $0.videoId == videoId }
        if sends.count == 2 {
            Text(L("import.mac.concurrent_two"))
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.accent)
        } else if sends.count > 2 {
            Text(Lf("import.mac.concurrent", Int64(sends.count)))
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.accent)
        } else if let send = sends.first, send.totalBytes > 0 {
            ProgressView(
                value: min(Double(send.sentBytes), Double(send.totalBytes)),
                total: Double(send.totalBytes)
            )
            .tint(YTLiteColor.accent)
            Text("\(min(100, Int((Double(send.sentBytes) / Double(send.totalBytes) * 100).rounded())))%")
                .font(YTLiteType.meta)
                .monospacedDigit()
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
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
            let cover = await offerCover(videoId: snapshot.videoId, storedThumbnail: row?.thumbnailURLString)
            let hasCover = cover != nil
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
            if let cover { covers[snapshot.videoId] = cover }
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
            let cover = await offerCover(videoId: track.trackId, storedThumbnail: track.thumbnailURLString)
            let hasCover = cover != nil
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
            if let cover { covers[track.trackId] = cover }
        }
        tracks = records
        audioById = audio
        coverById = covers
        selected = Set(records.map(\.videoId))
        loaded = true
        publishOffer(selected, restart: true)
    }

    /// Local `cover.jpg` when it exists. Otherwise save the artwork the library already shows, including a remote thumbnail.
    private func offerCover(videoId: String, storedThumbnail: String?) async -> URL? {
        let cached = PlaybackCachedCover.fileURL(videoId: videoId)
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        let imported = ImportCoverStorage.fileURL(trackId: videoId)
        if FileManager.default.fileExists(atPath: imported.path) { return imported }
        return await PlaybackMediaStore.shared.ensureCover(
            videoId: videoId,
            thumbnailURL: Self.coverSourceURL(videoId: videoId, stored: storedThumbnail)
        )
    }

    private static func coverSourceURL(videoId: String, stored: String?) -> URL? {
        if let resolved = ImportCoverStorage.resolveURL(trackId: videoId, stored: stored) {
            if resolved.isFileURL {
                return URL(fileURLWithPath: resolved.path)
            }
            return resolved
        }
        guard let stored, stored.hasPrefix("http"), let url = URL(string: stored) else { return nil }
        return url
    }

    /// Publishes the checked songs. Restarting rebinds the port, so a checkbox change only replaces the offer.
    private func publishOffer(_ ids: Set<String>, restart: Bool) {
        let offered = tracks.filter { ids.contains($0.videoId) }
        var audio: [String: URL] = [:]
        var covers: [String: URL] = [:]
        for track in offered {
            if let file = audioById[track.videoId] { audio[track.videoId] = file }
            if let file = coverById[track.videoId] { covers[track.videoId] = file }
        }
        if tracks.isEmpty {
            offerStarted = false
            server.stop()
        } else if restart || !offerStarted {
            offerStarted = true
            server.start(tracks: offered, audio: audio, covers: covers)
        } else {
            server.replaceOffer(tracks: offered, audio: audio, covers: covers)
        }
    }
}
#endif

#if !targetEnvironment(macCatalyst)
struct MacCacheReceiveSheet: View {
    var onImported: () -> Void

    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.selectAppTab) private var selectAppTab
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var browser = MacCacheTransferBrowser()
    @State private var selectedDeviceID: String?
    @State private var address = Self.storedAddress()
    @State private var code = ""
    @FocusState private var focusedField: MacField?
    @State private var session: MacCacheTransferSession?
    @State private var tracks: [MacCacheTrackRecord] = []
    @State private var importedIDs: Set<String> = []
    @State private var selected: Set<String> = []
    @State private var message: String?
    @State private var toastMessage: String?
    @State private var showImportSummary = false
    @State private var importSummaryCount = 0
    @State private var isBusy = false
    @State private var progressText: String?
    @StateObject private var transfer = MacCacheImportProgress()
    @State private var importTask: Task<Void, Never>?
    @State private var presenceTask: Task<Void, Never>?
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        focusedField = nil
                        close()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            .frame(width: 28, height: 28)
                            .background(YTLiteColor.surfaceVariant, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .opacity(isBusy ? 0.4 : 1)
                    .accessibilityLabel(L("common.close"))
                }
                .padding(.top, 12)
                .padding(.trailing, YTLiteLayout.screenPadding)
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.immediately)
                .refreshable { await refreshCurrent() }
                if isBusy, !transfer.title.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
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
                        if let progressText {
                            Text(progressText)
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                    .padding(.top, 8)
                }
                if session == nil {
                    HStack {
                        Spacer(minLength: 0)
                        YTLiteChip(title: L("import.mac.scan"), selected: true) {
                            focusedField = nil
                            Task { await openScanner() }
                        }
                        .disabled(isBusy)
                        .opacity(isBusy ? 0.4 : 1)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                } else if !tracks.isEmpty {
                    HStack {
                        Spacer(minLength: 0)
                        YTLiteChip(title: L("import.mac.import_songs"), selected: true) {
                            focusedField = nil
                            importTask?.cancel()
                            importTask = Task { await importSelected() }
                        }
                        .disabled(isBusy || selected.isEmpty)
                        .opacity(isBusy || selected.isEmpty ? 0.4 : 1)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
            }
            .padding(.bottom, 16)
            .background(MacKeyboardDismissInstaller { focusedField = nil })
            .ytLiteAppBackground()
            .ytLiteToast($toastMessage, bottomPadding: 96)
            .alert(
                Lf("import.mac.imported_summary", Int64(importSummaryCount)),
                isPresented: $showImportSummary
            ) {
                Button(L("import.mac.view")) {
                    openOfflinePlaylist()
                }
                Button(L("common.close"), role: .cancel) {}
            }
            .navigationBarHidden(true)
            .interactiveDismissDisabled(isBusy)
            .onAppear { browser.start() }
            .onChange(of: address) { _, value in
                Self.storeAddress(value)
            }
            .onDisappear {
                importTask?.cancel()
                stopPresence(notify: true)
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
                .overlay(alignment: .topTrailing) {
                    Button {
                        showScanner = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("common.close"))
                    .padding(.top, 16)
                    .padding(.trailing, YTLiteLayout.screenPadding)
                }
            }
        }
    }

    private var browseBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("import.source.mac_receive.hint"))
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            HStack(spacing: 12) {
                Text(L("import.mac.nearby"))
                    .font(YTLiteType.sectionTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                Spacer(minLength: 8)
            }
            if browser.devices.isEmpty {
                Text(L("import.mac.no_devices"))
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            } else {
                ForEach(browser.devices) { device in
                    Button {
                        focusedField = nil
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let lastError = browser.lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(YTLiteType.meta)
                    .foregroundStyle(.red)
            }
            macField(
                L("import.mac.enter_address"),
                text: $address,
                keyboard: .numbersAndPunctuation,
                focus: .address
            )
            macField(
                L("import.mac.enter_code"),
                text: $code,
                keyboard: .numberPad,
                monospaced: true,
                focus: .code
            )
            HStack(spacing: 8) {
                YTLiteChip(title: L("import.mac.pair"), selected: canPair) {
                    focusedField = nil
                    Task { await pair() }
                }
                .disabled(!canPair)
                .opacity(canPair ? 1 : 0.4)
            }
        }
    }

    private var trackBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(Lf("import.mac.selected_count", selected.count, tracks.count))
                    .font(YTLiteType.sectionTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 16) {
                    Button(L("common.select_all")) {
                        selected = Set(tracks.map(\.videoId))
                    }
                    .buttonStyle(.plain)
                    .disabled(tracks.isEmpty || selected.count == tracks.count)
                    Button(L("common.deselect_all")) {
                        selected = []
                    }
                    .buttonStyle(.plain)
                    .disabled(selected.isEmpty)
                }
                .font(YTLiteType.labelEmphasized)
                .foregroundStyle(YTLiteColor.accent)
            }
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
                        HStack(spacing: 12) {
                            Image(systemName: selected.contains(track.videoId) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(YTLiteColor.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(YTLiteType.rowTitle)
                                    .foregroundStyle(YTLiteColor.onSurface)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    if !track.artist.isEmpty {
                                        Text(track.artist)
                                            .lineLimit(1)
                                    }
                                    if let duration = DurationFormat.text(seconds: track.durationSeconds) {
                                        Text(duration)
                                    }
                                    if importedIDs.contains(track.videoId) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(Color.green)
                                            .accessibilityLabel(L("toast.already_imported"))
                                    }
                                }
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
            }
        }
    }

    private enum MacField: Hashable {
        case address
        case code
    }

    private static let addressKey = "ytlite.mac-cache.last-address"

    private static func storedAddress() -> String {
        let raw = UserDefaults.standard.string(forKey: addressKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return isIPv4(raw) ? raw : ""
    }

    private static func storeAddress(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isIPv4(trimmed) else { return }
        UserDefaults.standard.set(trimmed, forKey: addressKey)
    }

    private func macField(
        _ placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        monospaced: Bool = false,
        focus: MacField
    ) -> some View {
        TextField(
            "",
            text: text,
            prompt: Text(placeholder).foregroundStyle(YTLiteColor.onSurfaceVariant)
        )
        .focused($focusedField, equals: focus)
        .font(monospaced ? YTLiteType.body.monospacedDigit() : YTLiteType.body)
        .foregroundStyle(YTLiteColor.onSurface)
        .keyboardType(keyboard)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(YTLiteColor.surfaceVariant, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var canPair: Bool {
        !isBusy && pairEndpoint != nil && code.trimmingCharacters(in: .whitespaces).count >= 4
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

    private func refreshCurrent() async {
        guard !isBusy else { return }
        if session == nil {
            browser.start()
            try? await Task.sleep(nanoseconds: 700_000_000)
            return
        }
        guard let session else { return }
        // Pull-to-refresh is cancelled when this view updates. Fetch on a separate task so the new list still lands.
        let worker = Task { @MainActor in
            await self.loadOffer(session)
        }
        await worker.value
    }

    /// Reloads the Mac's current offer. Songs the user already unchecked stay unchecked.
    private func loadOffer(_ session: MacCacheTransferSession) async {
        do {
            let listed = try await session.tracks()
            let previousIDs = Set(tracks.map(\.videoId))
            let listedIDs = Set(listed.map(\.videoId))
            let added = listedIDs.subtracting(previousIDs)
            self.selected = self.selected.intersection(listedIDs).union(added)
            self.tracks = listed
            self.message = nil
            refreshImportedMarks()
        } catch is CancellationError {
            return
        } catch MacCacheTransferError.unauthorized {
            message = L("import.mac.pair_failed")
        } catch {
            message = error.localizedDescription
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
            refreshImportedMarks()
            browser.stop()
            startPresence(paired)
        } catch is CancellationError {
            return
        } catch MacCacheTransferError.unauthorized {
            message = L("import.mac.pair_failed")
        } catch {
            message = L("import.mac.same_wifi")
        }
    }

    private func importSelected() async {
        guard let session, let store else { return }
        let chosen = tracks.filter { selected.contains($0.videoId) }
        guard !chosen.isEmpty else { return }
        let pending = chosen.filter { track in
            store.importedTrack(remoteURI: "mac-cache:\(track.videoId)") == nil
        }
        let already = chosen.filter { track in
            store.importedTrack(remoteURI: "mac-cache:\(track.videoId)") != nil
        }
        if !already.isEmpty {
            await repairExistingCovers(already, session: session, store: store)
        }
        guard !pending.isEmpty else {
            toastMessage = L("toast.already_imported")
            return
        }
        isBusy = true
        message = nil
        defer { isBusy = false }
        var done = 0
        var failed = 0
        var importedCount = 0
        for track in pending {
            if Task.isCancelled { break }
            done += 1
            progressText = Lf("import.mac.progress", Int64(done), Int64(pending.count))
            transfer.begin(title: track.title)
            let uri = "mac-cache:\(track.videoId)"
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
                await attachTransferredCover(
                    videoId: track.videoId,
                    trackId: result.trackId,
                    session: session,
                    store: store
                )
                try? FileManager.default.removeItem(at: audioURL)
                importedCount += 1
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
        refreshImportedMarks()
        if importedCount > 0 {
            importSummaryCount = importedCount
            showImportSummary = true
        }
    }

    /// Songs already stored on this phone, matched by the Mac cache URI.
    private func refreshImportedMarks() {
        guard let store else {
            importedIDs = []
            return
        }
        importedIDs = Set(tracks.compactMap { track in
            store.importedTrack(remoteURI: "mac-cache:\(track.videoId)") == nil ? nil : track.videoId
        })
    }

    /// Fills a cover for a song that is already on the phone but never received artwork.
    private func repairExistingCovers(
        _ tracks: [MacCacheTrackRecord],
        session: MacCacheTransferSession,
        store: LibraryStore
    ) async {
        for track in tracks {
            if Task.isCancelled { return }
            guard let row = store.importedTrack(remoteURI: "mac-cache:\(track.videoId)") else { continue }
            await attachTransferredCover(
                videoId: track.videoId,
                trackId: row.trackId,
                session: session,
                store: store
            )
        }
    }

    private func attachTransferredCover(
        videoId: String,
        trackId: String,
        session: MacCacheTransferSession,
        store: LibraryStore
    ) async {
        guard ImportIngestService.shared.coverNeedsReplacement(trackId: trackId) else { return }
        let coverURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        defer { try? FileManager.default.removeItem(at: coverURL) }
        if (try? await session.download(videoId: videoId, kind: "cover", to: coverURL)) != nil,
           let data = try? Data(contentsOf: coverURL),
           !data.isEmpty,
           UIImage(data: data) != nil,
           !ImportIngestService.jpegDataIsNearlyBlank(data) {
            try? ImportIngestService.shared.attachCover(
                trackId: trackId,
                jpeg: data,
                store: store,
                overwrite: true
            )
        }
        await ImportIngestService.shared.fillCoverIfBlank(trackId: trackId, store: store)
    }

    private func openOfflinePlaylist() {
        appModel.pendingOfflinePlaylist = true
        selectAppTab?(.library)
        close()
    }

    private func close() {
        importTask?.cancel()
        stopPresence(notify: true)
        browser.stop()
        dismiss()
    }

    /// While the receive sheet stays open, tell the Mac this phone is still here.
    private func startPresence(_ session: MacCacheTransferSession) {
        presenceTask?.cancel()
        presenceTask = Task {
            while !Task.isCancelled {
                await session.ping()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func stopPresence(notify: Bool) {
        presenceTask?.cancel()
        presenceTask = nil
        guard notify, let session else { return }
        Task { await session.leave() }
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

/// Taps outside a text field dismiss the keyboard without taking the tap away from buttons.
private struct MacKeyboardDismissInstaller: UIViewRepresentable {
    var onDismiss: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onDismiss = onDismiss
        DispatchQueue.main.async {
            context.coordinator.install(on: uiView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onDismiss: () -> Void = {}
        private weak var host: UIView?
        private var tap: UITapGestureRecognizer?

        func install(on marker: UIView) {
            let host = sheetHost(from: marker)
            guard self.host !== host else { return }
            remove()
            let tap = UITapGestureRecognizer(target: self, action: #selector(dismiss))
            tap.name = "mixtube.dismiss-keyboard"
            tap.cancelsTouchesInView = false
            tap.delegate = self
            host.addGestureRecognizer(tap)
            self.host = host
            self.tap = tap
        }

        /// The sheet controller's view sits above both the fields and the empty area, so one recognizer sees every tap.
        private func sheetHost(from marker: UIView) -> UIView {
            var responder: UIResponder? = marker
            while let current = responder {
                if let controller = current as? UIViewController {
                    return controller.view
                }
                responder = current.next
            }
            return marker.superview ?? marker
        }

        func remove() {
            if let tap, let host {
                host.removeGestureRecognizer(tap)
            }
            tap = nil
            host = nil
        }

        @objc private func dismiss() {
            onDismiss()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
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
