#!/bin/bash
# Archive, Developer ID export, DMG, notarize, and staple Mixtube for other Macs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
IOS="$ROOT/ios"
BUILD="$IOS/build"
APP="$BUILD/export/Mixtube.app"
DMG="$BUILD/Mixtube.dmg"
IDENTITY="Developer ID Application: wei gao (8S748AQ4H7)"
MOUNT="/tmp/mixtube-dmg-check"
LOG="$BUILD/package-mac.log"

mkdir -p "$BUILD"
: > "$LOG"

log() { printf '%s\n' "$*" | tee -a "$LOG"; }

die() { log "ERROR: $*"; exit 1; }

log "Repo: $ROOT"

security find-identity -v -p codesigning 2>/dev/null | grep -F "$IDENTITY" >/dev/null \
  || die "钥匙串里没有 $IDENTITY"

if ! xcrun notarytool history --keychain-profile mixtube >/dev/null 2>&1; then
  die "没有公证凭证 mixtube。先执行：xcrun notarytool store-credentials mixtube --apple-id \"Apple ID邮箱\" --team-id 8S748AQ4H7 --password \"App专用密码\""
fi

detach_path() {
  local target="$1"
  if [ -e "$target" ] || mount | grep -F "$target" >/dev/null 2>&1; then
    hdiutil detach "$target" -force >/dev/null 2>&1 || true
  fi
}

detach_path "$MOUNT"
detach_path "/Volumes/Mixtube"
rmdir "$MOUNT" 2>/dev/null || true

cd "$IOS"

log "Archive YTLite Mac Release"
rm -rf "$BUILD/Mixtube.xcarchive"
xcodebuild -scheme "YTLite Mac" -configuration Release \
  -destination "platform=macOS,variant=Mac Catalyst" \
  -archivePath "$BUILD/Mixtube.xcarchive" \
  -allowProvisioningUpdates archive >>"$LOG" 2>&1

log "Export Developer ID app"
rm -rf "$BUILD/export"
xcodebuild -exportArchive \
  -archivePath "$BUILD/Mixtube.xcarchive" \
  -exportPath "$BUILD/export" \
  -exportOptionsPlist "$SKILL_DIR/ExportOptions-DeveloperID.plist" \
  -allowProvisioningUpdates >>"$LOG" 2>&1

[ -d "$APP" ] || die "导出失败，没有 $APP。看 $LOG"

SIGN_INFO="$(codesign -dv --verbose=4 "$APP" 2>&1)"
printf '%s\n' "$SIGN_INFO" >>"$LOG"
printf '%s\n' "$SIGN_INFO" | grep -F "Authority=$IDENTITY" >/dev/null \
  || die "签名不是 Developer ID。看 $LOG"
ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
printf '%s\n' "$ENTITLEMENTS" | grep -q "get-task-allow" \
  && die "签名里还有 get-task-allow，不能发给别人"

log "Create DMG"
STAGE="$BUILD/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Mixtube.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Mixtube" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >>"$LOG" 2>&1
rm -rf "$STAGE"
codesign --force --sign "$IDENTITY" --timestamp "$DMG" >>"$LOG" 2>&1

log "Notarize"
xcrun notarytool submit "$DMG" --keychain-profile mixtube --wait | tee -a "$LOG"
xcrun stapler staple "$DMG" | tee -a "$LOG"

log "Gatekeeper check"
mkdir -p "$MOUNT"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG" >>"$LOG" 2>&1
set +e
SPCTL="$(spctl -a -vv -t install "$MOUNT/Mixtube.app" 2>&1)"
SPCTL_STATUS=$?
set -e
printf '%s\n' "$SPCTL" | tee -a "$LOG"
hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
rmdir "$MOUNT" 2>/dev/null || true
[ "$SPCTL_STATUS" -eq 0 ] || die "Gatekeeper 拒绝了这个包"
printf '%s\n' "$SPCTL" | grep -q "Notarized Developer ID" \
  || die "来源不是 Notarized Developer ID"

log "DONE $DMG"
