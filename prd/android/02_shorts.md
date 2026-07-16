# 02 — Shorts

## Goal

Allow casual Shorts browsing via embedded YouTube Shorts web surface with app-level audio conflict handling.

## Entry

Bottom tab **Shorts**.

## Layout

- Full-bleed `EmbeddedWebView` loaded with Shorts URL (`ShortsConfig`)
- First interaction: center play unlock for unmuted web playback
- Optional vertical nudge before unlock to switch Short

## Behaviors

| Behavior | Spec |
|----------|------|
| Unlock | User tap to enable WebView audio |
| App player conflict | May pause local ExoPlayer when Shorts unmuted |
| Chrome | JS injection hides/locks selected native YouTube chrome controls |
| No native Shorts feed rewrite | Relies on YouTube mobile web |

## Non-goals

- Native Shorts Media3 feed
- Download Shorts
- Commenting inside Shorts

## Acceptance

- Tab opens WebView without freezing app shell.
- Unmute path works after explicit user gesture.
- Leaving tab returns to other tabs with shell intact.
