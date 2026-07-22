#!/usr/bin/env bash
# Publish bridge HTML (+ resolution.js from an external path) to Supabase Storage
# public bucket `resolution`.
#
# resolution.js is NOT kept in this repo. Provide it via:
#   RESOLUTION_JS=/absolute/path/to/resolution.js ./scripts/publish_resolution.sh <version>
# or:
#   ./scripts/publish_resolution.sh <version> [minAppVersion] /absolute/path/to/resolution.js
#
# Example:
#   RESOLUTION_JS=~/secrets/resolution.js ./scripts/publish_resolution.sh 1 1.0.0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${ROOT}/shared/resolution"
VERSION="${1:?usage: $0 <version> [minAppVersion] [resolution.js path]}"
MIN_APP_VERSION="${2:-1.0.0}"
RESOLUTION_JS_PATH="${3:-${RESOLUTION_JS:-}}"
BUCKET="resolution"
PREFIX="v${VERSION}"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/ytlite-resolution.XXXXXX")"
cleanup() { rm -rf "${STAGING}"; }
trap cleanup EXIT

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: missing $1" >&2; exit 1; }; }
need supabase
need python3

if [[ -z "${RESOLUTION_JS_PATH}" ]]; then
  echo "error: resolution.js is not in the repo." >&2
  echo "  Set RESOLUTION_JS=/path/to/resolution.js" >&2
  echo "  or pass it as the 3rd argument." >&2
  exit 1
fi
if [[ ! -f "${RESOLUTION_JS_PATH}" ]]; then
  echo "error: resolution.js not found: ${RESOLUTION_JS_PATH}" >&2
  exit 1
fi
# Refuse publishing a file that lives inside the tracked shared/resolution tree.
case "${RESOLUTION_JS_PATH}" in
  "${SOURCE}"/*)
    echo "error: do not place resolution.js under shared/resolution/; keep it outside the repo." >&2
    exit 1
    ;;
esac

for f in bridge.html bridge-ios.html; do
  if [[ ! -f "${SOURCE}/${f}" ]]; then
    echo "error: missing ${SOURCE}/${f}" >&2
    exit 1
  fi
done

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

HASH_JS="$(sha256_file "${RESOLUTION_JS_PATH}")"
HASH_BRIDGE="$(sha256_file "${SOURCE}/bridge.html")"
HASH_BRIDGE_IOS="$(sha256_file "${SOURCE}/bridge-ios.html")"

# Prefer SUPABASE_URL from env, else local.properties (Android), else ios secrets.
if [[ -z "${SUPABASE_URL:-}" ]]; then
  if [[ -f "${ROOT}/local.properties" ]]; then
    SUPABASE_URL="$(python3 - <<PY
from pathlib import Path
props = {}
for line in Path("${ROOT}/local.properties").read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    props[k.strip()] = v.strip()
print(props.get("SUPABASE_URL", ""))
PY
)"
  fi
fi
if [[ -z "${SUPABASE_URL:-}" && -f "${ROOT}/ios/Config/Secrets.xcconfig.local" ]]; then
  SUPABASE_URL="$(python3 - <<PY
from pathlib import Path
for line in Path("${ROOT}/ios/Config/Secrets.xcconfig.local").read_text().splitlines():
    line = line.strip()
    if line.startswith("SUPABASE_URL"):
        print(line.split("=", 1)[1].strip())
        break
PY
)"
fi
if [[ -z "${SUPABASE_URL:-}" ]]; then
  echo "error: set SUPABASE_URL or configure local.properties / ios secrets" >&2
  exit 1
fi

python3 - "${STAGING}/manifest.json" <<PY
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
manifest = {
    "version": int("${VERSION}"),
    "minAppVersion": "${MIN_APP_VERSION}",
    "files": {
        "resolution.js": {"path": "${PREFIX}/resolution.js", "sha256": "${HASH_JS}"},
        "bridge.html": {"path": "${PREFIX}/bridge.html", "sha256": "${HASH_BRIDGE}"},
        "bridge-ios.html": {"path": "${PREFIX}/bridge-ios.html", "sha256": "${HASH_BRIDGE_IOS}"},
    },
    "config": {
        "androidClientVersion": "20.10.38",
        "signatureTimestamp": 20646,
        "preferItags": [18, 22, 37],
        "enableAndroidPlayerFallback": True,
        "enableWatchPageFallback": True,
    },
}
out.write_text(json.dumps(manifest, indent=2) + "\n")
print(out.read_text())
PY

cp "${RESOLUTION_JS_PATH}" "${STAGING}/resolution.js"
cp "${SOURCE}/bridge.html" "${STAGING}/bridge.html"
cp "${SOURCE}/bridge-ios.html" "${STAGING}/bridge-ios.html"

echo "Uploading ${PREFIX}/ ..."
# Explicit Content-Type: CLI auto-detect may append "; charset=utf-8", which
# fails Storage allowed_mime_types exact-match checks.
# Remove existing objects first so republishing the same version is allowed (409 Duplicate).
supabase --experimental storage rm --yes \
  "ss:///${BUCKET}/${PREFIX}/resolution.js" \
  "ss:///${BUCKET}/${PREFIX}/bridge.html" \
  "ss:///${BUCKET}/${PREFIX}/bridge-ios.html" \
  "ss:///${BUCKET}/manifest.json" \
  2>/dev/null || true

supabase --experimental storage cp --content-type "application/javascript" \
  "${STAGING}/resolution.js" "ss:///${BUCKET}/${PREFIX}/resolution.js"
supabase --experimental storage cp --content-type "text/html" \
  "${STAGING}/bridge.html" "ss:///${BUCKET}/${PREFIX}/bridge.html"
supabase --experimental storage cp --content-type "text/html" \
  "${STAGING}/bridge-ios.html" "ss:///${BUCKET}/${PREFIX}/bridge-ios.html"
supabase --experimental storage cp --content-type "application/json" \
  "${STAGING}/manifest.json" "ss:///${BUCKET}/manifest.json"

echo
echo "Published resolution bundle v${VERSION}"
echo "Manifest: ${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/manifest.json"
echo "Files:"
echo "  ${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/${PREFIX}/resolution.js"
echo "  ${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/${PREFIX}/bridge.html"
echo "  ${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/${PREFIX}/bridge-ios.html"
