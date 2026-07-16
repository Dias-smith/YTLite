# Shared cross-platform assets (not Android/iOS UI code).

## extractor/

Source of truth for the WebView InnerTube bridge:

- `extractor.js`
- `bridge.html` (Android)
- `bridge-ios.html` (iOS WKWebView polyfill)
- [`REMOTE.md`](extractor/REMOTE.md) — hot-update publish flow

**Apps do not bundle these files.** After install they download from the
Supabase Storage bucket `extractor` (see `scripts/publish_extractor.sh`).

```bash
./scripts/publish_extractor.sh 1
```
