---
name: mac-dmg-release
description: >-
  Builds, Developer ID signs, notarizes, and staples the Mixtube Mac Catalyst
  DMG so other Macs can install it. Use when the user asks to package, ship,
  release, notarize, or build the Mac DMG, 打包, 发版, 公证, or Mixtube.dmg.
---

# Mac DMG release

When the user asks to package or ship the Mac app, run the script. Do not print the steps and stop. Do not rebuild `ios/build/Mixtube.dmg` by copying a Debug or Apple Development app.

## Execute

From the repo root, with full permissions (keychain, notarization, disk images). Archive plus notarization can take 20 minutes. Set `block_until_ms` to at least `1200000`.

```bash
bash .cursor/skills/mac-dmg-release/scripts/package.sh
```

The script archives scheme `YTLite Mac` (Release, Mac Catalyst), exports with Developer ID team `8S748AQ4H7`, writes `ios/build/Mixtube.dmg`, notarizes with keychain profile `mixtube`, staples the ticket, and checks Gatekeeper.

## After it finishes

Tell the user the DMG path. Success is `spctl` reporting `accepted` and `source=Notarized Developer ID`. They can send `ios/build/Mixtube.dmg`. Do not install over `/Applications/Mixtube.app`, commit, or deploy the website unless they ask.

## If it fails

Read `ios/build/package-mac.log`. Fix only the packaging failure and run the script again.

- Missing profile `mixtube`: stop. The user must run `notarytool store-credentials` once. Do not invent an Apple ID or app-specific password.
- Notarization rejected: `xcrun notarytool log <submission-id> --keychain-profile mixtube`, then fix the reported signature or entitlement problem.
- Unmount with `hdiutil detach`. `diskutil image detach` is not a valid command.

Every new DMG needs a new notarization. The Developer ID certificate and the `mixtube` keychain profile do not.
