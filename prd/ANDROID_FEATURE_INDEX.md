# YTLite Android — As-Built Feature Index

> **Status:** As-built baseline (code truth)  
> **Audience:** Product / iOS engineering  
> **Last calibrated:** 2026-07-15 against `app/` sources  

This index is the **single product source of truth** for what Android ships today. Module specs live under [`prd/android/`](android/). Older specs ([`PLAYER_DETAIL_SPEC.md`](PLAYER_DETAIL_SPEC.md), [`LIBRARY_UI_SPEC.md`](LIBRARY_UI_SPEC.md), [`SEARCH_TAB_SPEC.md`](SEARCH_TAB_SPEC.md)) are historical; deviations are listed in §5.

iOS scope mapping: [`IOS_MVP_SCOPE.md`](IOS_MVP_SCOPE.md).

---

## 1. Product summary

YTLite is a hybrid YouTube video + music-style client on Android:

- Browse / search / open videos without the official app chrome clutter in several surfaces
- Local library (playlists, likes, history) with optional Supabase cloud sync after Google sign-in
- Optional YouTube OAuth + Web cookie for “You” shelves and authenticated InnerTube
- Offline downloads (device-local) and background Media3 playback
- No comments, no AdMob, no real Cast SDK

**Package:** `com.ytlite.player` · **minSdk 24** · **Compose Material3**

---

## 2. Document map

| Doc | Contents |
|-----|----------|
| [android/00_information_architecture.md](android/00_information_architecture.md) | Tabs, routes, overlays, Activities, Services |
| [android/01_home.md](android/01_home.md) | Home feed & category chips |
| [android/02_shorts.md](android/02_shorts.md) | Embedded Shorts WebView |
| [android/03_search.md](android/03_search.md) | Search state machine |
| [android/04_subscriptions_you.md](android/04_subscriptions_you.md) | Sign-in wall, You page, channels & YT playlists |
| [android/05_library.md](android/05_library.md) | Library home, history, playlist/album, downloads entry |
| [android/06_player.md](android/06_player.md) | Detail / fullscreen / PiP / mini / speed / actions |
| [android/07_auth_accounts.md](android/07_auth_accounts.md) | Guest, Google→Supabase, cookie, channel switch |
| [android/08_settings.md](android/08_settings.md) | All settings rows |
| [android/09_track_playlist_actions.md](android/09_track_playlist_actions.md) | Action sheets, download format, lyrics |
| [android/10_sync_download_domain.md](android/10_sync_download_domain.md) | Sync boundaries, download/offline, prefs keys |
| [android/11_ui_ux_patterns.md](android/11_ui_ux_patterns.md) | Theme, language, lists, empty/error, gestures |

---

## 3. Feature inventory (checklist)

### Shell

- [x] 5 bottom tabs + MiniPlayerBar when now-playing
- [x] NavHost: `main` / `player/{videoId}`
- [x] Global TrackActionHost / PlaylistActionHost
- [x] FullscreenPlayerActivity + PlaybackService + DownloadForegroundService
- [x] Picture-in-Picture (Main + Fullscreen)

### Tabs

- [x] Home feed + mood/category chips + New Release browse
- [x] Shorts embedded WebView + unmute unlock
- [x] Search hub / suggestions / tabbed results / browse
- [x] Subscriptions: guest sign-in; authenticated You shelves
- [x] Library chips, multi-select, FAB playlist, Downloads hub entry

### Player

- [x] Inline 16:9 canvas, metadata, actions, transport, Up Next / Recommend
- [x] Playback speed 0.5x–8x (persisted)
- [x] Fullscreen landscape, PiP, mini bar, swipe-down dismiss
- [x] Audio power-save surface for local audio-only
- [x] Like / dislike local, share, save playlist, download
- [ ] Canvas CC toggle (API exists; **no UI**)
- [ ] Manual Video/Audio mode toggle (**no UI**)

### Auth & sync

- [x] Guest mode + Google → Supabase
- [x] YouTube Web cookie harvest; OAuth for Data API
- [x] Account switcher (channel within same Google identity)
- [x] Supabase sync for local library entities
- [ ] YouTube cloud watch history in Library (**unavailable**)

### Downloads & settings

- [x] Format sheet, Hub Downloaded/Tasks, pause/resume/retry
- [x] Wi‑Fi only / resume / thread count prefs
- [x] Night mode, language, system notifications deep-link, rate, feedback

### Explicit non-features

- Comments
- AdMob / IAP
- Cast SDK (settings stub only)
- Product Analytics events (Crashlytics + RC scaffold only)
- Voice search

---

## 4. Glossary

| UI term | Meaning |
|---------|---------|
| 歌曲 / Title | Video / track title |
| 歌手 / Channel | Uploader channel name |
| Favorites / Liked (local) | System playlist `favorites` |
| YouTube Liked | Data API liked playlist (read-only unless cloned) |
| Subscribe (player) | **App-local** `user_subscribed_channels` |
| Subscriptions (You) | YouTube Data API subscriptions |
| Up Next | Play queue / related continuation |
| Clone to local | Copy YT playlist → LOCAL UUID then sync |

---

## 5. Deviations vs older PRDs

| Topic | Older PRD | As-built |
|-------|-----------|----------|
| Search tab index | 5th tab | **3rd** tab |
| Search Voice | Coming soon UI | **No mic control** |
| Search Discovery hub cards | Documented | Subpages exist; **no DefaultHub entry** |
| Library Downloads | Empty chip placeholder | **Full Downloads Hub** + fixed entry card (chip hidden) |
| Library YouTube chip | Visible when auth | **Always hidden** in `visibleChips` |
| Library Albums chip | Hidden | **Hidden** (still true) |
| Player Like/Save/Download | Stub in old player spec | **Implemented** (local like; download pipeline) |
| Player CC / settings stub | Spec’d | **Not in canvas UI** |
| Player expanded queue overlay | Spec’d | **Up Next tab in detail** only |
| You History / Watch later shelves | Spec’d | **Hidden** pending cookie stability |

---

## 6. Acceptance for “PRD complete”

This suite is complete when:

1. Every screen/sheet in §3 maps to a section in `prd/android/*`
2. Sync/download boundaries are explicit in `10_sync_download_domain.md`
3. [`IOS_MVP_SCOPE.md`](IOS_MVP_SCOPE.md) marks Must / Should / Later against this index

Issues after freeze: amend these files; do not resurrect conflicting claims from older specs without updating §5.
