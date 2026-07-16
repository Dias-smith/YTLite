# 03 — Search

## Goal

YouTube-oriented video/channel/playlist search with local recent + history and tabbed results.

## Entry

Bottom tab **Search** (**3rd** tab — not 5th).

## State machine

| State | Description |
|-------|-------------|
| **DefaultHub** | Empty query focus: Recent cards, query history, hot keyword chips |
| **Suggestions** | Debounced suggest list (query / channel / video) |
| **Results** | Tabs: **All / Videos / Channels / Playlists** + continuation paging |
| **SubCategory** | New releases / Charts / Moods (code present) |
| **BrowseVideos** | Playlist or mood browse list → tap plays; can play all as queue |

> **As-built gap:** Discovery cards that open SubCategory are **not** wired from DefaultHub UI (`onDiscoveryOpen` unused). Hot keywords partially replace discovery.

## Search bar

- Rounded field; hint “Search videos, channels…”
- Clear button when non-empty
- **No voice mic** control

## Recent & history

| Feature | Spec |
|---------|------|
| Recent cards | From `search_recent_clicks`; tap opens; **long-press** delete one (confirm dialog); Clear all |
| Query history | Room FIFO max ~15; tap fills/submits; Clear all |
| Cloud sync | **No** |

## Results interactions

| Tap | Result |
|-----|--------|
| Video | Open player |
| Channel | Channel videos overlay/page |
| Playlist | BrowseVideos then items |

## Non-goals

- Voice / Identify
- Upload date / duration filters
- Shorts-only results tab
- Cloud sync of search history

## Acceptance

- Submit query → Results with at least Videos tab working.
- Recent long-press delete and Clear all work without corrupting history store.
