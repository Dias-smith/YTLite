#!/usr/bin/env bash
# Ensure Supabase Auth allows the iOS OAuth deep link.
# Requires: logged-in Supabase CLI (`supabase login`).
set -euo pipefail

REF="${SUPABASE_PROJECT_REF:-qhqrpurbwhitwdelhqwc}"
IOS_REDIRECT="ytlite://auth-callback"

python3 - "$REF" "$IOS_REDIRECT" <<'PY'
import base64, json, subprocess, sys, urllib.request

ref, needed = sys.argv[1], sys.argv[2]

def token() -> str:
    env = __import__("os").environ.get("SUPABASE_ACCESS_TOKEN")
    if env:
        return env.strip()
    raw = subprocess.check_output(
        ["security", "find-generic-password", "-s", "Supabase CLI", "-w"],
        text=True,
    ).strip()
    if raw.startswith("go-keyring-base64:"):
        return base64.b64decode(raw.split(":", 1)[1]).decode().strip()
    return raw

def call(method: str, body: dict | None = None) -> dict:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{ref}/config/auth",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token()}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "YTLite-iOS-Setup/1.0",
        },
    )
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)

cfg = call("GET")
uri = cfg.get("uri_allow_list") or cfg.get("URI_ALLOW_LIST") or ""
items = [u.strip() for u in uri.split(",") if u.strip()]
print("uri_allow_list=", ",".join(items) if items else "(empty)")
print("site_url=", cfg.get("site_url") or cfg.get("SITE_URL"))
print("external_google_enabled=", cfg.get("external_google_enabled"))
print(
    "external_google_client_id=",
    cfg.get("external_google_client_id") or cfg.get("EXTERNAL_GOOGLE_CLIENT_ID"),
)

if needed in items:
    print(f"ok: already present: {needed}")
    raise SystemExit(0)

items.append(needed)
updated = call("PATCH", {"uri_allow_list": ",".join(items)})
uri2 = updated.get("uri_allow_list") or updated.get("URI_ALLOW_LIST") or ""
items2 = [u.strip() for u in uri2.split(",") if u.strip()]
if needed not in items2:
    raise SystemExit(f"error: PATCH did not persist {needed}; got {items2!r}")
print(f"ok: redirect configured: {needed}")
print("uri_allow_list=", ",".join(items2))
PY
