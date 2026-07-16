# iOS MVP Scope

> Derived from [`ANDROID_FEATURE_INDEX.md`](ANDROID_FEATURE_INDEX.md).  
> Implement Must first; Should after core playable loop; Later after parity needs.

## Priority legend

| Tag | Meaning |
|-----|---------|
| **Must** | Required for first playable iOS build with account+library continuity |
| **Should** | Near-term parity; ship in follow-up sprint after Must |
| **Later** | Explicitly defer; Android-only OK for now |
| **Skip** | Not planned / non-feature |

## Must

| Area | Requirement | Android ref |
|------|-------------|-------------|
| Shell | Tab bar: Home, Search, Library (Shorts/You can stub) + Mini player when playing | `00`, `06` |
| Search | Query → results (Videos + All minimum) → open player | `03` |
| Home | Basic feed or “open from search” path if feed blocked | `01` |
| Player | AVPlayer play/pause/seek/next/prev; speed 0.5–8x; now-playing info | `06` |
| Extract | WKWebView + shared `extractor.js` yields playable URL | `10` |
| Auth | Guest + Google → Supabase | `07` |
| Library | Local playlists + Favorites + History list; create playlist; add track | `05`, `09` |
| Sync | Pull/push Supabase playlists/tracks/last_played/metadata | `10` |
| Settings | Language + night mode | `08` |
| Share | System share `youtube.com/watch?v=` | `09` |

## Should

| Area | Requirement | iOS status |
|------|-------------|------------|
| You / Subscriptions | Sign-in wall + You shelves (subscriptions, liked, playlists list) | Liked + Trending + channel/playlist deep browse |
| PiP | System Picture in Picture | AVPlayerViewController PiP |
| Fullscreen landscape | Player chrome parity | Via system player controls |
| Track/Playlist sheets | Same action matrix as Android | Partial (like/save/share/lyrics) |
| Channel / YT playlist deep pages | Browse & play | ChannelVideos / PlaylistVideosBrowser |
| Recommend / Up Next | Queue fill from `/next` | Queue from feed/search lists |
| Lyrics sheet | Caption VTT display | LyricsSheet |
| Cookie Web login | If Data API alone insufficient | Later |
| Shorts | Embedded Shorts WebView | Shorts tab |

## Later

| Area | Notes |
|------|-------|
| Shorts WebView tab | High WebView UX cost |
| Search Discovery / Charts / Moods hub | Missing Android hub entry anyway |
| Account multi-channel switcher | After single-account solid |
| Grid/list + batch multi-select library | After basic library |
| Cast stub | Low value |
| Analytics product events | Optional |

## Skip

- Comments
- AdMob / IAP
- True Cast SDK
- YouTube cloud watch-history-as-library

## Acceptance (MVP exit)

1. ~~Cold start → Search video → play~~ / also Home feed  
2. ~~Sign in with Google → create playlist → add track → sync~~ (requires Supabase redirect `ytlite://auth-callback`)  
3. ~~Speed change persists across relaunch~~  
4. ~~Mini player can pause/resume and reopen detail~~ (+ prev/next)


## Monorepo layout

```
YTLite/
  app/                 # Android
  ios/                 # SwiftUI Xcode project
  shared/extractor/    # extractor.js + bridge.html
  supabase/            # shared migrations
  prd/                 # this suite
```
