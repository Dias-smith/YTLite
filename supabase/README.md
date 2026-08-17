# Supabase (YTLite)

## Sign in with Apple

Enable **Authentication → Providers → Apple** for the iOS app (bundle `com.ytlite.player`).
See [Auth Apple (iOS)](https://supabase.com/docs/guides/auth/social-login/auth-apple?platform=ios).

iOS uses native `ASAuthorization` + `signInWithIdToken` (not the web OAuth redirect).

## Account deletion (Apple 5.1.1(v))

Edge Function: `functions/delete-account`

```bash
supabase functions deploy delete-account
```

iOS calls `POST /functions/v1/delete-account` with the signed-in user's access token.
The function deletes `user_track_metadata`, clears `playlist-covers/{user_id}/`, then
`auth.admin.deleteUser` (CASCADE removes other user-scoped rows).

## Storage buckets

| Bucket | Public | Purpose |
|--------|--------|---------|
| `playlist-covers` | yes | Per-user playlist cover images (`{user_id}/{playlist_id}.jpg`) |
| `resolution` | yes | Remote InnerTube resolver (`manifest.json`, `compat/api-N/`, `v{N}/*`) |

### Resolver hot-update

Apps **do not** ship `resolution.js` / bridge HTML. After first install they download:

```text
{SUPABASE_URL}/storage/v1/object/public/resolution/manifest.json
{SUPABASE_URL}/storage/v1/object/public/resolution/compat/api-{N}/manifest.json
{SUPABASE_URL}/storage/v1/object/public/resolution/v{N}/resolution.js
{SUPABASE_URL}/storage/v1/object/public/resolution/v{N}/bridge.html
{SUPABASE_URL}/storage/v1/object/public/resolution/v{N}/bridge-ios.html
```

Publish from the repo (requires service role / logged-in CLI).
`resolution.js` must live **outside** the repo:

```bash
# Apply migration once
supabase db push
# or: supabase migration up

# Compatible hotfix (nativeApi stays 1)
RESOLUTION_JS=~/secrets/resolution.js ./scripts/publish_resolution.sh 8

# Breaking JS — bump NATIVE_API in iOS/Android first, then:
# RESOLUTION_NATIVE_API=2 RESOLUTION_JS=~/secrets/resolution.js ./scripts/publish_resolution.sh 9 1.5.0
```

Apps pin a compiled `nativeApi` (currently 1). If `manifest.json` requires a newer
protocol they load `compat/api-{nativeApi}/manifest.json` and keep the last
compatible bundle. See `shared/resolution/REMOTE.md`.

`manifest.json` `config` is the Remote Config source for InnerTube knobs
(`androidClientVersion`, `signatureTimestamp`, `preferItags`, fallback flags).
Do not duplicate those keys in Firebase Remote Config.
