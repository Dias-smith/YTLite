# Remote resolver hot-update

Resolver assets are **not** shipped inside the iOS/Android app binary.
`shared/resolution/` holds bridge HTML only; `resolution.js` stays **outside**
the repo and is supplied at publish time. Apps download after first install.

## Layout on Supabase Storage (`resolution` bucket)

```text
manifest.json
v1/resolution.js
v1/bridge.html
v1/bridge-ios.html
v2/...
```

Public URL pattern:

```text
{SUPABASE_URL}/storage/v1/object/public/resolution/manifest.json
{SUPABASE_URL}/storage/v1/object/public/resolution/v{N}/resolution.js
```

## Publish

```bash
RESOLUTION_JS=/path/to/resolution.js ./scripts/publish_resolution.sh <version>
# Example:
RESOLUTION_JS=~/secrets/resolution.js ./scripts/publish_resolution.sh 1
# Or 3rd arg:
./scripts/publish_resolution.sh 1 1.0.0 ~/secrets/resolution.js
```

Requires `SUPABASE_URL` and a logged-in Supabase CLI (or `SUPABASE_ACCESS_TOKEN`).

## Manifest

See generated `manifest.json`. Important fields:

| Field | Role |
|-------|------|
| `version` | Monotonic int; apps upgrade when remote > installed |
| `minAppVersion` | Semver gate; older apps keep old store / prompt upgrade |
| `files.*.sha256` | Integrity check before install |
| `config.*` | InnerTube knobs (STS, client versions, itags, fallback flags) |

## App behavior

1. Cold start / `ensureReady` → resolver bundle `ensureBundle`
2. No local store → must fetch (first install needs network)
3. Has store → load immediately; refresh in background when newer
4. Checksum failure → re-fetch; never execute tampered JS
5. Native fallbacks (ANDROID player / watch HTML) still run if JS resolve fails
