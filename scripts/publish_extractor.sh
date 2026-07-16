#!/usr/bin/env bash
# Publish shared/extractor to Supabase Storage public bucket `extractor`.
# Usage: ./scripts/publish_extractor.sh <version> [minAppVersion]
# Example: ./scripts/publish_extractor.sh 1 1.0.0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${ROOT}/shared/extractor"
VERSION="${1:?usage: $0 <version> [minAppVersion]}"
MIN_APP_VERSION="${2:-1.0.0}"
BUCKET="extractor"
PREFIX="v${VERSION}"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/ytlite-extractor.XXXXXX")"
cleanup() { rm -rf "${STAGING}"; }
trap cleanup EXIT

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: missing $1" >&2; exit 1; }; }
need supabase
need python3

for f in extractor.js bridge.html bridge-ios.html; do
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

HASH_JS="$(sha256_file "${SOURCE}/extractor.js")"
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
        "extractor.js": {"path": "${PREFIX}/extractor.js", "sha256": "${HASH_JS}"},
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

cp "${SOURCE}/extractor.js" "${STAGING}/extractor.js"
cp "${SOURCE}/bridge.html" "${STAGING}/bridge.html"
cp "${SOURCE}/bridge-ios.html" "${STAGING}/bridge-ios.html"

echo "Uploading ${PREFIX}/ ..."
# Explicit Content-Type: CLI auto-detect may append "; charset=utf-8", which
# fails Storage allowed_mime_types exact-match checks.
supabase --experimental storage cp --content-type "application/javascript" \
  "${STAGING}/extractor.js" "ss:///${BUCKET}/${PREFIX}/extractor.js"
supabase --experimental storage cp --content-type "text/html" \
  "${STAGING}/bridge.html" "ss:///${BUCKET}/${PREFIX}/bridge.html"
supabase --experimental storage cp --content-type "text/html" \
  "${STAGING}/bridge-ios.html" "ss:///${BUCKET}/${PREFIX}/bridge-ios.html"
supabase --experimental storage cp --content-type "application/json" \
  "${STAGING}/manifest.json" "ss:///${BUCKET}/manifest.json"

echo
echo "Published extractor v${VERSION}"
echo "Manifest: ${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/manifest.json"
echo "Files:"
echo "  ${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/${PREFIX}/extractor.js"
echo "  ${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/${PREFIX}/bridge.html"
echo "  ${SUPABASE_URL}/storage/v1/object/public/${BUCKET}/${PREFIX}/bridge-ios.html"
