# 10 — Sync, Download & Domain Boundaries

## Dual identity (critical)

| Track | Powers |
|-------|--------|
| Supabase user | LOCAL library sync across devices |
| Google OAuth + optional Web cookie | YouTube Data API + authenticated InnerTube |

These are **not** the same. LOCAL likes ≠ YouTube Liked until clone/merge intentional.

## Syncs to Supabase

| Entity | Notes |
|--------|-------|
| profiles | display / avatar |
| artists, tracks | catalog upsert |
| playlists | includes system favorites / watch_later; `is_pinned` |
| playlist_track_cross_ref | positions |
| playback_history | events + progress_ms |
| user_track_last_played | library history continuum |
| user_track_metadata | edits |
| user_subscribed_channels | **app-local follows**, not Data API subs |

Triggers: login merge, uploadLocal, pullRemote, repository write paths. **No Settings “Sync” button.**

## Does NOT sync

| Data | Where it lives |
|------|----------------|
| Download files & tasks | Device `filesDir/downloads` + Room |
| Search history / recent clicks | Room |
| Not interested | Room |
| Play queue | Process / local repo |
| YouTube official playlists | Client cache / Data API; clone → LOCAL UUID then sync |

## Playback extraction

| Path | Role |
|------|------|
| InnerTube Kotlin | Home / search / browse / next |
| JS extractor (`extractor.js` + WebView bridge) | Resolves stream URLs + formats + captions |
| Format select | Video: muxed 37→22→18 preference; Audio: 140→141→139; remember `preferred_itag` |
| Speed | `PlaybackSpeeds` 0.5–8; `playback_preferences` |

## Downloads

| Behavior | Spec |
|----------|------|
| Enqueue | Format itag + metadata; Wi‑Fi-only gate |
| Engine | Multi-thread Range segments; resume `.partial`; concurrency caps |
| Lifecycle | Foreground service notifications |
| Offline play | Resolve local path → `file://` in queue |
| URL expiry | Re-extract same itag (limited retries) |
| Cloud | **Never** uploads media bytes |

Default format enum: AskEachTime / AudioFast(140) / Video360(18) / Video720(22). Additional itags may appear in selector order.

## Preference keys (summary)

| Store | Keys |
|-------|------|
| `app_preferences` | `night_mode_enabled`, `app_language` |
| `home_preferences` | `selected_category_id` |
| `playback_preferences` | `playback_speed`, `preferred_itag` |
| `download_preferences` | `thread_count`, `resume_enabled`, `wifi_only`, `default_format` |
| session / cookies | guest/user ids, google access token, active channel, cookie JSON |

## Remote Config / Analytics

- Firebase Crashlytics (release)
- Remote Config scaffold (`example_feature_enabled` placeholder)
- No product Analytics event taxonomy

## Share / Cast

- Share: YouTube watch URL
- Cast: open system Cast / wireless display settings only

## Acceptance

- After login, playlist created on device A appears on device B after pull.
- Downloaded item plays with airplane mode on.
- YouTube playlist remains non-synced until Clone to local.
