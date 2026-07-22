# Resolver assets are NOT packaged in the APK.

After first install the app downloads `resolution.js` + bridge HTML from the
Supabase Storage public bucket `resolution`.

`resolution.js` is **not** in this repo. Source of bridge HTML: `shared/resolution/`
Publish: `RESOLUTION_JS=/path/to/resolution.js ./scripts/publish_resolution.sh <version>`

See `shared/resolution/REMOTE.md` and `supabase/README.md`.
