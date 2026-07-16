#!/usr/bin/env bash
# Sync Android local.properties Supabase keys into ios/Config/Secrets.xcconfig.local
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/local.properties"
DST="${ROOT}/ios/Config/Secrets.xcconfig.local"

if [[ ! -f "$SRC" ]]; then
  echo "error: missing $SRC" >&2
  exit 1
fi

python3 - "$SRC" "$DST" <<'PY'
import pathlib, sys
src, dst = map(pathlib.Path, sys.argv[1:])
props = {}
for line in src.read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    props[k.strip()] = v.strip()

url = props.get("SUPABASE_URL", "")
anon = props.get("SUPABASE_ANON_KEY", "")
google = props.get("GOOGLE_WEB_CLIENT_ID") or props.get("GOOGLE_CLIENT_ID", "")
yt = props.get("YOUTUBE_DATA_API_KEY", "")
if not url or not anon:
    raise SystemExit("error: SUPABASE_URL / SUPABASE_ANON_KEY missing in local.properties")

# xcconfig treats // as comment — escape as https:/$()/host
if url.startswith("https://"):
    url_xc = "https:/$()/" + url[len("https://"):]
elif url.startswith("http://"):
    url_xc = "http:/$()/" + url[len("http://"):]
else:
    url_xc = url

body = "\n".join([
    f"SUPABASE_URL = {url_xc}",
    f"SUPABASE_ANON_KEY = {anon}",
    f"GOOGLE_CLIENT_ID = {google}",
    f"YOUTUBE_DATA_API_KEY = {yt}",
    "",
])
dst.write_text(body)
print(f"wrote {dst}")
print(f"SUPABASE_URL host = {url.split('://',1)[-1]}")
print("ANON_KEY set =", bool(anon))
print("GOOGLE_CLIENT_ID set =", bool(google))
PY
