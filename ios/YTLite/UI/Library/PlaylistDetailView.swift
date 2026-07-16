import SwiftUI
import PhotosUI
import UIKit

/// Playlist detail — mirrors Android `PlaylistDetailScreen`.
struct PlaylistDetailView: View {
    let playlist: LibraryPlaylist
    var onChange: () -> Void

    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @EnvironmentObject private var playlistActions: PlaylistActionPresenter
    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var sort: PlaylistTrackSort = .manual
    @State private var showSortSheet = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var refreshTick = 0
    @State private var orderedTrackIds: [String] = []

    private var livePlaylist: LibraryPlaylist {
        store?.playlist(id: playlist.playlistId) ?? playlist
    }

    private var canEdit: Bool { livePlaylist.systemType == nil }
    private var canRemoveTracks: Bool { livePlaylist.systemType == nil }
    private var canReorder: Bool { sort == .manual }

    private var entryRows: [PlaylistDetailTrack] {
        _ = refreshTick
        return livePlaylist.entries.compactMap { entry in
            guard let track = entry.track else { return nil }
            let item = store?.displayItem(for: track.asVideoItem) ?? track.asVideoItem
            return PlaylistDetailTrack(
                trackId: track.trackId,
                item: item,
                position: entry.position,
                addedAt: entry.createdAt
            )
        }
    }

