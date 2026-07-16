# Extractor.js patch notes

## Prefer itags

Target set for download/play enrichment: **18, 22, 37, 139, 140, 141**.

- `18 / 22 / 37` — progressive MP4 (muxed). YouTube often no longer serves 22/37.
- `139 / 140 / 141` — AAC audio-only (`adaptiveFormats`).

## Client strategy (YTLite patch)

`queryVideoInfo` client list:

```js
o = ["android_vr", "ios", "android"]
```

Only clients with `REQUIRE_JS_PLAYER: false` (no signatureCipher decrypt in this bundle).

Flow:

1. Primary client (`android_vr`) runs `/next` + `/player` as before.
2. If more clients exist, loop `ios` then `android`, each `POST /youtubei/v1/player?key=…`.
3. Successful responses merge via `mergePlayerStreamingByItag` (primary itags win; missing itags filled from later clients). Muxed 18/22/37 stay in `streamingData.formats`; others in `adaptiveFormats`.
4. `handleInfo` still skips entries without a direct `url`.

## Locating the patch (minified)

Search markers in `extractor.js`:

| Marker | Purpose |
|--------|---------|
| `o=["android_vr","ios","android"]` | Multi-client list |
| `mergePlayerStreamingByItag` | StreamingData merge helper |
| `js.mergePlayerStreamingByItag itags` | Console log of merged itag set |

Also fixed the old broken fallback (`_readOnlyError("playerRet")` + unchecked `d` on alternate client), which never merged formats.

## Out of scope

- WEB / MWEB cipher + nsig decrypt
- DASH A/V merge in ExoPlayer
- Guaranteeing 22/37 on every video
