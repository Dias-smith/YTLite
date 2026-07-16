# 00 — Information Architecture

## Top-level routes

| Route | Destination |
|-------|-------------|
| `main` | `MainScreen` (tabs + overlays) |
| `player/{videoId}` | `PlayerScreen` |

**Entry:** `MainActivity` → `YTLiteNavHost`.

## Bottom tabs (`MainTab`)

| Order | Tab | Screen | Notes |
|------:|-----|--------|-------|
| 1 | Home | `HomeScreen` | Default |
| 2 | Shorts | `ShortsScreen` | WebView |
| 3 | Search | `SearchScreen` | |
| 4 | Subscriptions / YouTube | `SubscriptionsScreen` | Label swaps when authenticated |
| 5 | Library | `LibraryScreen` → `LibraryNavHost` | Nested destinations |

**Chrome:** When `nowPlaying != null`, `MiniPlayerBar` sits above `NavigationBar`.

## Global hosts (always above NavHost)

- `TrackActionHost` — track more / download / lyrics / playlist picker
- `PlaylistActionHost` — playlist more / edit / delete
- Optional channel overlay from player (`ChannelVideosScreen`)

## Main overlays (state in MainScreen, not NavController)

| Overlay | Screen |
|---------|--------|
| YouTube Web login | `YoutubeWebLoginScreen` |
| Account switcher | `AccountSwitcherSheet` |
| All subscription channels | `SubscriptionChannelsScreen` |
| Channel videos | `ChannelVideosScreen` |
| YouTube playlists list | `YoutubePlaylistsListScreen` |
| YouTube playlist items | `YoutubePlaylistItemsScreen` |

## Library destinations

| Destination | Screen |
|-------------|--------|
| Home | `LibraryHomeScreen` |
| History | `HistoryScreen` |
| Playlist(id) | `PlaylistDetailScreen` |
| AlbumTracks(name) | `AlbumTracksScreen` |
| Settings | `SettingsScreen` |
| Downloads | `DownloadsHubScreen` |

## Activities & services

| Component | Role |
|-----------|------|
| `MainActivity` | Portrait launcher; PiP; soft input resize |
| `FullscreenPlayerActivity` | Landscape sensor; PiP; shared `PlaybackManager` |
| `PlaybackService` | MediaSessionService foreground playback |
| `DownloadForegroundService` | dataSync foreground downloads |
| `PipActionReceiver` | PiP prev / play-pause / next |
| `MediaButtonReceiver` | Headset / Bluetooth media keys |

## UX rules

- Leaving player route restores mini player if still playing (no hard stop).
- Switching tabs keeps playback.
- Opening player from mini uses existing `videoId` route.