    private var displayedTracks: [PlaylistDetailTrack] {
        let rows = entryRows
        switch sort {
        case .manual:
            if orderedTrackIds.isEmpty {
                return rows.sorted { $0.position < $1.position }
            }
            let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.trackId, $0) })
            let ordered = orderedTrackIds.compactMap { byId[$0] }
            let missing = rows.filter { !orderedTrackIds.contains($0.trackId) }
                .sorted { $0.position < $1.position }
            return ordered + missing
        case .recentlyAdded:
            return rows.sorted { $0.addedAt > $1.addedAt }
        case .title:
            return rows.sorted {
                $0.item.title.localizedCaseInsensitiveCompare($1.item.title) == .orderedAscending
            }
        }
    }

    private var coverURLs: [URL] {
        if let url = PlaylistCoverStorage.resolveURL(livePlaylist.coverUrlOrPath) {
            return [url]
        }
        return entryRows
            .sorted { $0.position < $1.position }
            .compactMap(\.item.thumbnailURL)
            .prefix(4)
            .map { $0 }
    }

    private var totalDurationSeconds: Int {
        entryRows.compactMap { row in
            let seconds = DurationFormat.seconds(from: row.item.durationText)
            return seconds > 0 ? seconds : nil
        }.reduce(0, +)
    }

    private var isThisPlaylistActive: Bool {
        playback.sourcePlaylistId == livePlaylist.playlistId && !playback.queue.isEmpty
    }

    private var showPause: Bool { isThisPlaylistActive && playback.isPlaying }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(YTLiteColor.background)
                    .listRowSeparator(.hidden)

                sortRow
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(YTLiteColor.background)
                    .listRowSeparator(.hidden)
            }

            Section {
                if displayedTracks.isEmpty {
                    Text("Empty playlist")
                        .font(YTLiteType.body)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                        .listRowBackground(YTLiteColor.background)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(Array(displayedTracks.enumerated()), id: \.element.trackId) { index, row in
                        trackRow(row, index: index)
                            .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                            .listRowBackground(YTLiteColor.background)
                    }
                    .onMove(perform: canReorder ? moveTracks : nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(YTLiteColor.background)
        .environment(\.editMode, .constant(canReorder && !displayedTracks.isEmpty ? .active : .inactive))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(YTLiteColor.background, for: .navigationBar)
        .onAppear { syncOrderedIds() }
        .onChange(of: refreshTick) { _, _ in syncOrderedIds() }
        .onChange(of: trackActions.listEpoch) { _, _ in
            refreshTick += 1
            onChange()
            if store?.playlist(id: playlist.playlistId) == nil {
                dismiss()
            }
        }
        .onChange(of: playlistActions.listEpoch) { _, _ in
            refreshTick += 1
            onChange()
            if store?.playlist(id: playlist.playlistId) == nil {
                dismiss()
            }
        }
        .sheet(isPresented: $showSortSheet) {
            PlaylistSortSheet(current: sort, onSelect: { selected in
                sort = selected
                showSortSheet = false
                if selected == .manual { syncOrderedIds() }
            })
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(YTLiteColor.surfaceElevated)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            // Clear selection first so a duplicate onChange cannot delete the cover just written.
            photoItem = nil
            Task { await applyPhotoCover(item) }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                PlaylistDetailCoverArt(
                    coverURLs: coverURLs,
                    systemType: livePlaylist.systemType
                )
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 220)

                if canEdit {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(YTLiteColor.onSurface)
                        .frame(width: 32, height: 32)
                        .background(YTLiteColor.surfaceElevated.opacity(0.92), in: Circle())
                        .padding(10)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                guard canEdit else { return }
                showPhotoPicker = true
            }
            .accessibilityAddTraits(canEdit ? .isButton : [])
            .accessibilityLabel(canEdit ? "Change cover" : "Playlist cover")

            Text(displayTitle)
                .font(.title2.bold())
                .foregroundStyle(YTLiteColor.onSurface)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(statsText)
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)

            HStack(spacing: 28) {
                if canEdit {
                    circleIconButton(systemName: "pencil") {
                        presentRename()
                    }
                } else {
                    Color.clear.frame(width: 48, height: 48)
                }

                Button(action: playOrToggle) {
                    Image(systemName: showPause ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(YTLiteColor.onSurface)
                        .frame(width: 72, height: 72)
                        .background(YTLiteColor.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(displayedTracks.isEmpty && !isThisPlaylistActive)

                circleIconButton(systemName: "ellipsis") {
                    presentPlaylistMore()
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, 8)
    }

    private var sortRow: some View {
        Button {
            showSortSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 16, weight: .medium))
                Text(sort.label)
                    .font(YTLiteType.body)
                Spacer()
            }
            .foregroundStyle(YTLiteColor.onSurfaceVariant)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func trackRow(_ row: PlaylistDetailTrack, index: Int) -> some View {
        HStack(spacing: 12) {
            Button {
                play(at: index)
            } label: {
                HStack(spacing: 12) {
                    VideoThumbnail(
                        url: row.item.thumbnailURL,
                        durationText: nil,
                        width: 48,
                        height: 48,
                        cornerRadius: 4,
                        badgePadding: 0
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.item.title)
                            .font(YTLiteType.rowTitleMedium)
                            .foregroundStyle(YTLiteColor.onSurface)
                            .lineLimit(1)
                        Text(subtitle(for: row.item))
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                trackActions.present(
                    item: row.item,
                    playlistId: livePlaylist.playlistId,
                    canRemoveFromPlaylist: canRemoveTracks
                )
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    private func circleIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(YTLiteColor.onSurface)
                .frame(width: 48, height: 48)
                .background(YTLiteColor.surfaceVariant, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var displayTitle: String {
        switch livePlaylist.systemType {
        case SystemPlaylistType.favorites: return "Liked videos"
        case SystemPlaylistType.watchLater: return "Watch later"
        default: return livePlaylist.name
        }
    }

    private var statsText: String {
        let count = entryRows.count
        let tracksLabel = count == 1 ? "1 track" : "\(count) tracks"
        guard totalDurationSeconds > 0 else { return tracksLabel }
        let minutes = totalDurationSeconds / 60
        let seconds = totalDurationSeconds % 60
        return "\(tracksLabel) • \(minutes) minutes, \(seconds) seconds"
    }

    private var coverKind: PlaylistActionContext.CoverKind {
        switch livePlaylist.systemType {
        case SystemPlaylistType.favorites: return .liked
        case SystemPlaylistType.watchLater: return .watchLater
        default: return .custom
        }
    }

    private func subtitle(for item: VideoItem) -> String {
        let artist = item.channelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = item.durationText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !artist.isEmpty, !duration.isEmpty { return "\(artist) • \(duration)" }
        if !artist.isEmpty { return artist }
        return duration
    }

    private func syncOrderedIds() {
        orderedTrackIds = entryRows
            .sorted { $0.position < $1.position }
            .map(\.trackId)
    }

    private func moveTracks(from source: IndexSet, to destination: Int) {
        guard canReorder else { return }
        var ids = displayedTracks.map(\.trackId)
        ids.move(fromOffsets: source, toOffset: destination)
        orderedTrackIds = ids
        store?.reorderPlaylistTracks(livePlaylist, orderedTrackIds: ids)
        refreshTick += 1
        onChange()
    }

    private func playOrToggle() {
        if isThisPlaylistActive {
            playback.togglePlayPause()
            return
        }
        play(at: 0)
    }

    private func play(at index: Int) {
        let items = displayedTracks.map(\.item)
        guard !items.isEmpty else { return }
        playback.play(
            items: items,
            startAt: index,
            sourcePlaylistId: livePlaylist.playlistId
        )
    }

    private func presentRename() {
        playlistActions.presentRename(
            .from(playlist: livePlaylist, title: displayTitle, coverKind: coverKind)
        )
    }

    private func presentPlaylistMore() {
        playlistActions.present(
            .from(playlist: livePlaylist, title: displayTitle, coverKind: coverKind)
        )
    }

    private func applyPhotoCover(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                await MainActor.run {
                    playlistActions.showToast("Couldn't update cover")
                }
                return
            }
            await MainActor.run {
                store?.setPlaylistCoverImage(livePlaylist, image: image)
                refreshTick += 1
                onChange()
                playlistActions.showToast("Cover updated")
            }
        } catch {
            await MainActor.run {
                playlistActions.showToast("Couldn't update cover")
            }
        }
    }
}

// MARK: - Models

private struct PlaylistDetailTrack: Identifiable, Hashable {
    var id: String { trackId }
    let trackId: String
    let item: VideoItem
    let position: Int
    let addedAt: Date
}

private enum PlaylistTrackSort: String, CaseIterable, Identifiable {
    case manual
    case recentlyAdded
    case title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .recentlyAdded: return "Recently added"
        case .title: return "Title"
        }
    }
}

// MARK: - Cover

private struct PlaylistDetailCoverArt: View {
    let coverURLs: [URL]
    let systemType: String?

    var body: some View {
        Group {
            switch systemType {
            case SystemPlaylistType.favorites:
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.31, green: 0.76, blue: 0.97),
                            Color(red: 0.91, green: 0.12, blue: 0.39),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(.white)
                }
            case SystemPlaylistType.watchLater:
                ZStack {
                    YTLiteColor.accent
                    Image(systemName: "clock.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(.white)
                }
            default:
                if coverURLs.count >= 4 {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            collageCell(coverURLs[0])
                            collageCell(coverURLs[1])
                        }
                        HStack(spacing: 0) {
                            collageCell(coverURLs[2])
                            collageCell(coverURLs[3])
                        }
                    }
                } else if let url = coverURLs.first {
                    RemoteImage(url: url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    ZStack {
                        YTLiteColor.surfaceVariant
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(YTLiteColor.onSurface)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func collageCell(_ url: URL) -> some View {
        RemoteImage(url: url)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

// MARK: - Sort sheet

private struct PlaylistSortSheet: View {
    let current: PlaylistTrackSort
    var onSelect: (PlaylistTrackSort) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            YTLiteSheetGrabHandle()
            YTLiteSheetTitle(title: "Sort by")
            Divider().overlay(YTLiteColor.surfaceVariant)

            ForEach(PlaylistTrackSort.allCases) { option in
                YTLiteSheetActionRow(
                    systemImage: "arrow.up.arrow.down",
                    title: option.label,
                    isSelected: option == current
                ) {
                    onSelect(option)
                }
            }
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(YTLiteColor.surfaceElevated)
    }
}
