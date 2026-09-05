# Apple Watch MVP Scope

> Companion remote for Mixtube on iPhone.  
> Decisions locked in product planning (2026-09).  
> Implement Must first; do **not** add Watch Xcode target until this doc is accepted.

Related: [`IOS_MVP_SCOPE.md`](IOS_MVP_SCOPE.md), [`android/06_player.md`](android/06_player.md), [`android/09_track_playlist_actions.md`](android/09_track_playlist_actions.md).

---

## Product positioning

| Field | Value |
|-------|--------|
| Role | **iPhone companion** — remote control + library/metadata mirror |
| Playback | Audio/video always plays on **iPhone** (`PlaybackController` / AVPlayer) |
| Watch does **not** | Resolve streams, run AVPlayer for content, cache media files, independent Google OAuth |
| Auth on Watch | **Display-only** — reflects iPhone session (signed-in / guest). No sign-in UI on Watch |
| Min OS | **watchOS 10+** (paired with existing iOS 17+ iPhone app) |
| Bundle | Watch app extension of `com.ytlite.player` (exact product name TBD with Xcode target) |

---

## Priority legend

| Tag | Meaning |
|-----|---------|
| **Must** | Required for first shippable Watch companion |
| **Should** | Near-term after Must; same architecture |
| **Later** | Explicitly defer |
| **Skip** | Out of scope for Watch |

---

## Architecture (locked)

```
┌─────────────────────┐     WatchConnectivity      ┌──────────────────────────┐
│  watchOS App        │◄──── commands / state ────►│  iOS App (source of truth)│
│  SwiftUI UI         │     metadata / playlists   │  PlaybackController       │
│  Local mirror cache │                            │  LibraryStore / SwiftData │
│  (metadata only)    │                            │  AuthService session      │
└─────────────────────┘                            └──────────────────────────┘
```

| Principle | Rule |
|-----------|------|
| Source of truth | **iPhone** for playback, queue, library mutations, auth |
| Watch local store | **Metadata + playlist structure only** (titles, artists, thumbs URLs/small images, playlist ids/names, membership). No media binaries |
| Commands | Watch → iPhone: play control + library CRUD intents (**only when phone reachable**) |
| State push | iPhone → Watch: now playing, queue snapshot, repeat/shuffle/speed, library delta, reachability |
| Phone unreachable | **Now Playing / Queue / transport / mutations** blocked with open-Mixtube CTA. **Library** may show **last mirrored snapshot read-only**, with persistent disconnected + readonly chrome |
| Phone killed | Same as unreachable for controls; Library still allows read-only last snapshot if any |
| Phone background | Must remain controllable while iPhone app is backgrounded and audio session active (existing background audio). If process suspended/killed → unreachable path |

Transport: `WatchConnectivity` (`WCSession`) — interactive `sendMessage` when reachable; `transferUserInfo` / `updateApplicationContext` for state; **no** `transferFile` for media in MVP.

---

## Must

### Shell & connectivity

| Area | Requirement |
|------|-------------|
| Watch app shell | Tab or root stack: **Now Playing**, **Library** (playlists / favorites / history), optional **Queue** surface |
| Reachability | Detect iPhone app reachable vs unreachable |
| Unreachable — controls | Now Playing transport, Queue mutations, Share, and all library writes → blocked; primary CTA “请打开 Mixtube” / `L("watch.phone_required")` |
| Unreachable — Library | If a prior mirror exists: browse playlists / favorites / history **read-only**; show clear banner (e.g. “手机未连接 · 只读” / `L("watch.phone_disconnected_readonly")`). No create/rename/delete/like/edit/add/remove. If no snapshot yet → same open-Mixtube empty state |
| Session bootstrap | On appear: request full state snapshot from iPhone (now playing + queue + library mirror + auth display); persist last library mirror locally on Watch |
| Localization | Reuse `L` / `Localizable.xcstrings` keys; add `watch.*` keys |

### Auth (display-only)

| Area | Requirement |
|------|-------------|
| Status | Show signed-in account label or Guest, mirrored from iPhone `AuthService` |
| Actions | **No** Sign in with Apple / Google / logout on Watch |
| Guest | Mirror guest library owner on phone; CRUD still targets phone `LibraryStore` |

### Now Playing & transport (remote)

All actions execute on iPhone `PlaybackController` (or equivalent queue APIs).

