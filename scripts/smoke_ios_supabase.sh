#!/usr/bin/env bash
# Read-only smoke checks for iOS Supabase readiness (no interactive OAuth UI).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS="${ROOT}/ios/Config/Secrets.xcconfig.local"
REF="${SUPABASE_PROJECT_REF:-qhqrpurbwhitwdelhqwc}"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "OK: $*"; }

[[ -f "$SECRETS" ]] || fail "missing $SECRETS (run scripts/sync_ios_supabase_secrets.sh)"

ENV_FILE="$(mktemp)"
trap 'rm -f "$ENV_FILE"' EXIT
python3 - "$SECRETS" "$ENV_FILE" <<'PY'
from pathlib import Path
import shlex, sys
src, out = map(Path, sys.argv[1:])
vals={}
for line in src.read_text().splitlines():
    if "=" not in line: continue
    k,v=line.split("=",1)
    vals[k.strip()]=v.strip()
url=vals.get("SUPABASE_URL","").replace("https:/$()/","https://").replace("http:/$()/","http://")
lines=[
    f"SUPABASE_URL={shlex.quote(url)}",
    f"SUPABASE_ANON_KEY={shlex.quote(vals.get('SUPABASE_ANON_KEY',''))}",
    f"GOOGLE_CLIENT_ID={shlex.quote(vals.get('GOOGLE_CLIENT_ID',''))}",
]
out.write_text("\n".join(lines) + "\n")
PY
# shellcheck disable=SC1090
source "$ENV_FILE"

[[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_ANON_KEY:-}" ]] || fail "empty SUPABASE_URL / ANON_KEY"
ok "Secrets loaded (${SUPABASE_URL})"

python3 - <<'PY' || fail "Google provider not enabled on Auth settings"
import json, os, urllib.request
url=os.environ["SUPABASE_URL"].rstrip("/")+"/auth/v1/settings"
req=urllib.request.Request(url, headers={"apikey": os.environ["SUPABASE_ANON_KEY"]})
with urllib.request.urlopen(req) as resp:
    d=json.load(resp)
g=d.get("external",{}).get("google")
assert g is True or (isinstance(g, dict) and g.get("enabled") is True), d.get("external")
print("google=", g)
PY
ok "Google provider enabled (auth/v1/settings)"

python3 - "$ROOT" "$REF" <<'PY' || fail "playlist-covers bucket missing"
import json, subprocess, sys, urllib.request
root, ref = sys.argv[1], sys.argv[2]
rows=json.loads(subprocess.check_output(
    ["supabase","projects","api-keys","--project-ref",ref,"-o","json"],
    cwd=root, text=True,
))
srv=next(r["api_key"] for r in rows if r.get("name")=="service_role" or r.get("id")=="service_role")
req=urllib.request.Request(
    f"https://{ref}.supabase.co/storage/v1/bucket",
    headers={"apikey": srv, "Authorization": f"Bearer {srv}"},
)
with urllib.request.urlopen(req) as resp:
    data=json.load(resp)
b=next(x for x in data if (x.get("id") or x.get("name"))=="playlist-covers")
assert b.get("public") is True
print("playlist-covers", {k:b.get(k) for k in ("id","public","file_size_limit","allowed_mime_types")})
PY
ok "Storage bucket playlist-covers present"

rg -q 'ytlite://auth-callback' "$ROOT/ios/YTLite/Auth/AuthService.swift" \
  || fail "AuthService missing ytlite://auth-callback"
rg -q '<string>ytlite</string>' "$ROOT/ios/YTLite/Info.plist" \
  || fail "Info.plist missing ytlite URL scheme"
ok "iOS code uses ytlite://auth-callback + URL scheme"

python3 - "$REF" <<'PY' || fail "Dashboard Redirect URLs missing ytlite://auth-callback"
import base64, json, subprocess, sys, urllib.request
ref=sys.argv[1]
raw=subprocess.check_output(
    ["security","find-generic-password","-s","Supabase CLI","-w"], text=True
).strip()
token=base64.b64decode(raw.split(":",1)[1]).decode().strip() if raw.startswith("go-keyring-base64:") else raw
req=urllib.request.Request(
    f"https://api.supabase.com/v1/projects/{ref}/config/auth",
    headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "User-Agent": "YTLite-iOS-Setup/1.0",
    },
)
with urllib.request.urlopen(req) as resp:
    cfg=json.load(resp)
uri=cfg.get("uri_allow_list") or cfg.get("URI_ALLOW_LIST") or ""
items=[u.strip() for u in uri.split(",") if u.strip()]
assert "ytlite://auth-callback" in items, items
assert cfg.get("external_google_enabled") is True
cid=cfg.get("external_google_client_id") or ""
assert cid.endswith(".apps.googleusercontent.com"), cid
print("uri_allow_list=", ",".join(items))
print("site_url=", cfg.get("site_url"))
print("external_google_client_id=", cid)
print("expected_google_cloud_redirect=", f"https://{ref}.supabase.co/auth/v1/callback")
PY
ok "Dashboard Redirect URL + Google provider config"

echo
echo "Automated checks passed."
echo "Manual (device): Google sign-in → session; playlist cover upload under playlist-covers/{uid}/; same account on Android."
