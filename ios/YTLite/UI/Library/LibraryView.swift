import SwiftUI

private enum LibraryRoute {
    static let history = "system:history"
    static let imported = "system:imported"
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

    private static let storageKey = "ytlite.library.sortMode"

    /// Newest added first until the user picks another rule.
    static var restored: LibrarySortMode {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let mode = LibrarySortMode(rawValue: raw)
        else { return .recentlySaved }
        return mode
    }

    func persist() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
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
    @State private var libraryPath = NavigationPath()
    @State private var history: [VideoItem] = []
    @EnvironmentObject private var playerPresentation: PlayerPresentation
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Deduped songs from all playlists (+ history-only), Library → Songs tab.
    @State private var songs: [VideoItem] = []
    /// Bumped only when `songs` is replaced — cheap identity for Equatable list panes.
    @State private var songsVersion: Int = 0
    /// Progressive window for Songs List — grows as the user scrolls near the end.
    @State private var songsDisplayLimit: Int = 200
    private static let songsPageSize = 200
    @State private var channels: [UserSubscribedChannel] = []
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var filter: LibraryFilter = .playlists
    @State private var channelPendingUnsubscribe: UserSubscribedChannel?

    @State private var sortMode: LibrarySortMode = .restored
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
    /// After 5s of syncing, collapse the modal into a trailing chip (and keep it for manual retry).
    @State private var preferCompactLibrarySync = false
    @State private var promoteCompactSyncTask: Task<Void, Never>?
    /// Skip the completion toast for non-sync flows that reuse `isLibrarySyncing` (e.g. delete account).
    @State private var suppressSyncCompletionToast = false

    private var showsLibrarySyncModal: Bool {
        appModel.isLibrarySyncing && !preferCompactLibrarySync
    }

    private var showsLibrarySyncChip: Bool {
        auth.isAuthenticated
    }

    @Environment(\.miniPlayerBottomInset) private var miniPlayerBottomInset

    private var libraryListBottomPadding: CGFloat { 80 }

    private var fabBottomPadding: CGFloat {
        YTLiteLayout.screenPadding + miniPlayerBottomInset
    }

