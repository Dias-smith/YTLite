# 11 — UI / UX Patterns

## Theme

- Material3; default **night mode on**
- Player detail uses dark emphasis palette even within app theme variants
- Primary brand orange tokens (`Orange40` family in Compose)

## Localization

- `values` + `values-zh`
- Runtime language: system / en / zh via Settings → recreate Activity
- iOS should mirror string keys conceptually (not Android XML)

## Lists & collections

| Pattern | Where |
|---------|-------|
| Horizontal shelves | You page, Home sections |
| Vertical LazyColumn | Most hubs |
| Grid / List toggle | Library |
| Multi-select + top action bar | Library |
| FAB | Library new playlist |
| Chips | Home categories; Library filters; Search hot words |
| Bottom sheets | Actions, pickers, speed, sort, language |
| Dialogs | Confirm destructive; new/edit playlist; edit metadata |

## Empty / error / loading

| Pattern | Spec |
|---------|------|
| Empty Songs | Find music → Home |
| Empty Downloads / Tasks | Dedicated empty strings |
| Network errors | Retry buttons on feed/search/player extract |
| Snackbars | Sign-in required, reauth, caption failures, unavailable create YT playlist |

## Gestures

| Gesture | Spec |
|---------|------|
| Pull to refresh | Home, You, some lists |
| Long-press | Search recent delete; Library reorder |
| Swipe down | Player dismiss |
| Drag | Playlist manual order / library playlist order |

## Accessibility (as-built baseline)

- Content descriptions on icon buttons (play, pip, fullscreen, back, delete, etc.)
- Not a full TalkBack audit — iOS should meet platform HIG minimums for controls

## Mini player rules

- Visible on all main tabs when now-playing
- Does not cover player detail route chrome inappropriately (detail uses full canvas)
- Progress reflects `PlaybackManager` position

## Image loading

- Coil on Android; thumbnails via `thumbnailRequest` helpers
- iOS: Kingfisher/Nuke equivalent; same URL schemes

## Acceptance

- Night mode + language cover primary chrome strings.
- Destructive actions always confirm when deleting playlists/batches/search recent.
