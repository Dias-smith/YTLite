import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private enum ImportHubSource: Identifiable {
    case local
    case photos
    case wifi
    case webdav
    case icloud
    case gdrive
    case baidu

    var id: String {
        switch self {
        case .local: return "local"
        case .photos: return "photos"
        case .wifi: return "wifi"
        case .webdav: return "webdav"
        case .icloud: return "icloud"
        case .gdrive: return "gdrive"
        case .baidu: return "baidu"
        }
    }

    var title: String {
        switch self {
        case .local: return L("import.source.local")
        case .photos: return L("import.source.photos")
        case .wifi: return L("import.source.wifi")
        case .webdav: return L("import.source.webdav")
        case .icloud: return L("import.source.icloud")
        case .gdrive: return L("import.source.gdrive")
        case .baidu: return L("import.source.baidu")
        }
    }

    var subtitle: String {
        switch self {
        case .local: return L("import.source.local.hint")
        case .photos: return L("import.source.photos.hint")
        case .wifi: return L("import.source.wifi.hint")
        case .webdav: return L("import.source.webdav.hint")
        case .icloud: return L("import.source.icloud.hint")
        case .gdrive: return L("import.source.gdrive.hint")
        case .baidu: return L("import.source.baidu.hint")
        }
    }

    var systemImage: String {
        switch self {
        case .local: return "folder"
        case .photos: return "photo.on.rectangle"
        case .wifi: return "wifi"
        case .webdav: return "externaldrive.connected.to.line.below"
        case .icloud: return "icloud"
        case .gdrive: return "globe"
        case .baidu: return "cloud"
        }
    }

    static let all: [ImportHubSource] = [
        // Baidu temporarily hidden — keep `.baidu` case / sheet for easy restore.
        .local, .photos, .wifi, .webdav, .icloud, .gdrive,
    ]
}

struct ImportHubView: View {
    /// Tab root uses Library-style page title + hidden nav bar; Settings push keeps system back.
    var isTabRoot: Bool = false

