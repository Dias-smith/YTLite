import SwiftUI

private enum LibraryRoute {
    static let history = "system:history"
}

private enum LibraryFilter: String, CaseIterable {
    case playlists
    case songs
    case channels

    var title: String {
        switch self {
        case .playlists: return L("library.filter.playlists")
        case .songs: return L("library.filter.songs")
        case .channels: return L("library.filter.channels")
        }
    }
}

private enum LibrarySortMode: String, CaseIterable, Identifiable {
    case recentActivity
    case recentlySaved
    case title
    case duration
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentActivity: return L("library.sort.recent_activity")
        case .recentlySaved: return L("library.sort.recently_saved")
        case .title: return L("library.sort.title_asc")
        case .duration: return L("library.sort.duration")
        case .custom: return L("library.sort.custom")
        }
    }
}

private enum LibraryViewMode {
    case list
    case grid
}

private let playlistManualOrderKey = "ytlite.library.playlistManualOrder"

struct LibraryView: View {
    @Environment(\.libraryStore) private var store
    @Environment(\.selectAppTab) private var selectAppTab
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @EnvironmentObject private var playlistActions: PlaylistActionPresenter

    @State private var playlists: [LibraryPlaylist] = []
    @State private var history: [VideoItem] = []
    /// Deduped songs from all playlists (+ history-only), Library → Songs tab.
    @State private var songs: [VideoItem] = []
    @State private var channels: [UserSubscribedChannel] = []
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var showPlayer = false
    @State private var filter: LibraryFilter = .playlists
    @State private var channelPendingUnsubscribe: UserSubscribedChannel?

    @State private var sortMode: LibrarySortMode = .recentActivity
    @State private var viewMode: LibraryViewMode = .list
    @State private var showSortMenu = false

    @State private var isSelectionMode = false
    @State private var selectedIds: Set<String> = []
    @State private var showDeleteConfirm = false
    @State private var showBatchPlaylistPicker = false

