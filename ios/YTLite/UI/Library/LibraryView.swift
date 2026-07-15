import SwiftUI

private enum LibraryFilter: String, CaseIterable {
    case playlists = "Playlists"
    case songs = "Songs"
    case channels = "Channels"
}

struct LibraryView: View {
    @Environment(\.libraryStore) private var store
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appModel: AppModel
    @State private var playlists: [LibraryPlaylist] = []
    @State private var history: [PlayHistoryItem] = []
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var showPlayer = false
    @State private var filter: LibraryFilter = .playlists

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        downloadsRow
                        filterChips
                        listControls
                        contentList
                    }
                    .padding(.bottom, 80)
                }

                Button {
                    showNewPlaylist = true
                } label: {
                    Text("+ New")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(YTLiteColor.accent, in: Capsule())
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
            .background(YTLiteColor.background)
            .navigationBarHidden(true)
            .navigationDestination(for: String.self) { playlistId in
                if let playlist = playlists.first(where: { $0.playlistId == playlistId }) {
                    PlaylistDetailView(playlist: playlist) { reload() }
                }
            }
            .onAppear(perform: reload)
            .alert("New playlist", isPresented: $showNewPlaylist) {
                TextField("Name", text: $newPlaylistName)
                Button("Create") {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        _ = store?.createPlaylist(name: name)
                        newPlaylistName = ""
                        reload()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showPlayer) {
                NavigationStack { PlayerDetailView().preferredColorScheme(.dark) }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Library")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Spacer()
            if auth.isAuthenticated {
                Button {
                    Task {
                        await auth.signOut()
                        appModel.syncAuth(auth)
                        reload()
                    }
                } label: {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                }
            } else {
                Button {
                    Task {
                        await auth.signInWithGoogle()
                        appModel.syncAuth(auth)
                        if let store, auth.isAuthenticated {
                            await LibrarySyncService(auth: auth).syncBidirectional(store: store)
                            reload()
                        }
                    }
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.title2)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                }
            }
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            }
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.top, 8)
    }

    private var downloadsRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(YTLiteColor.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Downloads")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Tap to manage downloads")
                    .font(.caption)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
        }
        .padding(14)
        .background(YTLiteColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, YTLiteLayout.screenPadding)
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(LibraryFilter.allCases, id: \.self) { item in
                YTLiteChip(title: item.rawValue, selected: filter == item) {
                    filter = item
                }
            }
            Spacer()
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
    }

    private var listControls: some View {
        HStack {
            Text("\(displayItemCount) items")
                .font(.subheadline)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            Spacer()
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            Image(systemName: "checkmark.circle")
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .padding(.leading, 12)
            Image(systemName: "square.grid.2x2")
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .padding(.leading, 12)
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
    }

    private var displayItemCount: Int {
        switch filter {
        case .playlists: return playlists.count + 1 // + history row
        case .songs: return history.count
        case .channels: return 0
        }
    }

    @ViewBuilder
    private var contentList: some View {
        switch filter {
        case .playlists:
            LazyVStack(spacing: 0) {
                ForEach(playlists, id: \.playlistId) { playlist in
                    NavigationLink(value: playlist.playlistId) {
                        playlistRow(playlist)
                    }
                    .buttonStyle(.plain)
                }
                // Always show History as a system-looking row
                Button {
                    filter = .songs
                } label: {
                    libraryRow(
                        title: "History",
                        subtitle: "System · \(history.count) songs",
                        cover: .history
                    )
                }
                .buttonStyle(.plain)
            }
        case .songs:
            LazyVStack(spacing: 0) {
                if history.isEmpty {
                    Text("No plays yet")
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .padding()
                } else {
                    ForEach(history, id: \.playedAt) { item in
                        Button {
                            playback.play(items: [item.asVideoItem], startAt: 0)
                            showPlayer = true
                        } label: {
                            LibrarySongRow(item: item.asVideoItem)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .channels:
            Text("Channel follows coming soon")
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .padding()
                .frame(maxWidth: .infinity)
        }
    }

    private func playlistRow(_ playlist: LibraryPlaylist) -> some View {
        let cover: SystemCover = {
            switch playlist.systemType {
            case SystemPlaylistType.favorites: return .liked
            case SystemPlaylistType.watchLater: return .watchLater
            default: return .custom
            }
        }()
        let displayName: String = {
            switch playlist.systemType {
            case SystemPlaylistType.favorites: return "Liked videos"
            case SystemPlaylistType.watchLater: return "Watch later"
            default: return playlist.name
            }
        }()
        let kind = playlist.systemType == nil ? "Playlist" : "System"
        return libraryRow(
            title: displayName,
            subtitle: "\(kind) · \(playlist.trackCount) songs",
            cover: cover,
            thumbnailURL: nil
        )
    }

    private func libraryRow(
        title: String,
        subtitle: String,
        cover: SystemCover,
        thumbnailURL: URL? = nil
    ) -> some View {
        HStack(spacing: 14) {
            SystemCoverView(cover: cover, url: thumbnailURL)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            }
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, 10)
    }

    private func reload() {
        playlists = store?.allPlaylists() ?? []
        history = store?.history() ?? []
    }
}

private enum SystemCover {
    case liked, watchLater, history, local, custom
}

private struct SystemCoverView: View {
    let cover: SystemCover
    var url: URL?

    var body: some View {
        ZStack {
            switch cover {
            case .liked:
                LinearGradient(
                    colors: [Color(red: 0.2, green: 0.45, blue: 0.95), Color(red: 0.85, green: 0.3, blue: 0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "hand.thumbsup.fill").foregroundStyle(.white)
            case .watchLater:
                YTLiteColor.accent
                Image(systemName: "clock.fill").foregroundStyle(.white)
            case .history:
                Color(red: 0.35, green: 0.32, blue: 0.42)
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.white)
            case .local:
                YTLiteColor.surfaceVariant
                Image(systemName: "music.note.list").foregroundStyle(.white)
            case .custom:
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: YTLiteColor.surfaceVariant
                        }
                    }
                } else {
                    YTLiteColor.surfaceVariant
                    Image(systemName: "music.note.list").foregroundStyle(.white)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct LibrarySongRow: View {
    let item: VideoItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: item.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: YTLiteColor.surfaceVariant
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                if let d = item.durationText {
                    DurationBadge(text: d).scaleEffect(0.85).padding(2)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Text(item.channelName).font(.caption).foregroundStyle(YTLiteColor.onSurfaceVariant).lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.down.to.line").foregroundStyle(YTLiteColor.onSurfaceVariant)
            Image(systemName: "ellipsis").foregroundStyle(YTLiteColor.onSurfaceVariant)
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, 8)
    }
}

struct PlaylistDetailView: View {
    let playlist: LibraryPlaylist
    var onChange: () -> Void
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.libraryStore) private var store
    @State private var showPlayer = false

    private var tracks: [VideoItem] {
        playlist.entries
            .sorted { $0.position < $1.position }
            .compactMap { $0.track?.asVideoItem }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if tracks.isEmpty {
                    Text("Empty playlist")
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .padding()
                } else {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, item in
                        Button {
                            playback.play(items: tracks, startAt: index)
                            showPlayer = true
                        } label: {
                            LibrarySongRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(YTLiteColor.background)
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let current = playback.nowPlaying {
                    Button("Add current") {
                        store?.add(
                            item: VideoItem(
                                videoId: current.videoId,
                                title: current.title,
                                channelName: current.channelName,
                                thumbnailURL: current.thumbnailURL
                            ),
                            to: playlist
                        )
                        onChange()
                    }
                }
            }
        }
        .sheet(isPresented: $showPlayer) {
            NavigationStack { PlayerDetailView().preferredColorScheme(.dark) }
        }
    }
}
