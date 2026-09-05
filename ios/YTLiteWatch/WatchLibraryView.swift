import SwiftUI

/// Library mirror + CRUD actions (Phase 6).
struct WatchLibraryView: View {
    @EnvironmentObject private var bridge: WatchConnectivityBridge
    @ObservedObject private var library = WatchLibraryClient.shared

    @State private var showCreatePlaylist = false
    @State private var createName = ""
    @State private var renameTarget: WatchConnectivityProtocol.LibraryPlaylistDTO?
    @State private var renameName = ""
    @State private var deleteTarget: WatchConnectivityProtocol.LibraryPlaylistDTO?

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = library.snapshot {
                    List {
                        disconnectedBanner

                        accountRow(snapshot)

                        if bridge.isReachable {
                            Button {
                                createName = ""
                                showCreatePlaylist = true
                            } label: {
                                Label(
                                    String(localized: "watch.create_playlist", defaultValue: "New playlist"),
                                    systemImage: "plus"
                                )
                                .font(.caption)
                            }
                        }

                        if !snapshot.playlists.isEmpty {
                            Section(String(localized: "watch.playlists", defaultValue: "Playlists")) {
                                ForEach(snapshot.playlists) { playlist in
                                    NavigationLink {
                                        WatchPlaylistDetailView(playlistId: playlist.playlistId)
                                    } label: {
                                        playlistRow(playlist)
                                    }
                                    .contextMenu {
                                        playlistContextMenu(playlist)
                                    }
                                }
                            }
                        }

                        if !snapshot.history.isEmpty {
                            Section(String(localized: "watch.history", defaultValue: "History")) {
                                ForEach(Array(snapshot.history.enumerated()), id: \.offset) { index, track in
                                    WatchTrackRow(track: track, historyIndex: index) {
                                        playHistory(index: index)
                                    }
                                }
                            }
                        }

                        if snapshot.playlists.isEmpty && snapshot.history.isEmpty {
                            Text(String(localized: "watch.library_empty", defaultValue: "Library empty"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label(
                            String(localized: "watch.library_empty", defaultValue: "Library empty"),
                            systemImage: "books.vertical"
                        )
                    } description: {
                        Text(
                            bridge.isReachable
                                ? String(localized: "watch.library_sync_hint", defaultValue: "Waiting for iPhone sync…")
                                : String(localized: "watch.phone_required", defaultValue: "Open Mixtube on iPhone")
                        )
                    }
                }
            }
            .navigationTitle(String(localized: "watch.library", defaultValue: "Library"))
            .onAppear {
                library.start()
                if bridge.isReachable {
                    library.requestSnapshot()
                }
            }
            .sheet(isPresented: $showCreatePlaylist) {
                nameSheet(
                    title: String(localized: "watch.create_playlist", defaultValue: "New playlist"),
                    text: $createName
                ) {
                    guard library.requireConnected() else { return }
                    library.createPlaylist(name: createName)
                    showCreatePlaylist = false
                }
            }
            .sheet(item: $renameTarget) { playlist in
                nameSheet(
                    title: String(localized: "watch.rename_playlist", defaultValue: "Rename"),
                    text: $renameName
                ) {
                    guard library.requireConnected() else { return }
                    library.renamePlaylist(playlistId: playlist.playlistId, name: renameName)
                    renameTarget = nil
                }
            }
            .confirmationDialog(
                String(localized: "watch.delete_playlist", defaultValue: "Delete playlist?"),
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(String(localized: "watch.delete", defaultValue: "Delete"), role: .destructive) {
                    if let id = deleteTarget?.playlistId, library.requireConnected() {
                        library.deletePlaylist(playlistId: id)
                    }
                    deleteTarget = nil
                }
                Button(String(localized: "watch.cancel", defaultValue: "Cancel"), role: .cancel) {
                    deleteTarget = nil
                }
            }
        }
    }

    @ViewBuilder
    private var disconnectedBanner: some View {
        if !bridge.isReachable {
            Text(WL("watch.phone_disconnected_readonly", "Phone disconnected · Read only"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
                .listRowBackground(Color.clear)
        }
        if let share = library.lastShareMessage {
            Text(share)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
        }
        if let error = library.lastCommandError {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.orange)
                .listRowBackground(Color.clear)
        }
    }

    private func accountRow(_ snapshot: WatchConnectivityProtocol.LibrarySnapshot) -> some View {
        HStack {
            Image(systemName: snapshot.authIsGuest ? "person" : "person.fill")
                .font(.caption)
            Text(
                snapshot.authIsGuest
                    ? String(localized: "watch.guest", defaultValue: "Guest")
                    : (snapshot.authDisplayName ?? String(localized: "watch.signed_in", defaultValue: "Signed in"))
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
        }
        .listRowBackground(Color.clear)
    }

    private func playlistRow(_ playlist: WatchConnectivityProtocol.LibraryPlaylistDTO) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(playlist.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                if playlist.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(playlist.trackCount) \(String(localized: "watch.tracks", defaultValue: "tracks"))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func playlistContextMenu(_ playlist: WatchConnectivityProtocol.LibraryPlaylistDTO) -> some View {
        Button {
            guard library.requireConnected() else { return }
            library.shufflePlay(playlistId: playlist.playlistId)
        } label: {
            Label(String(localized: "watch.shuffle_play", defaultValue: "Shuffle play"), systemImage: "shuffle")
        }

        if playlist.canEdit {
            Button {
                guard library.requireConnected() else { return }
                renameName = playlist.name
                renameTarget = playlist
            } label: {
                Label(String(localized: "watch.rename", defaultValue: "Rename"), systemImage: "pencil")
            }

            Button {
                guard library.requireConnected() else { return }
                library.setPinned(playlistId: playlist.playlistId, pinned: !playlist.isPinned)
            } label: {
                Label(
                    playlist.isPinned
                        ? String(localized: "watch.unpin", defaultValue: "Unpin")
                        : String(localized: "watch.pin", defaultValue: "Pin"),
                    systemImage: playlist.isPinned ? "pin.slash" : "pin"
                )
            }

            Button(role: .destructive) {
                guard library.requireConnected() else { return }
                deleteTarget = playlist
            } label: {
                Label(String(localized: "watch.delete", defaultValue: "Delete"), systemImage: "trash")
            }
        } else if playlist.systemType != "favorites" {
            Button {
                guard library.requireConnected() else { return }
                library.setPinned(playlistId: playlist.playlistId, pinned: !playlist.isPinned)
            } label: {
                Label(
                    playlist.isPinned
                        ? String(localized: "watch.unpin", defaultValue: "Unpin")
                        : String(localized: "watch.pin", defaultValue: "Pin"),
                    systemImage: playlist.isPinned ? "pin.slash" : "pin"
                )
            }
        }
    }

    private func playHistory(index: Int) {
        guard library.requireConnected() else { return }
        library.playHistory(index: index)
    }

    private func nameSheet(title: String, text: Binding<String>, onSave: @escaping () -> Void) -> some View {
        NavigationStack {
            Form {
                TextField(String(localized: "watch.name", defaultValue: "Name"), text: text)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "watch.cancel", defaultValue: "Cancel")) {
                        showCreatePlaylist = false
                        renameTarget = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "watch.save", defaultValue: "Save")) {
                        onSave()
                    }
                    .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