    @State private var isReorderMode = false
    @State private var reorderItems: [PlaylistDisplayItem] = []
    @State private var showAccountMenu = false
    @State private var pendingSwitchAccount = false
    @State private var pendingDeleteAccount = false
    @State private var showDeleteAccountConfirm = false
    @State private var deleteAccountError: String?
    @State private var showSignInOptions = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                if isReorderMode {
                    // Own scrolling List (not nested in ScrollView) so last rows aren't clipped.
                    VStack(alignment: .leading, spacing: 0) {
                        reorderHeader
                            .padding(.bottom, YTLiteLayout.stackLoose)
                        reorderList
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: YTLiteLayout.screenPadding) {
                            if isSelectionMode {
                                selectionHeader
                            } else {
                                header
                                filterChips
                                listControls
                            }
                            contentList
                        }
                        .padding(.bottom, 80)
                    }
                }

                if !isSelectionMode && !isReorderMode {
                    Button {
                        showNewPlaylist = true
                    } label: {
                        Text(L("library.new"))
                            .font(YTLiteType.labelEmphasized)
                            .foregroundStyle(YTLiteColor.onAccent)
                            .padding(.horizontal, 18)
                            .padding(.vertical, YTLiteLayout.stackLoose)
                            .background(YTLiteColor.accent, in: Capsule())
                    }
                    .padding(.trailing, YTLiteLayout.screenPadding)
                    .padding(.bottom, YTLiteLayout.screenPadding)
                    .disabled(appModel.isLibrarySyncing)
                }
            }
            .overlay {
                if appModel.isLibrarySyncing {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(YTLiteColor.accent)
                                .scaleEffect(1.15)
                            Text(L("library.syncing"))
                                .font(YTLiteType.meta.weight(.semibold))
                                .foregroundStyle(YTLiteColor.onSurface)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 22)
                        .background(
                            YTLiteColor.surfaceElevated,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .allowsHitTesting(true)
                }
            }
            .background(YTLiteColor.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { destinationId in
                if destinationId == LibraryRoute.history {
                    HistoryDetailView { reload() }
                } else if let playlist = playlists.first(where: { $0.playlistId == destinationId }) {
                    PlaylistDetailView(playlist: playlist) { reload() }
                }
            }
            .onAppear(perform: reload)
            .onChange(of: trackActions.listEpoch) { _, _ in reload() }
            .onChange(of: playlistActions.listEpoch) { _, _ in reload() }
            .onChange(of: appModel.libraryRevision) { _, _ in reload() }
            .onChange(of: playback.isChannelSubscribed) { _, _ in reload() }
            .onChange(of: filter) { _, newFilter in
                exitSelectionMode()
                if newFilter != .playlists { exitReorderMode(save: false) }
                if !sortOptions(for: newFilter).contains(sortMode), sortMode != .custom {
                    sortMode = .recentActivity
                }
                reload()
            }
            .alert(
                L("library.unsubscribe"),
                isPresented: Binding(
                    get: { channelPendingUnsubscribe != nil },
                    set: { if !$0 { channelPendingUnsubscribe = nil } }
                )
            ) {
                Button(L("library.unsubscribe"), role: .destructive) {
                    if let channel = channelPendingUnsubscribe {
                        _ = store?.toggleSubscribeChannel(
                            channelId: channel.channelId,
                            title: channel.title,
                            avatarUrl: channel.avatarUrl
                        )
                        playback.refreshSubscribeState()
                        reload()
                    }
                    channelPendingUnsubscribe = nil
                }
                Button(L("common.cancel"), role: .cancel) {
                    channelPendingUnsubscribe = nil
                }
            } message: {
                Text(
                    Lf(
                        "library.unsubscribe_named",
                        channelPendingUnsubscribe?.title ?? L("common.channel_lowercase")
                    )
                )
            }
            .sheet(isPresented: $showSortMenu) {
                LibrarySortSheet(
                    options: sortOptions(for: filter),
                    current: sortMode,
                    showsReorderPlaylists: filter == .playlists,
                    onSelect: { selected in
                        sortMode = selected
                        exitReorderMode(save: false)
                        showSortMenu = false
                        reload()
                    },
                    onReorderPlaylists: {
                        showSortMenu = false
                        enterReorderMode()
                    }
                )
                .presentationDetents([.height(filter == .songs ? 380 : 340)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(YTLiteColor.surfaceElevated)
            }
            .sheet(isPresented: $showNewPlaylist) {
                NavigationStack {
                    Form {
                        TextField(L("common.name"), text: $newPlaylistName)
                            .foregroundStyle(YTLiteColor.onSurface)
                    }
                    .scrollContentBackground(.hidden)
                    .background(YTLiteColor.background)
                    .navigationTitle(L("library.new_playlist"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L("common.cancel")) {
                                newPlaylistName = ""
                                showNewPlaylist = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L("common.create")) {
                                let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !name.isEmpty {
                                    _ = store?.createPlaylist(name: name)
                                    newPlaylistName = ""
                                    showNewPlaylist = false
                                    reload()
                                }
                            }
                            .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showDeleteConfirm) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: YTLiteLayout.stackLoose) {
                        Text(deleteConfirmMessage)
                            .font(YTLiteType.body)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        Spacer()
                        Button(role: .destructive) {
                            deleteSelected()
                            showDeleteConfirm = false
                        } label: {
                            Text(filter == .channels ? L("library.unsubscribe") : L("common.delete"))
                                .font(YTLiteType.labelEmphasized)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(YTLiteColor.danger)
                        Button {
                            showDeleteConfirm = false
                        } label: {
                            Text(L("common.cancel"))
                                .font(YTLiteType.labelEmphasized)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(YTLiteLayout.screenPadding)
                    .background(YTLiteColor.background)
                    .navigationTitle(filter == .channels ? L("library.unsubscribe") : L("common.delete"))
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showPlayer) {
                NavigationStack { PlayerDetailView() }
            }
            .sheet(isPresented: $showBatchPlaylistPicker) {
                LibraryPlaylistPickSheet(
                    playlists: playlists.filter {
                        $0.systemType == nil
                            || $0.systemType == SystemPlaylistType.favorites
                            || $0.systemType == SystemPlaylistType.watchLater
                    },
                    title: L("library.add_to_playlist"),
                    displayName: { displayName(for: $0) },
                    onSelect: { playlist in
                        addSelectedSongs(to: playlist)
                        showBatchPlaylistPicker = false
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(YTLiteColor.surfaceElevated)
            }
            .sheet(isPresented: $showAccountMenu, onDismiss: {
                if pendingSwitchAccount {
                    pendingSwitchAccount = false
                    Task {
                        await auth.switchAccount()
                        appModel.syncAuth(auth)
                        reload()
                    }
                    return
                }
                if pendingDeleteAccount {
                    pendingDeleteAccount = false
                    // Present confirm after sheet teardown so it isn't swallowed.
                    DispatchQueue.main.async {
                        showDeleteAccountConfirm = true
                    }
                }
            }) {
                AccountMenuSheet(
                    auth: auth,
                    onViewChannel: {
                        showAccountMenu = false
                        // Defer tab switch until after sheet teardown.
                        DispatchQueue.main.async {
                            selectAppTab?(.you)
                        }
                    },
                    onSwitchAccount: {
                        pendingSwitchAccount = true
                        showAccountMenu = false
                    },
                    onSignOut: {
                        showAccountMenu = false
                        Task {
                            await auth.signOut()
                            appModel.syncAuth(auth)
                            reload()
                        }
                    },
                    onDeleteAccount: {
                        pendingDeleteAccount = true
                        showAccountMenu = false
                    }
                )
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
                .presentationBackground(YTLiteColor.surface)
            }
            .sheet(isPresented: $showSignInOptions) {
                NavigationStack {
                    VStack(spacing: 24) {
                        Text(L("auth.sign_in_to_sync"))
                            .font(YTLiteType.body)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 12)

                        SignInOptionsView(auth: auth) {
                            appModel.syncAuth(auth)
                            showSignInOptions = false
                            reload()
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .background(YTLiteColor.background)
                    .navigationTitle(L("common.sign_in"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L("common.cancel")) { showSignInOptions = false }
                        }
                    }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
            }
            .alert(
                "Delete account?",
                isPresented: $showDeleteAccountConfirm
            ) {
                Button(L("account.delete"), role: .destructive) {
                    Task { await performDeleteAccount() }
                }
                Button(L("common.cancel"), role: .cancel) {}
            } message: {
                Text(
                    "This permanently deletes your YouLite account and cloud library data (playlists, history, subscriptions, and metadata). This can't be undone."
                )
            }
            .alert(
                L("account.delete_failed"),
                isPresented: Binding(
                    get: { deleteAccountError != nil },
                    set: { if !$0 { deleteAccountError = nil } }
                )
            ) {
                Button(L("common.ok"), role: .cancel) { deleteAccountError = nil }
            } message: {
                Text(deleteAccountError ?? "")
            }
        }
    }

    // MARK: - Headers

    private var header: some View {
        HStack(alignment: .center) {
            Text(L("library.title"))
                .font(YTLiteType.pageTitle)
                .foregroundStyle(YTLiteColor.onSurface)
            Spacer()
            if auth.isAuthenticated {
                Button {
                    showAccountMenu = true
                } label: {
                    FeedChannelAvatar(
                        url: auth.avatarURL,
                        channelName: auth.displayName,
                        size: 28
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("common.account"))
            } else {
                Button {
                    showSignInOptions = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                }
                .disabled(auth.isBusy)
                .accessibilityLabel(L("common.sign_in"))
            }
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
                selectAllSelectable()
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
            if filter == .songs, !selectedIds.isEmpty {
                Button {
                    showBatchPlaylistPicker = true
                } label: {
                    Image(systemName: "text.badge.plus")
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .frame(width: 36, height: 36)
                }
            }
            if !selectedIds.isEmpty {
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

    private var reorderHeader: some View {
        HStack {
            Text(L("library.reorder"))
                .font(YTLiteType.sectionTitle)
                .foregroundStyle(YTLiteColor.onSurface)
            Spacer()
            Button(L("common.done")) {
                exitReorderMode(save: true)
            }
            .font(YTLiteType.labelEmphasized)
            .foregroundStyle(YTLiteColor.accent)
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.top, YTLiteLayout.rowVertical)
    }

    private var filterChips: some View {
        HStack(spacing: YTLiteLayout.stackDefault) {
            ForEach(LibraryFilter.allCases, id: \.self) { item in
                YTLiteChip(title: item.title, selected: filter == item) {
                    filter = item
                }
            }
            Spacer()
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
    }

    private var listControls: some View {
        HStack {
            Text(Lf("common.n_items", displayItemCount))
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            Spacer()
            Button {
                showSortMenu = true
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if supportsMultiSelect {
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

            Button {
                viewMode = viewMode == .list ? .grid : .list
            } label: {
                Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
    }

    // MARK: - Content

    private var displayItemCount: Int {
        switch filter {
        case .playlists: return displayedPlaylists.count
        case .songs: return displayedSongs.count
        case .channels: return displayedChannels.count
        }
    }

    private var supportsMultiSelect: Bool {
        filter == .playlists || filter == .songs || filter == .channels
    }

    private var displayedPlaylists: [PlaylistDisplayItem] {
        orderedPlaylistItems()
    }

    private var displayedSongs: [VideoItem] { songs }

    private var displayedChannels: [UserSubscribedChannel] {
        switch sortMode {
        case .title:
            return channels.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .recentActivity, .recentlySaved, .duration, .custom:
            return channels.sorted { $0.subscribedAt > $1.subscribedAt }
        }
    }

    private func sortOptions(for filter: LibraryFilter) -> [LibrarySortMode] {
        switch filter {
        case .songs:
            return [.recentActivity, .recentlySaved, .title, .duration]
        case .playlists, .channels:
            return [.recentActivity, .recentlySaved, .title]
        }
    }

    private var songSort: LibraryStore.LibrarySongSort {
        switch sortMode {
        case .recentActivity, .custom: return .recentActivity
        case .recentlySaved: return .recentlySaved
        case .title: return .title
        case .duration: return .duration
        }
    }

    @ViewBuilder
    private var contentList: some View {
        switch filter {
        case .playlists:
            playlistContent
        case .songs:
            songsContent
        case .channels:
            channelsContent
        }
    }

    @ViewBuilder
    private var channelsContent: some View {
        let items = displayedChannels
        if items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.2")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                Text(L("library.no_channels"))
                    .font(YTLiteType.sectionTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                Text(L("library.no_channels_hint"))
                    .font(YTLiteType.body)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        } else if viewMode == .grid {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                ForEach(items, id: \.channelId) { channel in
                    channelGridCell(channel)
                }
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(items, id: \.channelId) { channel in
                    channelListRow(channel)
                }
            }
        }
    }

    @ViewBuilder
    private func channelListRow(_ channel: UserSubscribedChannel) -> some View {
        let selected = selectedIds.contains(channel.channelId)
        if isSelectionMode {
            Button {
                toggleSelection(channel.channelId)
            } label: {
                channelRowLabel(channel, showCheck: true, selected: selected)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 0) {
                NavigationLink {
                    ChannelVideosView(channel: channel.asChannelItem)
                } label: {
                    channelRowLabel(channel, showCheck: false, selected: false, showsMore: false)
                }
                .buttonStyle(.plain)
                Button {
                    channelPendingUnsubscribe = channel
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
    }

    private func channelRowLabel(
        _ channel: UserSubscribedChannel,
        showCheck: Bool,
        selected: Bool,
        showsMore: Bool = true
    ) -> some View {
        HStack(spacing: 14) {
            if showCheck {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? YTLiteColor.accent : YTLiteColor.onSurfaceVariant)
            }
            channelAvatar(channel)
                .frame(width: 56, height: 56)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                Text(channel.title)
                    .font(YTLiteType.rowTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(1)
                Text(channelSubtitle(channel))
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if showsMore && !isSelectionMode {
                Image(systemName: "ellipsis")
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            }
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, YTLiteLayout.rowVertical)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func channelGridCell(_ channel: UserSubscribedChannel) -> some View {
        let selected = selectedIds.contains(channel.channelId)
        if isSelectionMode {
            Button {
                toggleSelection(channel.channelId)
            } label: {
                channelGridLabel(channel, showCheck: true, selected: selected)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ChannelVideosView(channel: channel.asChannelItem)
            } label: {
                channelGridLabel(channel, showCheck: false, selected: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func channelGridLabel(
        _ channel: UserSubscribedChannel,
        showCheck: Bool,
        selected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                channelAvatar(channel)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(Circle())
                if showCheck {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? YTLiteColor.accent : YTLiteColor.onSurface)
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                        .padding(6)
                }
            }
            Text(channel.title)
                .font(YTLiteType.rowTitleMedium)
                .foregroundStyle(YTLiteColor.onSurface)
                .lineLimit(2)
            Text(channelSubtitle(channel))
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func channelAvatar(_ channel: UserSubscribedChannel) -> some View {
        if let url = channel.avatarUrl.flatMap(URL.init(string:)) {
            RemoteImage(url: url)
        } else {
            ZStack {
                YTLiteColor.surfaceVariant
                Image(systemName: "person.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            }
        }
    }

    private func channelSubtitle(_ channel: UserSubscribedChannel) -> String {
        if let count = channel.subscriberCountText, !count.isEmpty { return count }
        if let handle = channel.handle, !handle.isEmpty { return handle }
        return "Channel"
    }

    @ViewBuilder
    private var playlistContent: some View {
        let items = displayedPlaylists
        if viewMode == .grid {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                ForEach(items) { item in
                    playlistGridCell(item)
                }
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    playlistRow(item)
                }
            }
        }
    }

    @ViewBuilder
    private func playlistRow(_ item: PlaylistDisplayItem) -> some View {
        if isSelectionMode {
            playlistListRow(item)
        } else {
            HStack(spacing: 0) {
                if let playlistId = item.playlist?.playlistId {
                    NavigationLink(value: playlistId) {
                        playlistListRowLabel(item, showCheck: false, selected: false, showsMore: false)
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(value: LibraryRoute.history) {
                        playlistListRowLabel(item, showCheck: false, selected: false, showsMore: false)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    presentPlaylistActions(for: item)
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
    }

    @ViewBuilder
    private var songsContent: some View {
        let songs = displayedSongs
        if songs.isEmpty {
            Text(L("library.no_plays"))
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .padding()
        } else if viewMode == .grid {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                ForEach(songs) { item in
                    songGridCell(item)
                }
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(songs) { item in
                    songListRow(item)
                }
            }
        }
    }

    private var reorderList: some View {
        List {
            ForEach(reorderItems) { item in
                HStack(spacing: 14) {
                    SystemCoverView(cover: item.cover, url: item.coverURL)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(YTLiteType.rowTitle)
                            .foregroundStyle(YTLiteColor.onSurface)
                        Text(item.subtitle)
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    }
                    Spacer(minLength: 0)
                }
                .listRowBackground(YTLiteColor.background)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }
            .onMove(perform: moveReorderItems)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rows / cells

    @ViewBuilder
    private func playlistListRow(_ item: PlaylistDisplayItem) -> some View {
        let selectable = item.isSelectable
        let selected = selectedIds.contains(item.id)
        Button {
            guard selectable else { return }
            toggleSelection(item.id)
        } label: {
            playlistListRowLabel(item, showCheck: true, selected: selected)
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
    }

    private func playlistListRowLabel(
        _ item: PlaylistDisplayItem,
        showCheck: Bool,
        selected: Bool,
        showsMore: Bool = true
    ) -> some View {
        HStack(spacing: 14) {
            if showCheck {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? YTLiteColor.accent : YTLiteColor.onSurfaceVariant)
                    .opacity(item.isSelectable ? 1 : 0.35)
            }
            libraryRowLabel(
                title: item.title,
                subtitle: item.subtitle,
                cover: item.cover,
                coverURL: item.coverURL,
                showsMore: showsMore && !isSelectionMode
            )
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, YTLiteLayout.rowVertical)
        .contentShape(Rectangle())
    }

    private func presentPlaylistActions(for item: PlaylistDisplayItem) {
        if let playlist = item.playlist {
            let kind: PlaylistActionContext.CoverKind = {
                switch item.cover {
                case .liked: return .liked
                case .watchLater: return .watchLater
                case .history: return .history
                default: return .custom
                }
            }()
            playlistActions.present(
                .from(playlist: playlist, title: item.title, coverKind: kind)
            )
        } else if item.id == LibraryRoute.history {
            playlistActions.present(.history())
        }
    }

    @ViewBuilder
    private func playlistGridCell(_ item: PlaylistDisplayItem) -> some View {
        let selectable = item.isSelectable
        let selected = selectedIds.contains(item.id)
        Group {
            if isSelectionMode {
                Button {
                    guard selectable else { return }
                    toggleSelection(item.id)
                } label: {
                    playlistGridLabel(item, showCheck: true, selected: selected)
                }
                .buttonStyle(.plain)
                .disabled(!selectable)
            } else if let playlistId = item.playlist?.playlistId {
                NavigationLink(value: playlistId) {
                    playlistGridLabel(item, showCheck: false, selected: false)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: LibraryRoute.history) {
                    playlistGridLabel(item, showCheck: false, selected: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func playlistGridLabel(
        _ item: PlaylistDisplayItem,
        showCheck: Bool,
        selected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                // GeometryReader keeps custom covers square so grid rows stay aligned.
                GeometryReader { geo in
                    SystemCoverView(cover: item.cover, url: item.coverURL, fillsContainer: true)
                        .frame(width: geo.size.width, height: geo.size.width)
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: YTLiteLayout.thumbRadius))
                if showCheck {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? YTLiteColor.accent : YTLiteColor.onSurface)
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                        .padding(6)
                        .opacity(item.isSelectable ? 1 : 0.35)
                }
            }
            Text(item.title)
                .font(YTLiteType.rowTitleMedium)
                .foregroundStyle(YTLiteColor.onSurface)
                .lineLimit(2)
            Text(item.subtitle)
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func songListRow(_ item: VideoItem) -> some View {
        let selected = selectedIds.contains(item.videoId)
        Button {
            if isSelectionMode {
                toggleSelection(item.videoId)
            } else {
                playback.play(items: displayedSongs, startAt: displayedSongs.firstIndex(of: item) ?? 0)
                showPlayer = true
            }
        } label: {
            HStack(spacing: YTLiteLayout.stackLoose) {
                if isSelectionMode {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? YTLiteColor.accent : YTLiteColor.onSurfaceVariant)
                        .padding(.leading, YTLiteLayout.screenPadding)
                }
                LibrarySongRow(item: item, compactLeading: isSelectionMode) {
                    if !isSelectionMode {
                        trackActions.present(item: item)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func songGridCell(_ item: VideoItem) -> some View {
        let selected = selectedIds.contains(item.videoId)
        Button {
            if isSelectionMode {
                toggleSelection(item.videoId)
            } else {
                playback.play(items: displayedSongs, startAt: displayedSongs.firstIndex(of: item) ?? 0)
                showPlayer = true
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    GeometryReader { geo in
                        VideoThumbnail(
                            url: item.thumbnailURL,
                            durationText: item.durationText,
                            width: geo.size.width,
                            height: geo.size.width,
                            cornerRadius: YTLiteLayout.thumbRadius,
                            badgePadding: 4
                        )
                    }
                    .aspectRatio(1, contentMode: .fit)
                    if isSelectionMode {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? YTLiteColor.accent : YTLiteColor.onSurface)
                            .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                            .padding(6)
                    }
                }
                Text(item.title)
                    .font(YTLiteType.rowTitleMedium)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(2)
                Text(item.channelName)
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func libraryRowLabel(
        title: String,
        subtitle: String,
        cover: SystemCover,
        coverURL: URL? = nil,
        showsMore: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            SystemCoverView(cover: cover, url: coverURL)
            VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                Text(title)
                    .font(YTLiteType.rowTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                Text(subtitle)
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            }
            Spacer()
            if showsMore {
                Image(systemName: "ellipsis")
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            }
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func enterSelectionMode() {
        guard supportsMultiSelect else { return }
        exitReorderMode(save: false)
        isSelectionMode = true
        selectedIds = []
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedIds = []
    }

    private func selectAllSelectable() {
        switch filter {
        case .playlists:
            selectedIds = Set(displayedPlaylists.filter(\.isSelectable).map(\.id))
        case .songs:
            selectedIds = Set(displayedSongs.map(\.videoId))
        case .channels:
            selectedIds = Set(displayedChannels.map(\.channelId))
        }
    }

    private var deleteConfirmMessage: String {
        switch filter {
        case .playlists:
            return Lf("library.delete_playlists", selectedIds.count)
        case .songs:
            return Lf("library.remove_songs", selectedIds.count)
        case .channels:
            return Lf("library.unsubscribe_n", selectedIds.count)
        }
    }

    private func deleteSelected() {
        guard let store else { return }
        switch filter {
        case .playlists:
            for id in selectedIds {
                if let playlist = playlists.first(where: { $0.playlistId == id }), playlist.systemType == nil {
                    store.deletePlaylist(playlist)
                }
            }
        case .songs:
            store.removeTracksFromLocalLibrary(trackIds: Array(selectedIds))
        case .channels:
            for id in selectedIds {
                if let channel = channels.first(where: { $0.channelId == id }) {
                    _ = store.toggleSubscribeChannel(
                        channelId: channel.channelId,
                        title: channel.title,
                        avatarUrl: channel.avatarUrl
                    )
                }
            }
            playback.refreshSubscribeState()
        }
        exitSelectionMode()
        reload()
    }

    private func addSelectedSongs(to playlist: LibraryPlaylist) {
        guard let store else { return }
        for videoId in selectedIds {
            if let item = songs.first(where: { $0.videoId == videoId }) {
                store.add(item: item, to: playlist)
            }
        }
        exitSelectionMode()
        reload()
    }

    private func enterReorderMode() {
        exitSelectionMode()
        viewMode = .list
        reorderItems = orderedPlaylistItems()
        isReorderMode = true
    }

    private func exitReorderMode(save: Bool) {
        guard isReorderMode else { return }
        if save {
            let ids = reorderItems.map(\.id)
            UserDefaults.standard.set(ids, forKey: playlistManualOrderKey)
            sortMode = .custom
        }
        isReorderMode = false
        reorderItems = []
    }

    private func moveReorderItems(from source: IndexSet, to destination: Int) {
        reorderItems.move(fromOffsets: source, toOffset: destination)
    }

    private func performDeleteAccount() async {
        guard let store, let userId = auth.userId else {
            deleteAccountError = "Not signed in"
            return
        }
        let userKey = OwnerKeyStore.userOwnerKey(userId: userId)
        appModel.beginLibrarySync()
        let ok = await auth.deleteAccount()
        if ok {
            store.clearOwnerBucket(userKey)
            store.setOwnerKey(OwnerKeyStore.stableGuestOwnerKey)
            appModel.syncAuth(auth)
            appModel.endLibrarySync()
            reload()
        } else {
            appModel.endLibrarySync()
            deleteAccountError = auth.lastError ?? "Please try again."
        }
    }

    private func reload() {
        playlists = store?.allPlaylists() ?? []
        let items = store?.historyVideos() ?? []
        history = store?.filterNotInterested(items) ?? items
        let songItems = store?.librarySongs(sort: songSort) ?? []
        songs = store?.filterNotInterested(songItems) ?? songItems
        channels = store?.allSubscribedChannels() ?? []
    }

    private func orderedPlaylistItems() -> [PlaylistDisplayItem] {
        let mapped = playlists.map { PlaylistDisplayItem.playlist($0) }
        let historyItem = PlaylistDisplayItem.history(songCount: history.count)
        let all = mapped + [historyItem]

        switch sortMode {
        case .custom:
            let order = UserDefaults.standard.stringArray(forKey: playlistManualOrderKey) ?? []
            if order.isEmpty {
                return defaultOrdered(all)
            }
            return all.sorted { a, b in
                let ia = order.firstIndex(of: a.id) ?? Int.max
                let ib = order.firstIndex(of: b.id) ?? Int.max
                if ia != ib { return ia < ib }
                return systemOrder(a) < systemOrder(b)
            }
        case .recentActivity, .duration:
            return defaultOrdered(all)
        case .recentlySaved:
            // System block first; custom newest-saved activity near the end of customs via updatedAt.
            let system = defaultSystemBlock(all)
            let custom = all.filter { $0.systemType == nil }
                .sorted { ($0.playlist?.sortCreatedAt ?? .distantPast) < ($1.playlist?.sortCreatedAt ?? .distantPast) }
            return system + custom
        case .title:
            let system = defaultSystemBlock(all)
            let custom = all.filter { $0.systemType == nil }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return system + custom
        }
    }

    /// Liked → Watch later → History → custom (created oldest → newest).
    private func defaultOrdered(_ items: [PlaylistDisplayItem]) -> [PlaylistDisplayItem] {
        defaultSystemBlock(items) + customPlaylistsAscending(items)
    }

    private func defaultSystemBlock(_ items: [PlaylistDisplayItem]) -> [PlaylistDisplayItem] {
        let liked = items.filter { $0.systemType == SystemPlaylistType.favorites }
        let watchLater = items.filter { $0.systemType == SystemPlaylistType.watchLater }
        let historyRows = items.filter { $0.id == LibraryRoute.history }
        return liked + watchLater + historyRows
    }

    private func customPlaylistsAscending(_ items: [PlaylistDisplayItem]) -> [PlaylistDisplayItem] {
        items.filter { $0.systemType == nil }
            .sorted {
                ($0.playlist?.sortCreatedAt ?? .distantPast) < ($1.playlist?.sortCreatedAt ?? .distantPast)
            }
    }

    private func systemOrder(_ item: PlaylistDisplayItem) -> Int {
        switch item.systemType {
        case SystemPlaylistType.favorites: return 0
        case SystemPlaylistType.watchLater: return 1
        case "history": return 2
        default: return Int.max
        }
    }

    private func displayName(for playlist: LibraryPlaylist) -> String {
        switch playlist.systemType {
        case SystemPlaylistType.favorites: return L("library.liked")
        case SystemPlaylistType.watchLater: return L("library.watch_later")
        default: return playlist.name
        }
    }
}

// MARK: - Playlist pick sheet (batch add)

private struct LibraryPlaylistPickSheet: View {
    let playlists: [LibraryPlaylist]
    let title: String
    var displayName: (LibraryPlaylist) -> String
    var onSelect: (LibraryPlaylist) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            YTLiteSheetGrabHandle()
            YTLiteSheetTitle(title: title)
            Divider().overlay(YTLiteColor.surfaceVariant)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(playlists, id: \.playlistId) { playlist in
                        YTLiteSheetActionRow(
                            systemImage: playlistRowIcon(for: playlist),
                            title: displayName(playlist)
                        ) {
                            onSelect(playlist)
                        }
                    }
                }
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(YTLiteColor.surfaceElevated.ignoresSafeArea())
    }

    private func playlistRowIcon(for playlist: LibraryPlaylist) -> String {
        switch playlist.systemType {
        case SystemPlaylistType.favorites: return "hand.thumbsup"
        case SystemPlaylistType.watchLater: return "clock"
        default: return "music.note.list"
        }
    }
}

// MARK: - Sort sheet

private struct LibrarySortSheet: View {
    let options: [LibrarySortMode]
    let current: LibrarySortMode
    var showsReorderPlaylists: Bool = false
    var onSelect: (LibrarySortMode) -> Void
    var onReorderPlaylists: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            YTLiteSheetGrabHandle()
            YTLiteSheetTitle(title: L("library.sort_by"))
            Divider().overlay(YTLiteColor.surfaceVariant)

            ForEach(options) { option in
                YTLiteSheetActionRow(
                    systemImage: "arrow.up.arrow.down",
                    title: option.title,
                    isSelected: option == current
                ) {
                    onSelect(option)
                }
            }

            if showsReorderPlaylists {
                YTLiteSheetActionRow(
                    systemImage: "line.3.horizontal",
                    title: L("library.reorder"),
                    action: onReorderPlaylists
                )
            }

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(YTLiteColor.surfaceElevated)
    }
}

// MARK: - Playlist display model

private struct PlaylistDisplayItem: Identifiable {
    let id: String
    let playlist: LibraryPlaylist?
    let title: String
    let subtitle: String
    let cover: SystemCover
    let coverURL: URL?
    let systemType: String?

    var isSelectable: Bool {
        // History is a synthetic system row (playlist == nil) and must not be multi-selected/deleted.
        guard let playlist else { return false }
        return playlist.systemType == nil
    }

    static func playlist(_ playlist: LibraryPlaylist) -> PlaylistDisplayItem {
        let cover: SystemCover = {
            switch playlist.systemType {
            case SystemPlaylistType.favorites: return .liked
            case SystemPlaylistType.watchLater: return .watchLater
            default: return .custom
            }
        }()
        let title: String = {
            switch playlist.systemType {
            case SystemPlaylistType.favorites: return L("library.liked")
            case SystemPlaylistType.watchLater: return L("library.watch_later")
            default: return playlist.name
            }
        }()
        let subtitle: String = {
            if playlist.systemType == nil {
                return Lf("common.kind_n_songs", L("common.playlist"), playlist.trackCount)
            }
            return Lf("common.system_n_songs", playlist.trackCount)
        }()
        return PlaylistDisplayItem(
            id: playlist.playlistId,
            playlist: playlist,
            title: title,
            subtitle: subtitle,
            cover: cover,
            coverURL: PlaylistCoverStorage.resolveURL(playlist.coverUrlOrPath),
            systemType: playlist.systemType
        )
    }

    static func history(songCount: Int) -> PlaylistDisplayItem {
        PlaylistDisplayItem(
            id: LibraryRoute.history,
            playlist: nil,
            title: L("library.history"),
            subtitle: Lf("common.system_n_songs", songCount),
            cover: .history,
            coverURL: nil,
            systemType: "history"
        )
    }
}

private enum SystemCover {
    case liked, watchLater, history, local, custom
}

private struct SystemCoverView: View {
    let cover: SystemCover
    var url: URL?
    var fillsContainer: Bool = false

    var body: some View {
        coverContent
            .frame(
                width: fillsContainer ? nil : 64,
                height: fillsContainer ? nil : 64
            )
            .frame(maxWidth: fillsContainer ? .infinity : nil, maxHeight: fillsContainer ? .infinity : nil)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: YTLiteLayout.thumbRadius))
    }

    @ViewBuilder
    private var coverContent: some View {
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
                    RemoteImage(url: url, contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                } else {
                    YTLiteColor.surfaceVariant
                    Image(systemName: "music.note.list").foregroundStyle(.white)
                }
            }
        }
    }
}

struct LibrarySongRow: View {
    let item: VideoItem
    var compactLeading: Bool = false
    var onMore: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: YTLiteLayout.stackLoose) {
            VideoThumbnail(
                url: item.thumbnailURL,
                durationText: item.durationText,
                width: YTLiteLayout.channelAvatar,
                height: YTLiteLayout.channelAvatar,
                cornerRadius: 6,
                badgePadding: 2
            )
            VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                Text(item.title)
                    .font(YTLiteType.rowTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(1)
                Text(item.channelName)
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                onMore?()
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.leading, compactLeading ? 0 : YTLiteLayout.screenPadding)
        .padding(.trailing, YTLiteLayout.screenPadding)
        .padding(.vertical, YTLiteLayout.rowVertical)
        .contentShape(Rectangle())
    }
}

struct HistoryDetailView: View {
    var onChange: () -> Void
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @Environment(\.libraryStore) private var store
    @State private var tracks: [VideoItem] = []
    @State private var showPlayer = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if tracks.isEmpty {
                    Text(L("library.no_plays"))
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .padding()
                } else {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, item in
                        Button {
                            playback.play(items: tracks, startAt: index)
                            showPlayer = true
                        } label: {
                            LibrarySongRow(item: item) {
                                trackActions.present(item: item)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(YTLiteColor.background)
        .navigationTitle(L("library.history"))
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(YTLiteColor.background, for: .navigationBar)
        .onAppear { reload() }
        .onChange(of: trackActions.listEpoch) { _, _ in
            reload()
            onChange()
        }
        .sheet(isPresented: $showPlayer) {
            NavigationStack { PlayerDetailView() }
        }
    }

    private func reload() {
        let items = store?.historyVideos() ?? []
        tracks = store?.filterNotInterested(items) ?? items
    }
}

private extension UserSubscribedChannel {
    var asChannelItem: ChannelItem {
        ChannelItem(
            channelId: channelId,
            title: title,
            subtitle: {
                if let subscriberCountText, !subscriberCountText.isEmpty { return subscriberCountText }
                if let handle, !handle.isEmpty { return handle }
                return L("common.channel")
            }(),
            thumbnailURL: avatarUrl.flatMap(URL.init(string:))
        )
    }
}