| Control | Behavior |
|---------|----------|
| Play / Pause | Toggle |
| Previous / Next | Same as phone |
| Seek / scrub | Position + duration from phone; scrub sends seek command |
| Skip ± (optional UI) | If phone supports; else scrub only |
| Shuffle | Toggle `shuffleEnabled` |
| Repeat | Cycle `QueueRepeatMode`: Off → All → One (same as iOS) |
| Speed | **Must** — set among phone `PlaybackSpeeds` options (0.5…8); show current; sheet or picker on Watch |
| Volume | Prefer system Watch volume for phone audio route when applicable; if app-level volume exists on phone, mirror control |
| Artwork / title / artist | From phone now-playing; thumb may be small transferred image or URL loaded when reachable |
| Live / extracting | Show phone busy/extracting state; disable seek when not seekable |

### Queue

| Area | Requirement |
|------|-------------|
| List | Current queue order + current index highlight |
| Play item | Tap → phone plays that index |
| Remove from queue | Delete row → phone queue remove |
| Play next / Add to end | From track actions when context allows |
| Reorder | **Should** if cheap; else Later |

### Library mirror (metadata + playlists)

| Area | Requirement |
|------|-------------|
| Lists | Playlists (incl. Favorites), History / last played — ids, names, track counts, covers |
| Playlist detail | Track rows: title, artist/channel, thumb, duration if known |
| Sync | Initial snapshot + incremental updates when phone library changes; persist last successful mirror on Watch |
| Connected | Full browse + CRUD enabled |
| Disconnected (Must) | Show last mirror **read-only**; persistent UI chrome: disconnected + readonly (localized). Tap on mutating actions → explain reconnect / open Mixtube, do not no-op silently |
| Stale UI when connected | Mutations optimistic on Watch only if immediately ACK’d by phone; on failure revert + toast |

### Track & playlist CRUD (remote → phone)

Watch UI triggers the **same semantic operations** as iPhone track/playlist actions; phone mutates `LibraryStore` / queue and syncs to Supabase when phone already would.

**Track-level**

| Action | Notes |
|--------|--------|
| Like / Unlike | Favorites playlist toggle |
| Play | Replace/play on phone (context: playlist / history / queue) |
| Play next | Insert next in phone queue |
| Add to queue | Append |
| Save to playlist | Pick local writable playlist on Watch → phone adds |
| Remove from playlist | When parent writable |
| Remove from queue | When in queue context |
| Remove from history / last played | When in history context |
| Edit metadata | **Must** — title / artist / album / year / thumb — sheet on Watch, apply on phone |
| Share | **Must** — hand off to **iPhone system share sheet** (`youtube.com/watch?v=…`). Watch shows in-progress / success / phone-unreachable error. No Watch-only pasteboard fallback required for MVP |
| Not interested | **Must** — same local block / undo semantics as iPhone track action |

**Playlist-level**

| Action | Notes |
|--------|--------|
| Shuffle play | Start playlist on phone with shuffle |
| Create playlist | Name on Watch → phone creates |
| Rename playlist | Writable local only |
| Delete playlist | Confirm on Watch → phone deletes |
| Pin / Unpin | If phone supports |

System playlists (Favorites / History rules): same `canEdit` / `canPin` constraints as iOS.

### iPhone host requirements (Must)

| Area | Requirement |
|------|-------------|
| WCSession delegate | Activate session; handle Watch commands; push state on playback/library/auth changes |
| Background | Keep responding to Watch commands while app is backgrounded with active playback / audio session |
| Kill / not running | Controls unavailable + open-phone CTA; Library may still show last mirror read-only. (Optional Later: Watch wakes phone via `WCSession` — not relied on for MVP acceptance) |
| No stream resolve on Watch | All extract / `PlaybackMediaStore` stays on iPhone |

---

## Should

| Area | Notes |
|------|--------|
| Queue reorder | Drag reorder → phone |
| Complication / Smart Stack | Now Playing deep link into Watch app |
| Haptic on transport | Play/pause/next confirmation |
| Lyrics view | Read-only lyrics if phone already has VTT cached/fetched — low priority |
| Share fallback | If phone share handoff fails repeatedly, optional copy URL on Watch (not required for MVP exit) |

---

## Later

| Area | Notes |
|------|--------|
| Independent Watch playback | AVPlayer on Watch + media transfer / weak resolve |
| Media file sync from `PlaybackMediaStore` | Explicitly out of companion MVP |
| Sign in / logout on Watch | Product chose display-only |
| Search / Home / Shorts / You shelves on Watch | Phone-only discovery |
| Google OAuth on Watch | Not viable UX |
| AdMob on Watch | Skip |

---

## Skip

- Watch stream extraction (`WKWebView` / `resolution.js`)
- Video canvas / PiP on Watch
- Comments
- Download format picker / offline download management on Watch
- Cast

---

## Information architecture (Watch)

