# Resolver assets are NOT packaged in the APK.

After first install the app downloads `resolution.js` + bridge HTML from the
Supabase Storage public bucket `resolution`.

`resolution.js` is **not** in this repo. Source of bridge HTML: `shared/resolution/`
Publish: `RESOLUTION_JS=/path/to/resolution.js ./scripts/publish_resolution.sh <version>`

See `shared/resolution/REMOTE.md` and `supabase/README.md`.
Apps pin `ExtractorBundleStore.NATIVE_API` (currently 1). Breaking JS must bump that
constant in a new app build and publish with `RESOLUTION_NATIVE_API`.
