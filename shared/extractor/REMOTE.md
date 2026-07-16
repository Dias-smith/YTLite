# Remote extractor hot-update

Extractor assets are **not** shipped inside the iOS/Android app binary.
`shared/extractor/` is the publish source; apps download after first install.

## Layout on Supabase Storage (`extractor` bucket)

```text
manifest.json
v1/extractor.js
v1/bridge.html
v1/bridge-ios.html
v2/...
```

Public URL pattern:

```text
{SUPABASE_URL}/storage/v1/object/public/extractor/manifest.json
{SUPABASE_URL}/storage/v1/object/public/extractor/v{N}/extractor.js
```

## Publish

```bash
./scripts/publish_extractor.sh <version>
# Example:
./scripts/publish_extractor.sh 1
```

Requires `SUPABASE_URL` and a logged-in Supabase CLI (or `SUPABASE_ACCESS_TOKEN`).

## Manifest

See generated `manifest.json`. Important fields:

| Field | Role |
|-------|------|
| `version` | Monotonic int; apps upgrade when remote > installed |
| `minAppVersion` | Semver gate; older apps keep old cache / prompt upgrade |
| `files.*.sha256` | Integrity check before install |
| `config.*` | InnerTube knobs (STS, client versions, itags, fallback flags) |

## App behavior

1. Cold start / `ensureReady` → `ExtractorBundleStore.ensureBundle`
2. No cache → must download (first install needs network)
3. Has cache → load immediately; refresh in background when newer
4. Checksum failure → re-download; never execute tampered JS
5. Native fallbacks (ANDROID player / watch HTML) still run if JS extract fails
