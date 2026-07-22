# AdMob / UMP / ATT (iOS)

## Current status

- Debug uses Google sample IDs; Release uses production IDs via `Config/*.xcconfig` and `Info.plist`.
- Consent via **UMP**; ATT is expected from AdMob console **IDFA Explainer** (no manual `ATTrackingManager` in code).
- Formats: App Open + hot/in-app Interstitial + Rewarded Interstitial.
- Production mapping:
  - App Open (`opening_cold`): `…/7355598026`
  - Hot fallback (`interstitial_hot`): `…/2091542919`
  - In-app (`interstitial_in_app`): `…/7152297900`
  - Rewarded (`interstitial_reward`): `…/8465379577`

## Console checklist (before production)

1. Confirm the AdMob iOS app uses bundle id `com.ytlite.player`.
2. Confirm the four production units above are active.
3. **Privacy & messaging**: publish GDPR (EEA/UK) + **IDFA Explainer**, bind to the app.
4. Keep Debug on Google sample IDs; never copy production IDs into `Debug.xcconfig`.

## App Store Connect privacy

When shipping with ads + IDFA path:

- Does this app use data for tracking? **Yes** (if IDFA used for cross-app ads).
- Third-party advertising: **Yes**
- Data types: Device ID, Advertising Data (and Product Interaction as applicable)

`Info.plist` SKAdNetwork identifiers were checked against Google's current
`admob/ios/privacy/strategies` list on 2026-07-19. Recheck before each release
and add mediation-partner identifiers if mediation is introduced.

## In-app / web policy

- Settings shows **Ad Privacy Choices** when UMP `privacyOptionsRequirementStatus == .required`.
- Website privacy policy documents AdMob, advertising identifiers, and consent management.

## Verify (Console: `YTLite.AdProbe`)

| Scenario | Expect |
|----------|--------|
| Fresh install | `consent.*` then `sdk.start` / loads |
| First tab or play | `app_open.show reason=cold_*` (once) |
| Play ok + ~20s | `interstitial.show reason=play_start` if cooldown ok |
| Close player (chevron or swipe) | `interstitial.show reason=leave_player` if cooldown ok |
| Search results finish loading | `interstitial.show reason=search_results` once per query |
| Background ≥30s → active | hot app open or interstitial |
| Edit info first save today | rewarded ad; reward callback saves and unlocks today |
| Non-basic/custom theme today | rewarded ad; reward callback applies and unlocks today |
| Review sheet visible | ads skipped (`ui_blocked`) |

All ordinary full-screen ads share a 120-second cooldown and a global presentation lock.

## Configuration source

- `Config/Debug.xcconfig`: Google sample IDs.
- `Config/Release.xcconfig`: production IDs.
- `YTLite/Info.plist`: expands the xcconfig values.
- `YTLite/Ads/AdMobConfig.swift`: reads the expanded Info.plist values.
