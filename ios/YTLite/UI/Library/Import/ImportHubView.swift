import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImportHubView: View {
    @EnvironmentObject private var trackActions: TrackActionPresenter
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

    var body: some View {
        List {
            Section {
                sourceButton(title: L("import.source.local"), systemImage: "folder") {
                    showFileImporter = true
                }
                sourceButton(title: L("import.source.photos"), systemImage: "photo.on.rectangle") {
                    showPhotosPicker = true
                }
                sourceButton(title: L("import.source.wifi"), systemImage: "wifi") {
                    showWiFi = true
                }
                sourceButton(title: L("import.source.webdav"), systemImage: "externaldrive.connected.to.line.below") {
                    showWebDAV = true
                }
                sourceButton(title: L("import.source.icloud"), systemImage: "icloud") {
                    showFileImporter = true
                }
                sourceButton(title: L("import.source.gdrive"), systemImage: "globe") {
                    showGoogleDrive = true
                }
                sourceButton(title: L("import.source.baidu"), systemImage: "cloud") {
                    showBaidu = true
                }
            } header: {
                Text(L("import.hub.sources"))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .ytLiteAppBackground()
        .navigationTitle(L("import.hub.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ImportedTracksListView()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note.list")
                        Text("\(importedCount)")
                            .font(YTLiteType.labelEmphasized)
                            .monospacedDigit()
                    }
                    .foregroundStyle(YTLiteColor.accent)
                    .accessibilityLabel(Lf("import.hub.count", importedCount))
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
                    .background(YTLiteColor.surface)
            }
        }
        .onAppear { reloadCount() }
        .onChange(of: trackActions.listEpoch) { _, _ in reloadCount() }
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
        .sheet(isPresented: $showWebDAV) {
            WebDAVBrowserSheet {
                reloadCount()
                trackActions.notifyListsChanged()
            }
        }
        .sheet(isPresented: $showGoogleDrive) {
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

    private func sourceButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(YTLiteColor.onSurface)
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
        guard let store else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let urls = try result.get()
            var imported = 0
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                guard ImportIngestService.isSupportedAudioURL(url) else { continue }
                let kind: ImportSourceKind = url.path.contains("Mobile Documents") ? .icloud : .local
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
        guard let store else { return }
        isBusy = true
        defer {
            isBusy = false
            photoItems = []
        }
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
