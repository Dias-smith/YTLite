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

    /// Matches Import Hub source order (Files → Wi‑Fi → WebDAV → iCloud → Drive).
    /// Baidu chip temporarily hidden (parity with Import hub).
    static let chipOrder: [ImportedListFilter] = [
        .all,
        .source(.local),
        .source(.wifi),
        .source(.webdav),
        .source(.icloud),
        .source(.gdrive),
    ]
}

/// Imported tracks list pushed from Import hub / Library system playlist.
struct ImportedTracksListView: View {
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var playerPresentation: PlayerPresentation
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.libraryStore) private var store
    @EnvironmentObject private var appModel: AppModel

    @State private var entries: [ImportedDisplayEntry] = []
    @State private var filter: ImportedListFilter = .all
    @State private var isSelectionMode = false
    @State private var selectedIds: Set<String> = []
    @State private var showBatchPlaylistPicker = false
    @State private var showDeleteConfirm = false

    private var filteredEntries: [ImportedDisplayEntry] {
        switch filter {
        case .all:
            return entries
        case .source(let kind):
            return entries.filter { $0.sourceKind == kind }
        }
    }

    private var batchTargetPlaylists: [LibraryPlaylist] {
        (store?.allPlaylists() ?? []).filter {
            $0.systemType == nil
                || $0.systemType == SystemPlaylistType.favorites
        }
    }

    var body: some View {
        // Mirror Library scroll chrome: title → chips → N items → rows in one vertical stack
        // so the horizontal chip ScrollView sizes to content (no overlap / no giant gap).
        ScrollView {
            LazyVStack(alignment: .leading, spacing: YTLiteLayout.screenPadding) {
                if isSelectionMode {
                    selectionHeader
                } else {
                    header
                    filterChips
                    listControls
                }
                listBody
            }
            .padding(.bottom, 80)
        }
        .ytLiteAppBackground()
        .ytLiteMiniPlayerScrollInset()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(YTLiteColor.background, for: .navigationBar)
        .onAppear {
            reload()
            Task { await store?.refreshOfflinePlaylistFromCache() }
            Task { await backfillCoversIfNeeded() }
        }
        .onChange(of: trackActions.listEpoch) { _, _ in reload() }
        .onChange(of: appModel.libraryRevision) { _, _ in reload() }
        .onChange(of: filter) { _, _ in
            selectedIds = selectedIds.intersection(Set(filteredEntries.map(\.id)))
        }
        .sheet(isPresented: $showBatchPlaylistPicker) {
            LibraryPlaylistPickSheet(
                playlists: batchTargetPlaylists,
                title: L("library.add_to_playlist"),
                displayName: playlistDisplayName,
                onSelect: { playlist in
                    addSelectedToPlaylist(playlist)
                    showBatchPlaylistPicker = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(YTLiteColor.surfaceElevated)
        }
        .sheet(isPresented: $showDeleteConfirm) {
            VStack(spacing: 0) {
                YTLiteSheetGrabHandle()
                YTLiteSheetTitle(title: L("common.delete"))
                Text(Lf("import.list.remove_n", selectedIds.count))
                    .font(YTLiteType.body)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                Spacer(minLength: 20)
                VStack(spacing: 10) {
                    YTLiteSheetPrimaryButton(title: L("common.delete"), destructive: true) {
                        deleteSelected()
                        showDeleteConfirm = false
                    }
                    YTLiteSheetSecondaryButton(title: L("common.cancel")) {
                        showDeleteConfirm = false
                    }
                }
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(YTLiteColor.surfaceElevated)
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(YTLiteColor.surfaceElevated)
        }
    }

    private var header: some View {
        Text(L("import.list.title"))
            .font(YTLiteType.pageTitle)
            .foregroundStyle(YTLiteColor.onSurface)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
        }
    }

    private var listControls: some View {
        HStack {
            Text(Lf("common.n_items", filteredEntries.count))
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            Spacer(minLength: 0)
            if !entries.isEmpty {
                Button {
                    enterSelectionMode()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
    }

    private var selectionHeader: some View {
        HStack(spacing: YTLiteLayout.stackLoose) {
            Button {
                exitSelectionMode()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(YTLiteColor.onSurface)
                    .frame(width: 36, height: 36)
            }
            Text(Lf("common.n_selected", selectedIds.count))
                .font(YTLiteType.sectionTitle)
                .foregroundStyle(YTLiteColor.onSurface)
            Spacer()
            Button {
                selectedIds = Set(filteredEntries.map(\.id))
            } label: {
                Image(systemName: "checklist")
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(width: 36, height: 36)
            }
            Button {
                selectedIds.removeAll()
            } label: {
                Image(systemName: "checklist.unchecked")
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(width: 36, height: 36)
            }
            .disabled(selectedIds.isEmpty)
            if !selectedIds.isEmpty {
                Button {
                    showBatchPlaylistPicker = true
                } label: {
                    Image(systemName: "text.badge.plus")
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(L("library.add_to_playlist"))
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .frame(width: 36, height: 36)
                }
            }
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.top, YTLiteLayout.rowVertical)
    }

    @ViewBuilder
    private var listBody: some View {
        if entries.isEmpty {
            emptyState(L("import.hub.empty"))
        } else if filteredEntries.isEmpty {
            emptyState(L("import.list.empty_filter"))
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                    importedRow(entry, index: index)
                }
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(YTLiteType.body)
            .foregroundStyle(YTLiteColor.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 48)
    }

    private func importedRow(_ entry: ImportedDisplayEntry, index: Int) -> some View {
        let selected = selectedIds.contains(entry.id)
        return HStack(spacing: 0) {
            Button {
                if isSelectionMode {
                    toggleSelection(entry.id)
                } else {
                    play(at: index)
                }
            } label: {
                HStack(spacing: 14) {
                    if isSelectionMode {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? YTLiteColor.accent : YTLiteColor.onSurfaceVariant)
                    }
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

            if !isSelectionMode {
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
            } else {
                Color.clear
                    .frame(width: YTLiteLayout.screenPadding)
            }
        }
    }

    private func play(at index: Int) {
        let items = filteredEntries.map(\.item)
        playback.play(items: items, startAt: index, analyticsSource: "import")
        playerPresentation.present()
    }

    private func enterSelectionMode() {
        selectedIds = []
        isSelectionMode = true
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedIds = []
    }

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func playlistDisplayName(_ playlist: LibraryPlaylist) -> String {
        switch playlist.systemType {
        case SystemPlaylistType.favorites: return L("library.liked")
        case SystemPlaylistType.watchLater: return L("library.watch_later")
        default: return playlist.name
        }
    }

    private func addSelectedToPlaylist(_ playlist: LibraryPlaylist) {
        guard let store else { return }
        for id in selectedIds {
            if let item = entries.first(where: { $0.id == id })?.item {
                store.add(item: item, to: playlist)
            }
        }
        exitSelectionMode()
        trackActions.notifyListsChanged()
    }

    private func deleteSelected() {
        guard let store else { return }
        for id in selectedIds {
            store.removeFromOfflinePlaylist(trackId: id)
        }
        exitSelectionMode()
        reload()
        trackActions.notifyListsChanged()
    }

    private func reload() {
        entries = ImportedDisplayEntry.loadAll(from: store)
        selectedIds = selectedIds.intersection(Set(entries.map(\.id)))
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
        // Offline YouTube caches: size only — no "YouTube" source label.
        if sourceKind == .youtube {
            return fileSizeText
        }
        return "\(fileSizeText) · \(L(sourceKind.displayKey))"
    }

    @MainActor
    static func loadAll(from store: LibraryStore?) -> [ImportedDisplayEntry] {
        guard let store else { return [] }
        let metaById = Dictionary(
            uniqueKeysWithValues: store.allMetadata().map { ($0.trackId, $0) }
        )
        return store.offlinePlaylistTracks().map { track in
            let item = store.displayItem(for: track.asVideoItem, metaById: metaById)
            let kind = ImportSourceKind(rawValue: track.sourceKind) ?? .local
            let bytes = byteCount(trackId: track.trackId, relativePath: track.localRelativePath)
                ?? store.offlineCachedByteCount(trackId: track.trackId)
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
