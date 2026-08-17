# Remote resolver hot-update

Resolver assets are **not** shipped inside the iOS/Android app binary.
`shared/resolution/` holds bridge HTML only; `resolution.js` stays **outside**
the repo and is supplied at publish time. Apps download after first install.

## Layout on Supabase Storage (`resolution` bucket)

```text
manifest.json                      ← latest pointer
compat/api-1/manifest.json         ← frozen pointer for nativeApi=1
compat/api-2/manifest.json         ← … after a breaking JS/native bump
v1/resolution.js
v1/bridge.html
v1/bridge-ios.html
v2/...
```

Public URL pattern:

```text
{SUPABASE_URL}/storage/v1/object/public/resolution/manifest.json
{SUPABASE_URL}/storage/v1/object/public/resolution/compat/api-{N}/manifest.json
{SUPABASE_URL}/storage/v1/object/public/resolution/v{N}/resolution.js
```

Never delete old `v{N}/` directories or other `compat/api-*` channels.

## Native protocol vs YouTube hotfix

The compiled app constant (`ResolverBundleStore.nativeApi` / `ExtractorBundleStore.NATIVE_API`,
currently **1**) is the JS ↔ native contract. Bump it **only** when bridge methods or
resolve JSON shape change, and ship a new app with that constant.

| Publish type | What to bump | Who upgrades |
|--------------|--------------|--------------|
| Compatible hotfix (STS, clients, itags, YouTube breakage) | `version` only; keep `nativeApi` | All apps on that native API |
| Breaking JS | `nativeApi` + app constant + usually `minAppVersion` | New app builds only |

Old apps fetch `manifest.json`, see a higher `nativeApi`, then load
`compat/api-{their API}/manifest.json` and **keep their last compatible bundle**.
They never install an incompatible JS.

Manifests without `nativeApi` (already installed) are treated as `nativeApi=1`.

## Publish

```bash
RESOLUTION_JS=/path/to/resolution.js ./scripts/publish_resolution.sh <version>
# Compatible hotfix:
RESOLUTION_JS=~/secrets/resolution.js ./scripts/publish_resolution.sh 8 1.0.0
# Breaking (after bumping NATIVE_API in both apps to 2):
RESOLUTION_NATIVE_API=2 RESOLUTION_JS=~/secrets/resolution.js ./scripts/publish_resolution.sh 9 1.5.0
```

Requires `SUPABASE_URL` and a logged-in Supabase CLI (or `SUPABASE_ACCESS_TOKEN`).

The script writes both `manifest.json` and `compat/api-{NATIVE_API}/manifest.json`.
It does not touch other `compat/api-*` objects.

## Manifest

See generated `manifest.json`. Important fields:

| Field | Role |
|-------|------|
| `version` | Monotonic int; apps upgrade when remote > installed **and** native API matches |
| `nativeApi` | Highest native protocol this bundle speaks |
| `minNativeApi` | Lowest native protocol this bundle speaks (defaults to `nativeApi`) |
| `minAppVersion` | Semver gate; older apps keep old store / prompt upgrade |
| `files.*.sha256` | Integrity check before install |
| `config.*` | InnerTube knobs (STS, client versions, itags, fallback flags) |

## App behavior

1. Cold start / `ensureReady` → resolver bundle `ensureBundle`
2. No local store → fetch a **compatible** manifest (latest, else `compat/api-N`)
3. Has store → load immediately; refresh in background when a compatible newer version exists
4. Incompatible latest JS → keep installed bundle (do not overwrite)
5. Checksum failure → re-fetch; never execute tampered JS
6. Native fallbacks (ANDROID player / watch HTML) still run if JS resolve fails
