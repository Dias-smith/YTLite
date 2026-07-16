# 05 — Library

## Goal

Manage local library (playlists, songs, followed channels), history, downloads entry, and settings access. Design language: YT Music-like chips / list-grid / FAB / sheets.

## Entry

Bottom tab **Library** → `LibraryHomeScreen`.

## Toolbar

| Control | Action |
|---------|--------|
| Profile | AccountSwitcherSheet |
| Settings | `SettingsScreen` |

## Fixed entry (not a chip)

- **Downloads** card/`LibraryDownloadsEntry` → `DownloadsHubScreen`

## Visible chips (`visibleChips`)

| Chip | Content |
|------|---------|
| Playlists | Local playlists including system favorites / watch_later; History row |
| Songs | Deduped tracks across playlists |
| Channels | Local followed / artist channels |

**Hidden chips (as-built):** Albums, YouTube, Downloads chip (downloads uses fixed entry).

## List controls

| Feature | Spec |
|---------|------|
| Sort | Recent activity / Recently saved |
| Playlists reorder mode | Long-press drag reorder display order |
| List / Grid toggle | Yes |
| Multi-select | Select all / add to playlist / batch delete (confirm) |
| FAB | New local playlist (`NewPlaylistDialog`) |
| Songs empty | “Find music” → switch to Home tab |

## Navigation from rows

| Row | Destination |
|-----|-------------|
| History (system) | `HistoryScreen` (monthly groups, local only) |
| Playlist | `PlaylistDetailScreen` |
| Song | Start playback |
| Channel | Channel videos |
| Album (if any) | `AlbumTracksScreen` |
| More on track/playlist/channel | Track/Playlist actions or unfollow dialog |

## Playlist detail

| Feature | Spec |
|---------|------|
| Header | Cover, stats, Play/Pause |
| Edit name | Local editable playlists only |
| Clone to local | YouTube-sourced → LOCAL copy |
| Sort sheet | Manual / Recently added / Title; Manual drag reorder |
| Track more | TrackAction |
| Playlist more | PlaylistAction |

## History

- Source: `user_track_last_played` **local only**
- Grouped by month
- No YouTube cloud watch history

## Downloads hub (from Library entry)

| Tab | Spec |
|-----|------|
| Downloaded (first) | Title, channel, **size · duration**; play; delete |
| Tasks | Status · format label; pause/resume/cancel/retry; progress |

## Acceptance

- Create playlist → add track via picker → appears under Playlists.
- History shows after playback.
- Downloads entry opens hub; downloaded row plays offline when file present.
