# Shared cross-platform assets (not Android/iOS UI code).

## extractor/

Copied from `app/src/main/assets/extractor/` for dual-client use.

- Android may keep reading from `app/src/main/assets/extractor/` for now.
- iOS bundles this folder via XcodeGen `ExtractorAssets`.

When changing JS, update **both** locations until Android is switched to this folder as the single source.
