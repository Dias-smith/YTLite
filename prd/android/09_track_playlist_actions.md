# 09 — Track & Playlist Actions

## TrackActionBottomSheet

Triggered by More on track rows / player more / related hosts.

| Action | Behavior |
|--------|----------|
| Like / Unlike | Toggle local `favorites` |
| Play next | Insert next in `PlayQueueRepository` |
| Add to queue | Append end |
| Save to library | `PlaylistPickerSheet` / New playlist |
| Edit metadata | `EditTrackMetadataDialog` (title/artist/album/year/thumb) |
| View lyrics | `LyricsBottomSheet` — fetch & show VTT |
| Share | `https://www.youtube.com/watch?v={id}` |
| Not interested | Local block / undo path |
| Remove from queue | When flag set |
| Remove from playlist | When writable parent (not YT-readonly parent) |

### Download (related host)

- Not always a sheet row: download clicks open `DownloadFormatBottomSheet`
- Labels: Music Fast / HQ / High; Video Fast / HD, etc. (itag-driven)
- Respects Settings default format (Ask → show sheet)

### Navigation hooks

- Go to artist/channel
- Go to album (Library album destination) when available

## PlaylistActionBottomSheet

| Action | Enabled when |
|--------|----------------|
| Shuffle play | `trackCount > 0` |
| Edit (rename) | Local non-system `canEdit` |
| Pin / Unpin | Non-History `canPin` |
| Share | Always (YT URL or local title fallback) |
| Delete | Same as edit; confirm dialog |

System Liked / Watch later: no edit/delete; pin allowed except History.

## Playlist picker

- List local playlists + create new
- Used from track save and player Save / batch save list

## Acceptance

- Like adds/removes from Favorites playlist.
- Download format selection enqueues visible Tasks row.
- Lyrics sheet shows text or explicit empty/error.