    @EnvironmentObject private var trackActions: TrackActionPresenter
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.libraryStore) private var store

    @State private var importedCount: Int = 0
    @State private var showFileImporter = false
    @State private var showPhotosPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isBusy = false
    @State private var statusMessage: String?
    @State private var showWiFi = false
    @State private var showWebDAV = false
    @State private var showGoogleDrive = false
    @State private var showBaidu = false
    @State private var preferICloudPicker = false
    /// Photos/Files steal AVAudioSession; restore after dismiss/import if we were playing.
    @State private var resumePlaybackAfterPicker = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: YTLiteLayout.screenPadding) {
                if isTabRoot {
                    header
                }
                listControls
            }
            .padding(.bottom, YTLiteLayout.stackTight)

            sourcesBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ytLiteMiniPlayerScrollInset()
        .ytLiteAppBackground()
        .toolbar(isTabRoot ? .hidden : .automatic, for: .navigationBar)
        .navigationTitle(isTabRoot ? "" : L("import.hub.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(YTLiteColor.background, for: .navigationBar)
        .toolbar {
            if !isTabRoot {
                ToolbarItem(placement: .topBarTrailing) {
                    importedEntryLink
                }
            }
        }
        .overlay {
            if isBusy {
                ProgressView()
                    .padding(20)
                    .background(YTLiteColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let statusMessage {
                Text(statusMessage)
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(YTLiteColor.surface.opacity(0.92))
            }
        }
        .onAppear {
            reloadCount()
            Task {
                guard let store else { return }
                let updated = await ImportIngestService.shared.backfillMissingCovers(store: store)
                if updated > 0 {
                    reloadCount()
                    trackActions.notifyListsChanged()
                }
            }
        }
        .onChange(of: trackActions.listEpoch) { _, _ in reloadCount() }
        .onChange(of: showPhotosPicker) { _, presented in
            if presented {
                resumePlaybackAfterPicker = playback.isPlaying
            } else if resumePlaybackAfterPicker, photoItems.isEmpty {
                finishPickerPlaybackResume()
            }
        }
        .onChange(of: showFileImporter) { _, presented in
            if presented {
                resumePlaybackAfterPicker = playback.isPlaying
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.allowedTypes,
            allowsMultipleSelection: true
        ) { result in
            Task { await handleFileImporter(result) }
        }
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $photoItems,
            matching: .videos
        )
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await handlePhotos(items) }
        }
        .fullScreenCover(isPresented: $showWiFi) {
            WiFiImportSheet {
                reloadCount()
                trackActions.notifyListsChanged()
            }
        }
        .fullScreenCover(isPresented: $showWebDAV) {
            WebDAVBrowserSheet {
                reloadCount()
                trackActions.notifyListsChanged()
            }
        }
        .fullScreenCover(isPresented: $showGoogleDrive) {
            GoogleDriveImportSheet {
                reloadCount()
                trackActions.notifyListsChanged()
            }
        }
        .sheet(isPresented: $showBaidu) {
            BaiduPanImportSheet {
                reloadCount()
                trackActions.notifyListsChanged()
            }
        }
    }

    // MARK: - Library-style chrome

    private var header: some View {
        HStack(alignment: .center, spacing: YTLiteLayout.stackLoose) {
            Text(L("import.hub.title"))
                .font(YTLiteType.pageTitle)
                .foregroundStyle(YTLiteColor.onSurface)
            Spacer(minLength: 0)
            importedEntryLink
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            }
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.top, YTLiteLayout.rowVertical)
    }

    private var importedEntryLink: some View {
        NavigationLink {
            ImportedTracksListView(scope: .importedOnly)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(importedCount)")
                    .font(YTLiteType.labelEmphasized)
                    .monospacedDigit()
            }
            .foregroundStyle(YTLiteColor.accent)
            .padding(.horizontal, YTLiteLayout.chipHorizontal)
            .padding(.vertical, YTLiteLayout.chipVertical)
            .background(YTLiteColor.surfaceChip, in: Capsule())
            .contentShape(Capsule())
            .accessibilityLabel(Lf("import.hub.count", importedCount))
        }
    }

    private var listControls: some View {
        HStack {
            Text(Lf("common.n_items", ImportHubSource.all.count))
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            Spacer()
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
    }

    private var sourcesBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(ImportHubSource.all) { source in
                    sourceRow(source)
                }
            }
            .padding(.bottom, 80)
        }
    }

    private func sourceRow(_ source: ImportHubSource) -> some View {
        Button {
            activate(source)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    YTLiteColor.surfaceVariant
                    Image(systemName: source.systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(YTLiteColor.accent)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: YTLiteLayout.thumbRadius))

                VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                    Text(source.title)
                        .font(YTLiteType.rowTitle)
                        .foregroundStyle(YTLiteColor.onSurface)
                        .lineLimit(1)
                    Text(source.subtitle)
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
            .padding(.vertical, YTLiteLayout.rowVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func activate(_ source: ImportHubSource) {
        switch source {
        case .local:
            preferICloudPicker = false
            resumePlaybackAfterPicker = playback.isPlaying
            showFileImporter = true
        case .photos:
            resumePlaybackAfterPicker = playback.isPlaying
            showPhotosPicker = true
        case .wifi:
            showWiFi = true
        case .webdav:
            showWebDAV = true
        case .icloud:
            preferICloudPicker = true
            resumePlaybackAfterPicker = playback.isPlaying
            showFileImporter = true
        case .gdrive:
            showGoogleDrive = true
        case .baidu:
            showBaidu = true
        }
    }

    private func finishPickerPlaybackResume() {
        let shouldResume = resumePlaybackAfterPicker
        resumePlaybackAfterPicker = false
        guard shouldResume else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            playback.resumeAfterSystemPickerIfNeeded(wasPlaying: true)
        }
    }

    private func reloadCount() {
        importedCount = store?.importedTracks().count ?? 0
    }

    private static var allowedTypes: [UTType] {
        var types: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        if let flac = UTType(filenameExtension: "flac") { types.append(flac) }
        types.append(contentsOf: [.mpeg4Movie, .quickTimeMovie, .movie])
        return types
    }

    private func handleFileImporter(_ result: Result<[URL], Error>) async {
        defer { finishPickerPlaybackResume() }
        guard let store else { return }
        isBusy = true
        defer {
            isBusy = false
            preferICloudPicker = false
        }
        do {
            let urls = try result.get()
            var imported = 0
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                guard ImportIngestService.isSupportedAudioURL(url) else { continue }
                let kind: ImportSourceKind =
                    preferICloudPicker || url.path.contains("Mobile Documents") ? .icloud : .local
                _ = try await ImportIngestService.shared.ingestFileURL(
                    url,
                    sourceKind: kind,
                    store: store,
                    cacheEligible: false
                )
                imported += 1
            }
            statusMessage = Lf("import.status.imported_n", imported)
            reloadCount()
            trackActions.notifyListsChanged()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func handlePhotos(_ items: [PhotosPickerItem]) async {
        defer {
            photoItems = []
            finishPickerPlaybackResume()
        }
        guard let store else { return }
        isBusy = true
        defer { isBusy = false }
        var imported = 0
        for item in items {
            do {
                if let movie = try await item.loadTransferable(type: ImportMovieTransferable.self) {
                    _ = try await ImportIngestService.shared.ingestFileURL(
                        movie.url,
                        sourceKind: .local,
                        store: store,
                        titleHint: movie.url.deletingPathExtension().lastPathComponent,
                        cacheEligible: false
                    )
                    imported += 1
                    try? FileManager.default.removeItem(at: movie.url)
                } else if let data = try await item.loadTransferable(type: Data.self) {
                    _ = try await ImportIngestService.shared.ingestData(
                        data,
                        fileExtension: "m4a",
                        fileName: "photo-audio.m4a",
                        sourceKind: .local,
                        store: store
                    )
                    imported += 1
                }
            } catch {
                statusMessage = error.localizedDescription
            }
        }
        if imported > 0 {
            statusMessage = Lf("import.status.imported_n", imported)
            reloadCount()
            trackActions.notifyListsChanged()
        }
    }
}

private struct ImportMovieTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: temp)
            return ImportMovieTransferable(url: temp)
        }
    }
}
