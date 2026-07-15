import SwiftUI

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
    @State private var selectedPlaylist: LibraryPlaylist?
    @State private var isSyncing = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if auth.isAuthenticated {
                        Text(auth.session?.user.email ?? "Signed in")
                        Button("Sign out") {
                            Task {
                                await auth.signOut()
                                appModel.syncAuth(auth)
                            }
                        }
                        Button(isSyncing ? "Syncing…" : "Sync now") {
                            Task {
                                isSyncing = true
                                if let store {
                                    await LibrarySyncService(auth: auth).syncBidirectional(store: store)
                                    reload()
                                }
                                isSyncing = false
                            }
                        }
                        .disabled(isSyncing || store == nil)
                    } else {
                        Text(auth.isConfigured ? "Guest mode" : "Supabase not configured")
                            .foregroundStyle(.secondary)
                        Button(auth.isBusy ? "Signing in…" : "Sign in with Google") {
                            Task {
                                await auth.signInWithGoogle()
                                appModel.syncAuth(auth)
                                if let store, auth.isAuthenticated {
                                    await LibrarySyncService(auth: auth).syncBidirectional(store: store)
                                    reload()
                                }
                            }
                        }
                        .disabled(auth.isBusy || !auth.isConfigured)
                        if let err = auth.lastError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }
                }

                Section("Playlists") {
                    ForEach(playlists, id: \.playlistId) { playlist in
                        NavigationLink(value: playlist.playlistId) {
                            VStack(alignment: .leading) {
                                Text(playlist.name)
                                Text("\(playlist.trackCount) tracks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("New playlist") { showNewPlaylist = true }
                }

                Section("History") {
                    if history.isEmpty {
                        Text("No plays yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(history, id: \.playedAt) { item in
                            Button {
                                playback.play(items: [item.asVideoItem], startAt: 0)
                                showPlayer = true
                            } label: {
                                VideoRow(item: item.asVideoItem)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: String.self) { playlistId in
                if let playlist = playlists.first(where: { $0.playlistId == playlistId }) {
                    PlaylistDetailView(playlist: playlist) {
                        reload()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Settings") { SettingsView() }
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
                NavigationStack { PlayerDetailView() }
            }
        }
    }

    private func reload() {
        playlists = store?.allPlaylists() ?? []
        history = store?.history() ?? []
    }
}

struct PlaylistDetailView: View {
    let playlist: LibraryPlaylist
    var onChange: () -> Void
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.libraryStore) private var store
    @State private var showPlayer = false
    @State private var showAdd = false

    private var tracks: [VideoItem] {
        playlist.entries
            .sorted { $0.position < $1.position }
            .compactMap { $0.track?.asVideoItem }
    }

    var body: some View {
        List {
            if tracks.isEmpty {
                Text("Empty playlist").foregroundStyle(.secondary)
            } else {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, item in
                    Button {
                        playback.play(items: tracks, startAt: index)
                        showPlayer = true
                    } label: {
                        VideoRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
            NavigationStack { PlayerDetailView() }
        }
    }
}
