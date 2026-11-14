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

/// Full list of on-device imported tracks (opened from Import Hub toolbar).
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
            filterChips
            listBody
        }
        .ytLiteAppBackground()
        .navigationTitle(L("import.list.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .onChange(of: trackActions.listEpoch) { _, _ in reload() }
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
            .padding(.vertical, YTLiteLayout.rowVertical)
        }
    }

    @ViewBuilder
    private var listBody: some View {
        if entries.isEmpty {
            Text(L("import.hub.empty"))
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredEntries.isEmpty {
            Text(L("import.list.empty_filter"))
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                        importedRow(entry, index: index)
                    }
                }
                .ytLiteMiniPlayerScrollInset()
            }
        }
    }

    private func importedRow(_ entry: ImportedDisplayEntry, index: Int) -> some View {
        Button {
            play(at: index)
        } label: {
            HStack(spacing: YTLiteLayout.stackLoose) {
                Group {
                    if entry.item.thumbnailURL != nil {
                        RemoteImage(url: entry.item.thumbnailURL, maxPointSize: 96)
                    } else {
                        Image(systemName: "music.note")
                            .foregroundStyle(YTLiteColor.accent)
                    }
                }
                .frame(width: YTLiteLayout.channelAvatar, height: YTLiteLayout.channelAvatar)
                .background(YTLiteColor.surfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: 6))
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
                Button {
                    trackActions.present(item: entry.item, canDeleteFromLibrary: true)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
            .padding(.vertical, YTLiteLayout.rowVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func play(at index: Int) {
        let items = filteredEntries.map(\.item)
        playback.play(items: items, startAt: index, analyticsSource: "import")
        playerPresentation.present()
    }

    private func reload() {
        entries = ImportedDisplayEntry.loadAll(from: store)
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
