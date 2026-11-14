import SwiftUI

private enum ImportedListFilter: Hashable {
    case all
    case source(ImportSourceKind)

    var title: String {
        switch self {
        case .all: return L("import.list.filter.all")
        case .source(let kind): return L(kind.displayKey)
        }
    }

    /// Matches Import Hub source order (Files → Wi‑Fi → WebDAV → iCloud → Drive → Baidu).
    static let chipOrder: [ImportedListFilter] = [
        .all,
        .source(.local),
        .source(.wifi),
        .source(.webdav),
        .source(.icloud),
        .source(.gdrive),
        .source(.baidu),
    ]
}

/// Imported tracks list pushed from Import hub header / toolbar.
struct ImportedTracksListView: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var playerPresentation: PlayerPresentation
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.libraryStore) private var store

    @State private var entries: [ImportedDisplayEntry] = []
    @State private var filter: ImportedListFilter = .all

    private var filteredEntries: [ImportedDisplayEntry] {
        switch filter {
        case .all:
            return entries
        case .source(let kind):
            return entries.filter { $0.sourceKind == kind }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Same chrome stack as Library: page title → chips → N items.
            VStack(alignment: .leading, spacing: YTLiteLayout.screenPadding) {
                header
                filterChips
                listControls
            }
            .padding(.bottom, YTLiteLayout.stackTight)

            listBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ytLiteAppBackground()
        .ytLiteMiniPlayerScrollInset()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(YTLiteColor.background, for: .navigationBar)
        .onAppear {
            reload()
            Task { await backfillCoversIfNeeded() }
        }
        .onChange(of: trackActions.listEpoch) { _, _ in reload() }
    }

    private var header: some View {
        Text(L("import.list.title"))
            .font(YTLiteType.pageTitle)
            .foregroundStyle(YTLiteColor.onSurface)
            .padding(.horizontal, YTLiteLayout.screenPadding)
            .padding(.top, YTLiteLayout.rowVertical)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: YTLiteLayout.stackDefault) {
                ForEach(ImportedListFilter.chipOrder, id: \.self) { item in
                    YTLiteChip(title: item.title, selected: filter == item) {
                        filter = item
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var listControls: some View {
        HStack {
            Text(Lf("common.n_items", filteredEntries.count))
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 36, alignment: .center)
        .padding(.horizontal, YTLiteLayout.screenPadding)
    }

    @ViewBuilder
    private var listBody: some View {
        if entries.isEmpty {
            emptyState(L("import.hub.empty"))
        } else if filteredEntries.isEmpty {
            emptyState(L("import.list.empty_filter"))
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                        importedRow(entry, index: index)
                    }
                }
                .padding(.bottom, 80)
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(YTLiteType.body)
            .foregroundStyle(YTLiteColor.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)
    }

    private func importedRow(_ entry: ImportedDisplayEntry, index: Int) -> some View {
        HStack(spacing: 0) {
            Button {
                play(at: index)
            } label: {
                HStack(spacing: 14) {
                    Group {
                        if entry.item.thumbnailURL != nil {
                            RemoteImage(url: entry.item.thumbnailURL, contentMode: .fill)
                        } else {
                            ZStack {
                                YTLiteColor.surfaceVariant
                                Image(systemName: "music.note")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(YTLiteColor.accent)
                            }
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: YTLiteLayout.thumbRadius))
                    .id("import-list-thumb-\(entry.id)-\(entry.item.thumbnailURL?.absoluteString ?? "")")

                    VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                        Text(entry.item.title)
                            .font(YTLiteType.rowTitle)
                            .foregroundStyle(YTLiteColor.onSurface)
                            .lineLimit(1)
                        Text(entry.subtitleLine)
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, YTLiteLayout.screenPadding)
                .padding(.vertical, YTLiteLayout.rowVertical)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                trackActions.present(item: entry.item, canDeleteFromLibrary: true)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, YTLiteLayout.screenPadding - 8)
        }
    }

    private func play(at index: Int) {
        let items = filteredEntries.map(\.item)
        playback.play(items: items, startAt: index, analyticsSource: "import")
        playerPresentation.present()
    }

    private func reload() {
        entries = ImportedDisplayEntry.loadAll(from: store)
    }

    private func backfillCoversIfNeeded() async {
        guard let store else { return }
        let updated = await ImportIngestService.shared.backfillMissingCovers(store: store)
        guard updated > 0 else { return }
        reload()
        trackActions.notifyListsChanged()
    }
}

struct ImportedDisplayEntry: Identifiable, Equatable {
    let id: String
    let item: VideoItem
    let sourceKind: ImportSourceKind
    let fileSizeText: String

    var subtitleLine: String {
        "\(fileSizeText) · \(L(sourceKind.displayKey))"
    }

    @MainActor
    static func loadAll(from store: LibraryStore?) -> [ImportedDisplayEntry] {
        guard let store else { return [] }
        let metaById = Dictionary(
            uniqueKeysWithValues: store.allMetadata().map { ($0.trackId, $0) }
        )
        return store.importedTracks().map { track in
            let item = store.displayItem(for: track.asVideoItem, metaById: metaById)
            let kind = ImportSourceKind(rawValue: track.sourceKind) ?? .local
            let bytes = byteCount(trackId: track.trackId, relativePath: track.localRelativePath)
            return ImportedDisplayEntry(
                id: track.trackId,
                item: item,
                sourceKind: kind,
                fileSizeText: formatFileSize(bytes)
            )
        }
    }

    @MainActor
    private static func byteCount(trackId: String, relativePath: String?) -> Int64? {
        guard let url = LocalMediaStore.shared.audioURL(trackId: trackId, relativePath: relativePath),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        else { return nil }
        return Int64(size)
    }

    private static func formatFileSize(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return L("import.hub.size_unknown") }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