    var body: some View {
        NavigationStack(path: $libraryPath) {
            ZStack(alignment: .bottomTrailing) {
                if isReorderMode {
                    // Own scrolling List (not nested in ScrollView) so last rows aren't clipped.
                    VStack(alignment: .leading, spacing: 0) {
                        reorderHeader
                            .padding(.bottom, YTLiteLayout.stackLoose)
                        reorderList
                    }
                } else if filter == .songs, viewMode == .list {
                    // `List` recycles cells; Equatable pane ignores playback publish storms.
                    VStack(spacing: 0) {
                        Group {
                            if isSelectionMode {
                                selectionHeader
                            } else {
                                VStack(alignment: .leading, spacing: YTLiteLayout.screenPadding) {
                                    header
                                    filterChips
                                    listControls
                                }
                            }
                        }
                        LibrarySongsPane(
                            songs: Array(songs.prefix(songsDisplayLimit)),
                            songsVersion: songsVersion,
                            totalCount: songs.count,
                            viewMode: .list,
                            isSelectionMode: isSelectionMode,
                            selectedIds: selectedIds,
                            usesUIKitList: true,
                            onPlay: { index in
                                playback.play(items: songs, startAt: index, analyticsSource: "library")
                                playerPresentation.present()
                            },
                            onToggleSelection: { toggleSelection($0) },
                            onMore: { trackActions.present(item: $0, canDeleteFromLibrary: true) },
                            onLoadMore: { growSongsWindow() }
                        )
                        .equatable()
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            Color.clear.frame(height: libraryListBottomPadding)
                        }
                    }
                    .ytLiteMiniPlayerScrollInset()
                } else {
                    ScrollView {
                        // Single LazyVStack (no nested lazy stacks) so rows stay virtualized.
                        LazyVStack(alignment: .leading, spacing: YTLiteLayout.screenPadding) {
                            if isSelectionMode {
                                selectionHeader
                            } else {
                                header
                                filterChips
                                listControls
                            }
                            flattenedContent
                        }
                        .padding(.bottom, libraryListBottomPadding)
                    }
                    .ytLiteMiniPlayerScrollInset()
                }

                if filter == .playlists, !isSelectionMode, !isReorderMode {
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
                    .padding(.bottom, fabBottomPadding)
                    .disabled(showsLibrarySyncModal)
                }
            }
            .overlay {
                if showsLibrarySyncModal {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { dismissLibrarySyncModal() }
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
                        .padding(.top, 8)
                        .frame(minWidth: 180)
                        .background(
                            YTLiteColor.surfaceElevated,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(alignment: .topTrailing) {
                            Button {
                                dismissLibrarySyncModal()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(6)
                            .accessibilityLabel(L("common.close"))
                        }
                    }
                    .allowsHitTesting(true)
                }
            }
            .ytLiteContentWidth(enabled: YTLiteAdaptive.isRegularWidth(horizontalSizeClass))
            .ytLiteAppBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { destinationId in
                if destinationId == LibraryRoute.history {
                    HistoryDetailView { reload() }
                } else if destinationId == LibraryRoute.imported {
                    ImportedTracksListView(scope: .offlineAll)
                } else if let playlist = playlists.first(where: { $0.playlistId == destinationId }) {
                    PlaylistDetailView(playlist: playlist) { reload() }
                }
            }
            .onAppear {
                reload()
                consumeOfflinePlaylistRequest()
                Task { await store?.refreshOfflinePlaylistFromCache() }
                if appModel.isLibrarySyncing {
                    handleLibrarySyncingChange(true)
                }
            }
            // Store is created asynchronously in RootView.onAppear — refresh once it arrives
            // so Liked / Watch later (from SwiftData) are not stuck missing behind synthetic History.
            .onChange(of: store != nil) { _, hasStore in
                guard hasStore else { return }
                reload()
            }
            .onChange(of: trackActions.listEpoch) { _, _ in reload() }
            .onChange(of: playlistActions.listEpoch) { _, _ in reload() }
            .onChange(of: appModel.libraryRevision) { _, _ in reload() }
            .onChange(of: appModel.pendingOfflinePlaylist) { _, pending in
                if pending { consumeOfflinePlaylistRequest() }
            }
            .onChange(of: playback.isChannelSubscribed) { _, _ in reload() }
            .onChange(of: appModel.isLibrarySyncing) { _, syncing in
                handleLibrarySyncingChange(syncing)
            }
            .onChange(of: auth.isAuthenticated) { _, signedIn in
                if !signedIn {
                    preferCompactLibrarySync = false
                    suppressSyncCompletionToast = false
                    promoteCompactSyncTask?.cancel()
                    promoteCompactSyncTask = nil
                }
            }
            .onChange(of: filter) { _, newFilter in
                exitSelectionMode()
                if newFilter != .playlists { exitReorderMode(save: false) }
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
                    current: activeSort,
                    showsReorderPlaylists: filter == .playlists,
                    onSelect: { selected in
                        sortMode = selected
                        selected.persist()
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
                VStack(spacing: 0) {
                    YTLiteSheetGrabHandle()
                    YTLiteSheetTitle(title: L("library.new_playlist"))

                    Text(L("common.name"))
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, YTLiteLayout.screenPadding)
                        .padding(.bottom, 6)

                    YTLiteSheetField(placeholder: L("common.name"), text: $newPlaylistName)

                    Spacer(minLength: 20)

                    VStack(spacing: 10) {
                        YTLiteSheetPrimaryButton(
                            title: L("common.create"),
                            enabled: !newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ) {
                            let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            _ = store?.createPlaylist(name: name)
                            newPlaylistName = ""
                            showNewPlaylist = false
                            reload()
                        }
                        YTLiteSheetSecondaryButton(title: L("common.cancel")) {
                            newPlaylistName = ""
                            showNewPlaylist = false
                        }
                    }
                    .padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(YTLiteColor.surfaceElevated)
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(YTLiteColor.surfaceElevated)
            }
            .sheet(isPresented: $showDeleteConfirm) {
                VStack(spacing: 0) {
                    YTLiteSheetGrabHandle()
                    YTLiteSheetTitle(
                        title: filter == .channels ? L("library.unsubscribe") : L("common.delete")
                    )

                    Text(deleteConfirmMessage)
                        .font(YTLiteType.body)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, YTLiteLayout.screenPadding)

                    Spacer(minLength: 20)

                    VStack(spacing: 10) {
                        YTLiteSheetPrimaryButton(
                            title: filter == .channels ? L("library.unsubscribe") : L("common.delete"),
                            destructive: true
                        ) {
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
            .sheet(isPresented: $showBatchPlaylistPicker) {
                LibraryPlaylistPickSheet(
                    playlists: playlists.filter {
                        $0.systemType == nil
                            || $0.systemType == SystemPlaylistType.favorites
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

                        SignInOptionsView(auth: auth, analyticsSource: "library") {
                            appModel.syncAuth(auth)
                            showSignInOptions = false
                            reload()
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .background(YTLiteColor.surfaceElevated)
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
                .presentationBackground(YTLiteColor.surfaceElevated)
            }
            .alert(
                L("account.delete_confirm"),
                isPresented: $showDeleteAccountConfirm
            ) {
                Button(L("account.delete"), role: .destructive) {
                    Task { await performDeleteAccount() }
                }
                Button(L("common.cancel"), role: .cancel) {}
            } message: {
                Text(L("account.delete_message"))
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
        HStack(alignment: .center, spacing: YTLiteLayout.stackLoose) {
            Text(L("library.title"))
                .font(YTLiteType.pageTitle)
                .foregroundStyle(YTLiteColor.onSurface)
            Spacer(minLength: 0)
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
            Spacer(minLength: 8)
            if showsLibrarySyncChip {
                librarySyncChip
            }
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
    }

    private var librarySyncChip: some View {
        Button {
            requestLibrarySync()
        } label: {
            Group {
                if appModel.isLibrarySyncing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(YTLiteColor.accent)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(appModel.isLibrarySyncing)
        .accessibilityLabel(L("library.syncing"))
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

            if showsMultiSelectControl {
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

    /// Edit/select control — playlists only when at least one user-created playlist exists
    /// (system rows Liked / Watch later / History are not multi-selectable).
    private var showsMultiSelectControl: Bool {
        switch filter {
        case .playlists:
            return displayedPlaylists.contains(where: \.isSelectable)
        case .songs:
            return !displayedSongs.isEmpty
        case .channels:
            return !displayedChannels.isEmpty
        }
    }

    private var displayedPlaylists: [PlaylistDisplayItem] {
        orderedPlaylistItems()
    }

    private var displayedSongs: [VideoItem] { songs }

    /// Saved rule when this tab supports it. Otherwise newest-added.
    private var activeSort: LibrarySortMode {
        if sortOptions(for: filter).contains(sortMode) { return sortMode }
        if filter == .playlists, sortMode == .custom { return .custom }
        return .recentlySaved
    }

    private var displayedChannels: [UserSubscribedChannel] {
        switch activeSort {
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
        switch activeSort {
        case .recentActivity, .custom: return .recentActivity
        case .recentlySaved: return .recentlySaved
        case .title: return .title
        case .duration: return .duration
        }
    }

    /// Emits rows as siblings of the outer `LazyVStack` (avoids nested lazy stacks).
    @ViewBuilder
    private var flattenedContent: some View {
        switch filter {
        case .playlists:
            playlistContent
        case .songs:
            // Isolated from PlaybackController `@Published` churn while audio is playing.
            LibrarySongsPane(
                songs: Array(songs.prefix(songsDisplayLimit)),
                songsVersion: songsVersion,
                totalCount: songs.count,
                viewMode: viewMode,
                isSelectionMode: isSelectionMode,
                selectedIds: selectedIds,
                usesUIKitList: false,
                onPlay: { index in
                    playback.play(items: songs, startAt: index, analyticsSource: "library")
                    playerPresentation.present()
                },
                onToggleSelection: { toggleSelection($0) },
                onMore: { trackActions.present(item: $0, canDeleteFromLibrary: true) },
                onLoadMore: { growSongsWindow() }
            )
            .equatable()
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
                columns: [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 12)],
                spacing: 12
            ) {
                ForEach(items, id: \.channelId) { channel in
                    channelGridCell(channel)
                }
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
        } else {
            ForEach(items, id: \.channelId) { channel in
                channelListRow(channel)
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
                columns: [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 12)],
                spacing: 12
            ) {
                ForEach(items) { item in
                    playlistGridCell(item)
                }
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
        } else {
            ForEach(items) { item in
                playlistRow(item)
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
                    // Synthetic system rows (Imported / History).
                    NavigationLink(value: item.id) {
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
        .ytLiteMiniPlayerScrollInset()
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
                case .imported: return .imported
                default: return .custom
                }
            }()
            playlistActions.present(
                .from(playlist: playlist, title: item.title, coverKind: kind)
            )
        } else if item.id == LibraryRoute.history {
            playlistActions.present(.history())
        } else if item.id == LibraryRoute.imported {
            playlistActions.present(.imported())
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
                NavigationLink(value: item.id) {
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
        guard showsMultiSelectControl else { return }
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
            LibrarySortMode.custom.persist()
        }
        isReorderMode = false
        reorderItems = []
    }

    private func moveReorderItems(from source: IndexSet, to destination: Int) {
        reorderItems.move(fromOffsets: source, toOffset: destination)
    }

    /// Hide the blocking card. Sync keeps running and the filter-bar chip stays visible.
    private func dismissLibrarySyncModal() {
        promoteCompactSyncTask?.cancel()
        promoteCompactSyncTask = nil
        preferCompactLibrarySync = true
    }

    private func handleLibrarySyncingChange(_ syncing: Bool) {
        if syncing {
            promoteCompactSyncTask?.cancel()
            if preferCompactLibrarySync { return }

            let started = appModel.librarySyncStartedAt ?? Date()
            let elapsed = Date().timeIntervalSince(started)
            if elapsed >= 5 {
                preferCompactLibrarySync = true
                return
            }

            let remainingNs = UInt64((5 - elapsed) * 1_000_000_000)
            promoteCompactSyncTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: remainingNs)
                guard !Task.isCancelled, appModel.isLibrarySyncing else { return }
                preferCompactLibrarySync = true
            }
        } else {
            promoteCompactSyncTask?.cancel()
            promoteCompactSyncTask = nil
            // Sync / owner switch may have rewritten playlists — refresh Liked / Watch later / customs.
            reload()
            if suppressSyncCompletionToast {
                suppressSyncCompletionToast = false
            } else if auth.isAuthenticated {
                trackActions.showToast(L("toast.library_synced"))
            }
        }
    }

    private func requestLibrarySync() {
        guard auth.isAuthenticated, let store, !appModel.isLibrarySyncing else { return }
        preferCompactLibrarySync = true
        Task {
            let t0 = SyncProbe.now()
            AppAnalytics.librarySyncStart(source: "manual")
            appModel.beginLibrarySync()
            defer {
                AppAnalytics.librarySyncEnd(ok: true, ms: SyncProbe.ms(since: t0))
                appModel.endLibrarySync()
            }
            await LibrarySyncService(auth: auth).syncBidirectional(store: store)
            reload()
        }
    }

    private func performDeleteAccount() async {
        guard let store, let userId = auth.userId else {
            deleteAccountError = "Not signed in"
            return
        }
        let userKey = OwnerKeyStore.userOwnerKey(userId: userId)
        suppressSyncCompletionToast = true
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

    private func consumeOfflinePlaylistRequest() {
        guard appModel.pendingOfflinePlaylist else { return }
        appModel.pendingOfflinePlaylist = false
        libraryPath.append(LibraryRoute.imported)
    }

    private func reload() {
        // Liked / Watch later are persisted system playlists; ensure they exist for this owner.
        store?.ensureSystemPlaylists()
        playlists = store?.allPlaylists() ?? []
        let items = store?.historyVideos() ?? []
        history = store?.filterNotInterested(items) ?? items
        // `librarySongs` already applies metadata in one pass — only strip not-interested.
        let songItems = store?.librarySongs(sort: songSort) ?? []
        let nextSongs = store?.excludingNotInterested(songItems) ?? songItems
        // Include artist + artwork so Edit Info refresh invalidates Equatable song rows.
        let nextFingerprint = nextSongs.map {
            "\($0.videoId)|\($0.title)|\($0.channelName)|\($0.thumbnailURL?.absoluteString ?? "")"
        }
        let prevFingerprint = songs.map {
            "\($0.videoId)|\($0.title)|\($0.channelName)|\($0.thumbnailURL?.absoluteString ?? "")"
        }
        if nextFingerprint != prevFingerprint {
            songsVersion &+= 1
            songsDisplayLimit = Self.songsPageSize
        }
        songs = nextSongs
        channels = store?.allSubscribedChannels() ?? []
    }

    private func growSongsWindow() {
        guard songsDisplayLimit < songs.count else { return }
        songsDisplayLimit = min(songs.count, songsDisplayLimit + Self.songsPageSize)
        songsVersion &+= 1
    }

    private func orderedPlaylistItems() -> [PlaylistDisplayItem] {
        let mapped = playlists.map { PlaylistDisplayItem.playlist($0) }
        let importedCount = store?.offlinePlaylistTracks().count ?? 0
        let importedItem = PlaylistDisplayItem.imported(songCount: importedCount)
        let historyItem = PlaylistDisplayItem.history(songCount: history.count)
        let all = mapped + [importedItem, historyItem]

        switch activeSort {
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
                .sorted { ($0.playlist?.sortCreatedAt ?? .distantPast) > ($1.playlist?.sortCreatedAt ?? .distantPast) }
            return system + custom
        case .title:
            let system = defaultSystemBlock(all)
            let custom = all.filter { $0.systemType == nil }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return system + custom
        }
    }

    /// Liked → Watch later → Imported → History → custom (created oldest → newest).
    private func defaultOrdered(_ items: [PlaylistDisplayItem]) -> [PlaylistDisplayItem] {
        defaultSystemBlock(items) + customPlaylistsAscending(items)
    }

    private func defaultSystemBlock(_ items: [PlaylistDisplayItem]) -> [PlaylistDisplayItem] {
        let liked = items.filter { $0.systemType == SystemPlaylistType.favorites }
        let importedRows = items.filter { $0.id == LibraryRoute.imported }
        let historyRows = items.filter { $0.id == LibraryRoute.history }
        return liked + importedRows + historyRows
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
        case SystemPlaylistType.imported, "imported": return 2
        case "history": return 3
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

struct LibraryPlaylistPickSheet: View {
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

    static func imported(songCount: Int) -> PlaylistDisplayItem {
        PlaylistDisplayItem(
            id: LibraryRoute.imported,
            playlist: nil,
            title: L("import.list.title"),
            subtitle: Lf("common.system_n_songs", songCount),
            cover: .imported,
            coverURL: nil,
            systemType: SystemPlaylistType.imported
        )
    }
}

private enum SystemCover {
    case liked, watchLater, history, imported, local, custom
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
            case .imported:
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.55, blue: 0.52),
                        Color(red: 0.08, green: 0.35, blue: 0.48),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "square.and.arrow.down").foregroundStyle(.white)
            case .local:
                YTLiteColor.surfaceVariant
                Image(systemName: "music.note.list")
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            case .custom:
                if let url {
                    RemoteImage(url: url, contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                } else {
                    YTLiteColor.surfaceVariant
                    Image(systemName: "music.note.list")
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                }
            }
        }
    }
}

/// Songs list pane that ignores `PlaybackController` publish storms (buffering / nowPlaying).
private struct LibrarySongsPane: View, Equatable {
    let songs: [VideoItem]
    let songsVersion: Int
    let totalCount: Int
    let viewMode: LibraryViewMode
    let isSelectionMode: Bool
    let selectedIds: Set<String>
    /// When true, use `List` cell recycling (primary path for large song libraries).
    let usesUIKitList: Bool
    let onPlay: (Int) -> Void
    let onToggleSelection: (String) -> Void
    let onMore: (VideoItem) -> Void
    let onLoadMore: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.songsVersion == rhs.songsVersion
            && lhs.totalCount == rhs.totalCount
            && lhs.viewMode == rhs.viewMode
            && lhs.isSelectionMode == rhs.isSelectionMode
            && lhs.selectedIds == rhs.selectedIds
            && lhs.usesUIKitList == rhs.usesUIKitList
    }

    var body: some View {
        if songs.isEmpty {
            Text(L("library.no_plays"))
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if viewMode == .grid {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 12)],
                spacing: 12
            ) {
                ForEach(Array(songs.enumerated()), id: \.element.videoId) { index, item in
                    songGridCell(item, index: index)
                        .onAppear { maybeLoadMore(index: index) }
                }
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
        } else if usesUIKitList {
            // No nested `ytLiteAppBackground()` — parent Library already owns the canvas.
            // Opaque row fills would clip the shared image and create a header/list seam.
            List {
                ForEach(Array(songs.enumerated()), id: \.element.videoId) { index, item in
                    songListRow(item, index: index)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .onAppear { maybeLoadMore(index: index) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        } else {
            ForEach(Array(songs.enumerated()), id: \.element.videoId) { index, item in
                songListRow(item, index: index)
                    .onAppear { maybeLoadMore(index: index) }
            }
        }
    }

    private func maybeLoadMore(index: Int) {
        guard songs.count < totalCount else { return }
        // Prefetch when within one page of the end of the visible window.
        if index >= songs.count - 40 {
            onLoadMore()
        }
    }

    @ViewBuilder
    private func songListRow(_ item: VideoItem, index: Int) -> some View {
        let selected = selectedIds.contains(item.videoId)
        Button {
            if isSelectionMode {
                onToggleSelection(item.videoId)
            } else {
                onPlay(index)
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
                        onMore(item)
                    }
                }
                .equatable()
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func songGridCell(_ item: VideoItem, index: Int) -> some View {
        let selected = selectedIds.contains(item.videoId)
        Button {
            if isSelectionMode {
                onToggleSelection(item.videoId)
            } else {
                onPlay(index)
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
                HStack(spacing: 4) {
                    Text(item.channelName)
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .lineLimit(1)
                    #if targetEnvironment(macCatalyst)
                    Spacer(minLength: 4)
                    MacSongCacheButton(
                        videoId: item.videoId,
                        thumbnailURL: item.thumbnailURL,
                        isLive: item.isLive
                    )
                    #endif
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LibrarySongRow: View, Equatable {
    let item: VideoItem
    var compactLeading: Bool = false
    var onMore: (() -> Void)? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.compactLeading == rhs.compactLeading
    }

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
            MacSongCacheSlot(videoId: item.videoId, thumbnailURL: item.thumbnailURL, isLive: item.isLive) {
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
        }
        .padding(.leading, compactLeading ? 0 : YTLiteLayout.screenPadding)
        .padding(.trailing, YTLiteLayout.screenPadding)
        .padding(.vertical, YTLiteLayout.rowVertical)
        .contentShape(Rectangle())
    }
}

// MARK: - History list filters (duration + progress)

enum HistoryProgressFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case under10
    case from10To50
    case from50To80
    case over80

    var id: String { rawValue }

    var title: String {
        switch self {
        case .under10: return L("library.history.filter.progress.under_10")
        case .from10To50: return L("library.history.filter.progress.10_50")
        case .from50To80: return L("library.history.filter.progress.50_80")
        case .over80: return L("library.history.filter.progress.over_80")
        }
    }

    func matches(fraction: Double) -> Bool {
        let percent = fraction * 100
        switch self {
        case .under10: return percent < 10
        case .from10To50: return percent >= 10 && percent < 50
        case .from50To80: return percent >= 50 && percent <= 80
        case .over80: return percent > 80
        }
    }
}

struct HistoryListFilter: Equatable, Sendable {
    var durations: Set<HomeDurationFilter>
    var progress: Set<HistoryProgressFilter>

    static let `default` = HistoryListFilter(durations: [], progress: [])

    var isActive: Bool {
        !durations.isEmpty || !progress.isEmpty
    }

    func matches(_ entry: HistoryDisplayItem) -> Bool {
        if !durations.isEmpty {
            let seconds = entry.durationSeconds > 0
                ? entry.durationSeconds
                : DurationFormat.seconds(from: entry.item.durationText)
            guard durations.contains(where: { $0.matches(seconds: seconds) }) else { return false }
        }
        if !progress.isEmpty {
            guard progress.contains(where: { $0.matches(fraction: entry.progressFraction) }) else {
                return false
            }
        }
        return true
    }
}

private struct HistoryListFilterSheet: View {
    @State private var draft: HistoryListFilter
    let onApply: (HistoryListFilter) -> Void
    let onCancel: () -> Void

    init(
        filter: HistoryListFilter,
        onApply: @escaping (HistoryListFilter) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: filter)
        self.onApply = onApply
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: YTLiteLayout.sectionGap) {
                    filterSection(title: L("home.filter.duration")) {
                        durationOptions
                    }
                    filterSection(title: L("library.history.filter.progress")) {
                        progressOptions
                    }
                }
                .padding(.horizontal, YTLiteLayout.screenPadding)
                .padding(.top, YTLiteLayout.stackLoose)
                .padding(.bottom, YTLiteLayout.sectionGap)
            }
            .background(YTLiteColor.surfaceElevated)
            .navigationTitle(L("library.history.filter.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.cancel"), action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("home.filter.reset")) {
                        draft = .default
                    }
                    .disabled(!draft.isActive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.done")) {
                        onApply(draft)
                    }
                    .font(YTLiteType.labelEmphasized)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(YTLiteColor.surfaceElevated)
    }

    private func filterSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: YTLiteLayout.stackLoose) {
            Text(title)
                .font(YTLiteType.sectionTitle)
                .foregroundStyle(YTLiteColor.onSurface)
            content()
        }
    }

    private var durationOptions: some View {
        HomeFilterFlowLayout(spacing: YTLiteLayout.stackDefault) {
            filterChip(
                title: L("home.filter.duration.any"),
                selected: draft.durations.isEmpty
            ) {
                draft.durations = []
            }
            ForEach(HomeDurationFilter.allCases) { option in
                filterChip(
                    title: option.title,
                    selected: draft.durations.contains(option)
                ) {
                    toggleDuration(option)
                }
            }
        }
    }

    private var progressOptions: some View {
        HomeFilterFlowLayout(spacing: YTLiteLayout.stackDefault) {
            filterChip(
                title: L("library.history.filter.progress.any"),
                selected: draft.progress.isEmpty
            ) {
                draft.progress = []
            }
            ForEach(HistoryProgressFilter.allCases) { option in
                filterChip(
                    title: option.title,
                    selected: draft.progress.contains(option)
                ) {
                    toggleProgress(option)
                }
            }
        }
    }

    private func filterChip(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(selected ? YTLiteType.labelEmphasized : YTLiteType.label)
                .foregroundStyle(selected ? YTLiteColor.onAccent : YTLiteColor.onSurface)
                .padding(.horizontal, YTLiteLayout.chipHorizontal)
                .padding(.vertical, YTLiteLayout.chipVertical)
                .background(
                    selected ? YTLiteColor.accent : YTLiteColor.surfaceChip,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleDuration(_ option: HomeDurationFilter) {
        if draft.durations.contains(option) {
            draft.durations.remove(option)
        } else {
            draft.durations.insert(option)
        }
    }

    private func toggleProgress(_ option: HistoryProgressFilter) {
        if draft.progress.contains(option) {
            draft.progress.remove(option)
        } else {
            draft.progress.insert(option)
        }
    }
}

/// Library → History: search filter, multi-select delete, listen progress bars.
struct HistoryDetailView: View {
    var onChange: () -> Void

    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var trackActions: TrackActionPresenter
    @EnvironmentObject private var playerPresentation: PlayerPresentation
    @Environment(\.libraryStore) private var store

    @State private var entries: [HistoryDisplayItem] = []
    @State private var entriesVersion: Int = 0
    @State private var filterText: String = ""
    @State private var listFilter: HistoryListFilter = .default
    @State private var isSelectionMode = false
    @State private var selectedIds: Set<String> = []
    @State private var showDeleteConfirm = false
    @State private var showBatchPlaylistPicker = false
    @State private var showListFilter = false
    @State private var lastHistoryReloadAt: Date = .distantPast
    @State private var pendingHistoryReloadTask: Task<Void, Never>?

    private var historyEpoch: Int {
        store?.historyEpoch ?? 0
    }

    private var filteredEntries: [HistoryDisplayItem] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            if listFilter.isActive, !listFilter.matches(entry) {
                return false
            }
            guard !query.isEmpty else { return true }
            return entry.item.title.localizedCaseInsensitiveContains(query)
                || entry.item.channelName.localizedCaseInsensitiveContains(query)
        }
    }

    private var batchTargetPlaylists: [LibraryPlaylist] {
        (store?.allPlaylists() ?? []).filter {
            $0.systemType == nil
                || $0.systemType == SystemPlaylistType.favorites
        }
    }

    var body: some View {
        // Keep Observation subscribed to history mutations while this screen is visible.
        let observedHistoryEpoch = historyEpoch
        VStack(spacing: 0) {
            if isSelectionMode {
                selectionHeader
                    .padding(.bottom, YTLiteLayout.stackTight)
            } else {
                filterField
                    .padding(.bottom, YTLiteLayout.stackTight)
                listControls
                    .padding(.bottom, YTLiteLayout.stackTight)
            }

            HistoryTracksPane(
                entries: filteredEntries,
                entriesVersion: entriesVersion,
                filterText: filterText,
                isSelectionMode: isSelectionMode,
                selectedIds: selectedIds,
                onPlay: { index in
                    let queue = filteredEntries.map(\.item)
                    playback.play(items: queue, startAt: index, analyticsSource: "library")
                    playerPresentation.present()
                },
                onToggleSelection: toggleSelection,
                onMore: { trackActions.present(item: $0, canRemoveFromHistory: true) },
                onDelete: removeFromHistory,
                onRefresh: {
                    await refreshHistory()
                }
            )
            .equatable()
        }
        .ytLiteAppBackground()
        .ytLiteMiniPlayerScrollInset()
        .navigationTitle(L("library.history"))
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(YTLiteColor.background, for: .navigationBar)
        .onAppear {
            // Entering History always reloads once immediately.
            requestHistoryReload(force: true, notifyParent: true)
        }
        .onDisappear {
            pendingHistoryReloadTask?.cancel()
            pendingHistoryReloadTask = nil
        }
        .onChange(of: observedHistoryEpoch) { _, _ in
            requestHistoryReload(force: false, notifyParent: true)
        }
        .onChange(of: trackActions.listEpoch) { _, _ in
            // Metadata / not-interested edits that affect History rows — force so Edit Info isn't throttled.
            requestHistoryReload(force: true, notifyParent: true)
        }
        .onChange(of: filterText) { _, _ in
            selectedIds = selectedIds.intersection(Set(filteredEntries.map(\.id)))
        }
        .onChange(of: listFilter) { _, _ in
            selectedIds = selectedIds.intersection(Set(filteredEntries.map(\.id)))
        }
        .sheet(isPresented: $showDeleteConfirm) {
            VStack(spacing: 0) {
                YTLiteSheetGrabHandle()
                YTLiteSheetTitle(title: L("common.delete"))
                Text(Lf("library.history.remove_n", selectedIds.count))
                    .font(YTLiteType.body)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, YTLiteLayout.screenPadding)
                Spacer(minLength: 20)
                VStack(spacing: 10) {
                    YTLiteSheetPrimaryButton(title: L("common.delete"), destructive: true) {
                        removeFromHistory(Array(selectedIds))
                        showDeleteConfirm = false
                        exitSelectionMode()
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
        .sheet(isPresented: $showBatchPlaylistPicker) {
            LibraryPlaylistPickSheet(
                playlists: batchTargetPlaylists,
                title: L("library.add_to_playlist"),
                displayName: historyPlaylistDisplayName,
                onSelect: { playlist in
                    addSelectedToPlaylist(playlist)
                    showBatchPlaylistPicker = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(YTLiteColor.surfaceElevated)
        }
        .sheet(isPresented: $showListFilter) {
            HistoryListFilterSheet(
                filter: listFilter,
                onApply: { next in
                    listFilter = next
                    showListFilter = false
                },
                onCancel: { showListFilter = false }
            )
        }
    }

    private var filterField: some View {
        HStack(spacing: YTLiteLayout.stackDefault) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            TextField(
                "",
                text: $filterText,
                prompt: Text(L("library.history.search"))
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            )
            .font(YTLiteType.body)
            .foregroundStyle(YTLiteColor.onSurface)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.vertical, 10)
        .background(YTLiteColor.surfaceVariant, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, YTLiteLayout.screenPadding)
        .padding(.top, YTLiteLayout.stackTight)
    }

    private var listControls: some View {
        HStack {
            Text(Lf("common.n_items", filteredEntries.count))
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            Spacer()
            if !entries.isEmpty {
                Button {
                    showListFilter = true
                } label: {
                    Image(
                        systemName: listFilter.isActive
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                    .foregroundStyle(
                        listFilter.isActive ? YTLiteColor.accent : YTLiteColor.onSurfaceVariant
                    )
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("library.history.filter.title"))

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

    private func historyPlaylistDisplayName(_ playlist: LibraryPlaylist) -> String {
        switch playlist.systemType {
        case SystemPlaylistType.favorites: return L("library.liked")
        case SystemPlaylistType.watchLater: return L("library.watch_later")
        default: return playlist.name
        }
    }

    private func addSelectedToPlaylist(_ playlist: LibraryPlaylist) {
        guard let store else { return }
        for videoId in selectedIds {
            if let item = entries.first(where: { $0.id == videoId })?.item {
                store.add(item: item, to: playlist)
            }
        }
        exitSelectionMode()
        onChange()
        trackActions.notifyListsChanged()
    }

    private func removeFromHistory(_ ids: [String]) {
        store?.removeLastPlayed(trackIds: ids)
        // historyEpoch will also fire; force keeps the list snappy after an explicit delete.
        requestHistoryReload(force: true, notifyParent: true)
        trackActions.notifyListsChanged()
    }

    @MainActor
    private func refreshHistory() async {
        // Brief yield so the system refresh spinner is visible even for fast local reloads.
        try? await Task.sleep(nanoseconds: 250_000_000)
        requestHistoryReload(force: true, notifyParent: true)
    }

    /// Reloads History. `force` bypasses the 1s throttle (enter / pull-to-refresh / local delete).
    private func requestHistoryReload(force: Bool, notifyParent: Bool) {
        if force {
            pendingHistoryReloadTask?.cancel()
            pendingHistoryReloadTask = nil
            reload(force: true)
            lastHistoryReloadAt = .now
            if notifyParent { onChange() }
            return
        }

        let elapsed = Date.now.timeIntervalSince(lastHistoryReloadAt)
        if elapsed >= 1.0 {
            pendingHistoryReloadTask?.cancel()
            pendingHistoryReloadTask = nil
            reload(force: false)
            lastHistoryReloadAt = .now
            if notifyParent { onChange() }
            return
        }

        let delay = 1.0 - elapsed
        pendingHistoryReloadTask?.cancel()
        pendingHistoryReloadTask = Task { @MainActor in
            let ns = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled else { return }
            reload(force: false)
            lastHistoryReloadAt = .now
            if notifyParent { onChange() }
            pendingHistoryReloadTask = nil
        }
    }

    private func reload(force: Bool = false) {
        let raw = store?.historyDisplayItems() ?? []
        let next = store.map { store in
            raw.filter { !store.isNotInterested(videoId: $0.item.videoId) }
        } ?? raw
        // Include title/artist/artwork so Edit Info invalidates the Equatable History pane.
        let fingerprint = next.map {
            "\($0.id):\($0.progressMs):\($0.durationSeconds):\($0.lastPlayedAt.timeIntervalSince1970)|\($0.item.title)|\($0.item.channelName)|\($0.item.thumbnailURL?.absoluteString ?? "")"
        }
        let previous = entries.map {
            "\($0.id):\($0.progressMs):\($0.durationSeconds):\($0.lastPlayedAt.timeIntervalSince1970)|\($0.item.title)|\($0.item.channelName)|\($0.item.thumbnailURL?.absoluteString ?? "")"
        }
        if force || fingerprint != previous {
            entriesVersion &+= 1
        }
        entries = next
        selectedIds = selectedIds.intersection(Set(next.map(\.id)))
    }
}

private struct HistoryTracksPane: View, Equatable {
    let entries: [HistoryDisplayItem]
    let entriesVersion: Int
    let filterText: String
    let isSelectionMode: Bool
    let selectedIds: Set<String>
    let onPlay: (Int) -> Void
    let onToggleSelection: (String) -> Void
    let onMore: (VideoItem) -> Void
    let onDelete: ([String]) -> Void
    let onRefresh: () async -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entriesVersion == rhs.entriesVersion
            && lhs.filterText == rhs.filterText
            && lhs.isSelectionMode == rhs.isSelectionMode
            && lhs.selectedIds == rhs.selectedIds
            && lhs.entries.map(\.id) == rhs.entries.map(\.id)
    }

    var body: some View {
        if entries.isEmpty {
            ScrollView {
                Text(
                    filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? L("library.no_plays")
                        : L("library.history.no_matches")
                )
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .padding()
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .refreshable { await onRefresh() }
        } else {
            List {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    historyRow(entry, index: index)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onDelete { offsets in
                    guard !isSelectionMode else { return }
                    let ids = offsets.map { entries[$0].id }
                    onDelete(ids)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await onRefresh() }
        }
    }

    @ViewBuilder
    private func historyRow(_ entry: HistoryDisplayItem, index: Int) -> some View {
        let selected = selectedIds.contains(entry.id)
        Button {
            if isSelectionMode {
                onToggleSelection(entry.id)
            } else {
                onPlay(index)
            }
        } label: {
            HStack(spacing: YTLiteLayout.stackLoose) {
                if isSelectionMode {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? YTLiteColor.accent : YTLiteColor.onSurfaceVariant)
                        .padding(.leading, YTLiteLayout.screenPadding)
                }
                HistorySongRow(
                    entry: entry,
                    compactLeading: isSelectionMode,
                    showsMore: !isSelectionMode,
                    onMore: { onMore(entry.item) }
                )
            }
        }
        .buttonStyle(.plain)
    }
}

private struct HistorySongRow: View {
    let entry: HistoryDisplayItem
    var compactLeading: Bool = false
    var showsMore: Bool = true
    var onMore: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: YTLiteLayout.stackLoose) {
            VideoThumbnail(
                url: entry.item.thumbnailURL,
                durationText: entry.item.durationText,
                width: YTLiteLayout.channelAvatar,
                height: YTLiteLayout.channelAvatar,
                cornerRadius: 6,
                badgePadding: 2
            )
            VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                Text(entry.item.title)
                    .font(YTLiteType.rowTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .lineLimit(1)
                Text(entry.item.channelName)
                    .font(YTLiteType.meta)
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    .lineLimit(1)
                progressBar
            }
            Spacer(minLength: 0)
            if showsMore {
                MacSongCacheSlot(
                    videoId: entry.item.videoId,
                    thumbnailURL: entry.item.thumbnailURL,
                    isLive: entry.item.isLive
                ) {
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
            }
        }
        .padding(.leading, compactLeading ? 0 : YTLiteLayout.screenPadding)
        .padding(.trailing, YTLiteLayout.screenPadding)
        .padding(.vertical, YTLiteLayout.rowVertical)
        .contentShape(Rectangle())
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(YTLiteColor.miniProgressTrack)
                Capsule()
                    .fill(YTLiteColor.accent)
                    .frame(width: geo.size.width * entry.progressFraction)
            }
        }
        .frame(height: max(3, YTLiteLayout.miniProgressHeight + 1))
        .opacity(entry.hasProgress || entry.durationSeconds > 0 ? 1 : 0.35)
        .accessibilityLabel(L("library.history.progress"))
        .accessibilityValue("\(Int((entry.progressFraction * 100).rounded()))%")
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
