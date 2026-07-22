# Shared cross-platform assets (not Android/iOS UI code).

## resolution/

WebView bridge HTML kept in-repo (no stream-resolver JS payload):

- `bridge.html` (Android)
- `bridge-ios.html` (iOS WKWebView polyfill)
- [`REMOTE.md`](resolution/REMOTE.md) — hot-update publish flow

**`resolution.js` is never stored in this repo** (gitignored). Keep it outside
the tree and pass its path when publishing.

**Apps do not bundle these files.** After first install they download from the
Supabase Storage bucket `resolution` (see `scripts/publish_resolution.sh`).

```bash
RESOLUTION_JS=~/secrets/resolution.js ./scripts/publish_resolution.sh 1
```
