# Supabase (YTLite)

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
| `extractor` | yes | Remote InnerTube extractor bundle (`manifest.json` + `v{N}/*`) |

### Extractor hot-update

Apps **do not** ship `extractor.js` / bridge HTML. After first install they download:

```text
{SUPABASE_URL}/storage/v1/object/public/extractor/manifest.json
{SUPABASE_URL}/storage/v1/object/public/extractor/v{N}/extractor.js
{SUPABASE_URL}/storage/v1/object/public/extractor/v{N}/bridge.html
{SUPABASE_URL}/storage/v1/object/public/extractor/v{N}/bridge-ios.html
```

Publish from the repo (requires service role / logged-in CLI):

```bash
# Apply migration once
supabase db push
# or: supabase migration up

# Upload a new bundle version (example: 1)
./scripts/publish_extractor.sh 1
```

`manifest.json` `config` is the Remote Config source for InnerTube knobs
(`androidClientVersion`, `signatureTimestamp`, `preferItags`, fallback flags).
Do not duplicate those keys in Firebase Remote Config.
