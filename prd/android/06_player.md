# 06 — Player

## Goal

Hybrid video + music-style player: watch or listen, control queue, persist speed, survive background via MediaSession.

## Surfaces

| Surface | Implementation |
|---------|----------------|
| Inline detail | `PlayerScreen` + `SmartPlayerCanvas(Inline)` 16:9 |
| Fullscreen | `FullscreenPlayerActivity` landscape |
| PiP | System PiP + `PipActionReceiver` |
| Mini | `MiniPlayerBar` above tabs |
| Extracting | `PlayerExtractingSurface` while resolving stream |

## Detail layout (top → bottom)

1. **Canvas** — video or audio power-save cover
2. **Metadata** — marquee title; more; channel (+ Subscribe local); action bar: Like / Dislike / Share / Save / Download
3. **Transport** — Shuffle, Prev, Play/Pause, Next, Repeat (Off / All / One)
4. **Tabs** — Up Next (queue) / Lyrics placeholder / Recommend  
   - Save list → PlaylistPicker (batch)

**Comments:** forbidden (no UI).

## Canvas overlay (`SmartPlayerCanvas`)

| Control | Spec |
|---------|------|
| Tap | Toggle overlay visibility |
| Auto-hide | ~5s while playing; paused = keep visible; speed sheet open = keep visible |
| Speed | Button shows current (`1x`…); sheet options **0.5 / 0.75 / 1 / 1.25 / 1.5 / 2 / 3 / 5 / 8**; persist `playback_speed` |
| PiP | When video mode + device support |
| Fullscreen | Enter/exit |
| Center | Prev / PlayPause / Next |
| Scrubber | Seek + time labels |
| Back | Inline uses nav back; fullscreen may show back / exit |

## Audio power-save

- Auto when playing **local audio-only** download
- Cover surface instead of video
- **No** user-facing Video/Audio toggle on canvas

## Gestures & exit

| Gesture | Spec |
|---------|------|
| Swipe down on detail | ~120dp dismiss → mini if still playing |
| Mini tap | Re-open detail |
| Mini play/pause / next | Transport |

## Captions / lyrics

- Canvas **has no CC button**
- Track Action → `LyricsBottomSheet` loads VTT via `CaptionRepository`
- `PlaybackManager` subtitle APIs exist but not wired to canvas UI

## Like / dislike semantics

- Local Favorites / Not Interested — **not** YouTube API like

## Queue

- Prefill related (~20) on enter when available (`/next`)
- No separate full-screen queue overlay product surface (as-built)

## Acceptance

- Play remote URL and local file; speed applies immediately and after relaunch.
- Fullscreen and PiP keep same `PlaybackManager` position.
- Mini controls work from any main tab.
