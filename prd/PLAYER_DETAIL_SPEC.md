# YTLite: Player Detail Screen UI/UX & Technical Specification

## 0. Product decisions (locked)

| Decision | Value |
|----------|-------|
| Paradigm | **Hybrid** — YouTube video playback + music-style UI copy (歌曲/歌手) |
| RAM threshold | **Fixed 4GB** — `ActivityManager.MemoryInfo.totalMem` |
| Audio power-save | **Pure audio stream** (audio-only itag) + destroy `PlayerView` + cover `RGB_565` + lyrics placeholder |
| Up Next source | InnerTube `/next` via `RelatedVideoParser` + `AdContentFilter`; JS extract fallback when available |
| Queue prefill | **First 20** related items on enter |
| Bottom bar | **Merge** into global `MiniPlayerBar` variant on player screen (`Next:` + swipe-up queue) |
| Fullscreen | **Separate `FullscreenPlayerActivity`**, shared `PlaybackManager` |
| Actions v1 | **Share** + **Save to playlist** (reuse Library `PlaylistPickerSheet`); like/dislike/subscribe/download stub |
| Comments | **Forbidden** — no UI, no network, no parsing |

## 0.1 Non-goals (v1)

- Real lyrics / CC subtitle APIs
- Like / dislike / subscribe / download API integration
- Cast
- Comment loading or preview
- Cloud sync of play queue

## 0.2 Terminology mapping

| UI term | Data semantics |
|---------|----------------|
| 歌曲 / 歌名 | `VideoItem.title` / `NowPlaying.title` |
| 歌手 | `VideoItem.channelName` |
| 封面 | `NowPlaying.thumbnailUrl` / Coil `RGB_565` in audio mode |
| Up Next | Related videos from InnerTube `/next` → `secondaryResults` → `lockupViewModel` |
| 播放队列 | `PlayQueueRepository` → `PlaybackManager` ExoPlayer queue |

---

## 1. Screen topology

Vertical scrollable layout, four blocks:

1. **SmartPlayerCanvas** — dual-mode player (audio power-save / video), top-right mode toggle, CC & Settings stubs, progress overlay, fullscreen
2. **Metadata Panel** — title, expandable description, channel row, horizontal action row
3. **Purified Up Next** — ad-filtered related list, no comments
4. **Player mini bar + queue sheet** — extended `MiniPlayerBar` with `Next:` hint; swipe up for full reorderable queue

---

## 2. Block specifications

### 2.1 SmartPlayerCanvas

**RAM guard (fixed 4GB):**
- On init, read `totalMem`
- `< 4GB` → default `AudioPowerSave`: no `PlayerView`, Coil cover `RGB_565`, lyrics placeholder, **audio-only itag**
- `>= 4GB` → default `Video`: Media3 `PlayerView` hardware decode
- Top-right manual toggle destroys and rebuilds surface (never `GONE` only)

**Overlays:**
- Top-right: mode toggle, CC (stub), Settings (stub)
- Bottom-left: `"3:11 / 3:26"` progress text
- Bottom-right: fullscreen → `FullscreenPlayerActivity`; aspect ratio toggle

### 2.2 Metadata Panel

- Title: bold, max 2 lines, `...more` expands description
- Channel row: avatar, name, subscriber count, black capsule Subscribe (stub)
- Horizontal `LazyRow` actions: Like, Dislike, Share, Save to playlist, Download (stubs except Share + Save)

### 2.3 Purified Up Next

**Data source:** `InnerTubeApi.fetchWatchNext` (`POST /youtubei/v1/next`). YouTube 2025+ returns related items as **`lockupViewModel`** (not legacy `videoRenderer`). Parse path:

`contents.twoColumnWatchNextResults.secondaryResults.secondaryResults.results[]`

**Parser:** `RelatedVideoParser` uses targeted `secondaryResults` roots, then `LockupViewModelParser` + legacy renderer fallback. Exclude current `videoId` from results.

**Ad filter (repository layer):** drop nodes with `compactAdRenderer`, `adSlotRenderer`, `adVideoRenderer`, `promotedVideoRenderer`, or metadata containing `Sponsored` / `promoted`.

**UI:** `LazyColumn` items with stable `videoId` keys; `contentType` for video vs playlist; no comments block.

### 2.4 Queue overlay

- Global `MiniPlayerBar` (Main) and `PlayerMiniBar` (detail) open the same **fullscreen black Overlay** (`ExpandedPlayerQueueOverlay`)
- Layout: ~40% player surface (square art, centered controls, red seek bar) + ~60% queue list
- Queue header: "Play queue" + current track title; Loop / Shuffle / More / Close
- Like / Dislike under current track (local Favorites / Not Interested)
- Cast via system share / wireless display settings; CC loads VTT subtitles; Settings sheet for speed + quality
- Long-press drag reorder → `PlayQueueRepository.reorder()` → `PlaybackManager.syncQueue()`
- Auto-advance on track end via queue (respects repeat mode)

---

## 3. Performance guards

1. Never initialize or fetch comments on player detail
2. Audio mode must **remove** `PlayerView` from composition tree
3. Audio mode must use **audio-only stream**, not hidden video track
4. Icons: vector only, no bitmap action icons

---

## 4. Implementation phases

### Phase 0 — Infrastructure
- `AdContentFilter`, `RelatedVideoParser`, `PlayQueueRepository`
- Extend `PlaybackManager` (multi-item queue, skip, reorder sync)
- `GlobalPlaybackViewModel` auto-next from queue
- `LibraryRepository.addTrackToPlaylist`, `PlaylistPickerSheet`

### Phase 1 — SmartPlayerCanvas
- `SmartPlayerCanvas.kt`, `DeviceRam.kt`, `PlayerSurfaceMode`
- `FullscreenPlayerActivity`

### Phase 2 — Metadata + Up Next
- `PlayerMetadataPanel.kt`, `PurifiedUpNextStream.kt`
- Remove comments from `PlayerScreen`
- Prefill queue with 20 related items

### Phase 3 — Queue sheet
- `SlidingPlayQueueSheet.kt`, `PlayerMiniBar.kt`
- Wire Library play-next / add-to-queue actions