```
Now Playing
  ├─ Artwork, title, artist, time
  ├─ Transport: shuffle, prev, play/pause, next, repeat
  ├─ Speed, seek
  └─ Open Queue

Queue
  └─ Rows → play / swipe remove / more

Library
  ├─ [when disconnected] banner: 手机未连接 · 只读
  ├─ Playlists → detail → track rows + more (mutations only when connected)
  ├─ Favorites (shortcut)
  └─ History

Account (banner or settings row)
  └─ Signed-in / Guest (read-only)
```

---

## Protocol sketch (implementation guide)

Not a wire format freeze — implementers may use Codable enums.

**Watch → iPhone (commands)**

- `transport.playPause` / `next` / `previous` / `seek(position)` / `setShuffle` / `cycleRepeat` / `setSpeed`
- `queue.play(index)` / `queue.remove(ids)` / `queue.playNext(track)` / `queue.append(track)`
- `library.like` / `unlike` / `addToPlaylist` / `removeFromPlaylist` / `createPlaylist` / `renamePlaylist` / `deletePlaylist`
- `library.editTrackMetadata` / `removeFromHistory` / `notInterested`
- `share.present(videoId)` — iPhone presents system share sheet
- `sync.requestSnapshot`

**iPhone → Watch (state)**

- `playback.snapshot` — now playing, position, duration, playing, shuffle, repeat, speed, extracting/error
- `queue.snapshot`
- `library.snapshot` or `library.delta`
- `auth.snapshot` — display name / guest flag
- `host.unavailable` — phone app not ready
- `share.result` — presented / failed / unavailable

Payloads stay small (metadata + ids). Thumbnails: URL string preferred; optional tiny JPEG via file transfer only if URL load fails — not required for Must.

---

## Acceptance (MVP exit)

1. iPhone playing (app backgrounded OK) → Watch shows correct now playing → play/pause/next/prev/shuffle/repeat/**speed**/seek work.
2. Watch queue list matches phone; remove / play-next / add-to-queue reflected on phone.
3. Watch Library shows phone playlists + favorites + history metadata; create/rename/delete playlist and add/remove/like/**edit-metadata** / **not interested** on Watch persist on phone (and cloud sync if user already signed in on phone).
4. Share from Watch → iPhone presents system share sheet for the track URL.
5. Watch shows Guest vs signed-in label from phone; **no** login UI on Watch.
6. Force-quit / unreachable iPhone → transport/queue/mutations blocked with open-Mixtube feedback; **Library still browsable read-only** from last snapshot with explicit **disconnected · readonly** labeling; with no snapshot, empty + open-Mixtube.
7. No media files transferred; no stream resolve on Watch.

---

## Implementation phases (suggested)

| Phase | Deliverable |
|-------|-------------|
| **0 — Spec** | This document accepted |
| **1 — Project** | ✅ watchOS 10 target via XcodeGen; shared `YTLiteWatchConnectivity`; iOS embeds Watch in `PlugIns/`; both schemes build |
| **2 — Transport spine** | ✅ playback snapshot push + play/pause/prev/next remote; Watch Now Playing UI |
| **3 — Full transport** | ✅ seek / ±15·+30 / shuffle / repeat / speed picker; volume read-only + crown hint; extracting/error in snapshot |
| **4 — Queue UI** | ✅ queue snapshot; list + play index + swipe remove; play next / move to end |
| **5 — Library mirror** | ✅ library snapshot + persist; playlists/history browse; disconnected readonly banner; play-when-connected |
| **6 — CRUD** | ✅ like/unlike, play next/queue, save/remove playlist, create/rename/delete/pin, edit metadata, not interested, share→iPhone, history remove |
| **7 — Hardening** | ✅ unreachable CTA vs Library/Queue readonly; Watch Localizable (en/zh-Hans); WCSession early activate + background task + transferUserInfo fallback |

Do not start Phase 1 until product signs off this scope.

**MVP implementation status:** Phases 1–7 complete in codebase (companion remote). Remaining work is device QA / polish.

---

## Locked product decisions (changelog)

| Decision | Value |
|----------|--------|
| Auth on Watch | Display-only (1A) |
| Speed / edit metadata / not interested | **Must** |
| Share | Evoke **iPhone** system share sheet |
| Phone unreachable + Library | Last snapshot **read-only** + disconnected/readonly label |
| Min watchOS | 10+ |

## Open implementation notes (non-blocking)

- Exact Watch tab layout (2 vs 3 tabs) left to UI pass; IA above is normative.
- Whether Watch can `WCSession`‑wake a suspended iPhone app is best-effort only; acceptance uses explicit CTA when unreachable for controls.
- Android Wear is **out of scope** for this document.
