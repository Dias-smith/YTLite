# 07 — Auth & Accounts

## Goal

Support guest use of local library, then optional Google identity for Supabase sync and YouTube API/cookie features.

## Session model

| State | Owner key | Capabilities |
|-------|-----------|--------------|
| Guest | `guest:{guestId}` | Local library, playback, downloads |
| Authenticated | `user:{supabaseUserId}` | + cloud sync; You shelves; OAuth |

## Google → Supabase

1. Credential Manager / Google Identity → ID token
2. Supabase `signInWithGoogleNative`
3. Store session; attempt cookie sync from WebView
4. If YouTube auth cookie missing → encourage/force `YoutubeWebLoginScreen`

## YouTube Web cookie login

- WebView with browser-like UA
- Harvest cookies into `YoutubeCookieJar` (+ persistent store)
- Used for authenticated InnerTube (`SAPISIDHASH`)

## OAuth (Data API)

- Scope: `youtube.readonly`
- Access token stored; silent refresh via Identity authorize
- Required for subscriptions / owned playlists / liked via Data API

## Account switcher

| Action | Spec |
|--------|------|
| Add account / Sign in | Google flow |
| Sign out | Clear Supabase + cookies/tokens; migrate local ownership to guest |
| Switch YouTube channel | Same Google user; select `mine` channel (`OwnedChannelsRepository`) — **not** multi-Google-account switcher |

## Guest merge

On first auth: `LibraryRepository.mergeGuestDataIntoUser` then remote upload/pull.

## Configuration failure

- Missing `GOOGLE_WEB_CLIENT_ID` / Supabase keys → snackbar / not-configured UX (no crash)

## Acceptance

- Guest → sign-in → library items owned by user.
- Sign-out returns to guest-capable shell without wiping device downloads files unexpectedly (metadata ownership rules follow repository).
