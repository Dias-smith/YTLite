# Extractor assets are NOT packaged in the APK.

After first install the app downloads `extractor.js` + bridge HTML from the
Supabase Storage public bucket `extractor`.

Source of truth: `shared/extractor/`
Publish: `./scripts/publish_extractor.sh <version>`

See `shared/extractor/REMOTE.md` and `supabase/README.md`.
