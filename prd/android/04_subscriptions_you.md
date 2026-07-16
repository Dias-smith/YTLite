# 04 — Subscriptions / You

## Goal

For guests: convert to sign-in. For authenticated users: YouTube “You”-style shelves and deep browse of subscriptions / playlists / liked videos.

## Entry

Bottom tab **Subscriptions** (label may show YouTube-oriented string when authenticated).

## Guest

- `SignInPromptScreen` → Google native sign-in
- On success, may prompt YouTube Web cookie login if auth cookies missing

## Authenticated — `YoutubeYouScreen`

| Block | Actions |
|-------|---------|
| Profile header | Avatar, Google account row, open AccountSwitcher |
| Reauth banner | When OAuth/cookie insufficient |
| Subscriptions rail | Horizontal channels; View all → `SubscriptionChannelsScreen` |
| Playlists rail | Horizontal; View all → list; “New playlist” → snackbar **unavailable** |
| Liked rail | Horizontal liked videos; View all |
| Pull to refresh | Reloads shelves |

### Hidden shelves (as-built)

History / Watch later / Your videos / Connect-cookie promotional shelves are **commented out / hidden** until cookie path is stable.

## Deep pages

| Page | Actions |
|------|---------|
| Subscription channels list | Open channel |
| Channel videos | Play one / play all as queue |
| YT playlists list | Open playlist |
| YT playlist items | Play one / play all |

## Cookie & OAuth

- Data API (`youtube.readonly`) powers many shelves
- Cookie enables SAPISIDHASH InnerTube authenticated browse where needed
- Web login via `YoutubeWebLoginScreen`

## Acceptance

- Guest sees sign-in and can authenticate.
- Authenticated user sees at least subscriptions or liked (when API returns data).
- Channel / playlist deep links play into global player.
