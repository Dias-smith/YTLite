# 01 — Home

## Goal

Surface personalized / catalog video & album rows so users can start playback or open track actions without leaving the tab.

## Entry

Bottom tab **Home** (default).

## Layout

1. Horizontal **category chips**
2. Vertical **feed list** (video rows; album rows where applicable)
3. Pull-to-refresh; pagination / infinite scroll

## Category chips (`FeedCategory`)

| Chip | Behavior |
|------|----------|
| All | Default home browse (`FEwhat_to_watch` / feed pipeline) |
| New Release | Music new-release albums → browse album tracks |
| Podcasts | Podcast-oriented browse |
| Moods | Energize / Feel good / Workout / Chill / Party / Romance / Commute / Focus / Sad / Sleep |

Selected category persisted via `home_preferences.selected_category_id`.

## Row actions

| Action | Result |
|--------|--------|
| Tap video | Open player with queue context when playing a list |
| Tap album | `BrowseVideosScreen` for album tracks |
| More (⋮) | `TrackActionBottomSheet` |
| Play playlist affordance | `onPlayPlaylist` → queue |

## States

| State | UI |
|-------|-----|
| Loading | Progress / placeholders |
| Empty / error | Retry (feed error) |
| Refreshing | Pull indicator |

## Data

- InnerTube home / music browse via `ExtractionRepository` / home VM
- No comments; ads filtered where `AdContentFilter` applies

## Acceptance

- User can change chip and see different content without crash.
- Tap video opens player; back/swipe dismiss returns with mini player if playing.
