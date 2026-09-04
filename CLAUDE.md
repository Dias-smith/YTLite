# CLAUDE.md

Instructions for background AI agents (Claude Code CLI, Aider, Codex, etc.) working on this repository.

This is a **monorepo**. The iOS app lives under `ios/`. Do not treat the Android `app/` tree as the iOS source of truth.

---

## Project Overview

| Field | Value |
|-------|--------|
| Display name | Mixtube |
| Xcode project | `ios/YTLite.xcodeproj` |
| Project / Target name | `YTLite` |
| **Scheme Name** | `YTLite` |
| **Bundle ID** | `com.ytlite.player` |
| Product name (`PRODUCT_NAME`) | `Mixtube` (produces `Mixtube.app`) |
| Default Simulator | `iPhone 17 Pro` |
| Language | Swift 5.0 |
| Minimum iOS | 17.0 (`TARGETED_DEVICE_FAMILY` = iPhone + iPad) |
| UI framework | SwiftUI (primary) + UIKit bridges |
| Persistence | SwiftData |
| Project generator | XcodeGen (`ios/project.yml`) |

There is no `.xcworkspace` at the repo root. Open `ios/YTLite.xcodeproj`. SPM packages (Supabase, Firebase, GoogleMobileAds) are resolved by the project.

### Build / run (iOS)

Work from `ios/` unless noted. Always use scheme `YTLite` and destination `iPhone 17 Pro`.

```bash
cd ios
xcodebuild -scheme YTLite -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Regenerate the Xcode project only when `ios/project.yml` or source groups change — and only after explicit permission:

```bash
cd ios && xcodegen generate
```

Secrets: `ios/Config/Secrets.xcconfig.local` (gitignored). Sync from Android `local.properties` via `./scripts/sync_ios_supabase_secrets.sh`.

### Monorepo map

| Path | Role |
|------|------|
| `ios/` | Mixtube iOS (this CLAUDE.md’s primary target) |
| `app/` | Android (Jetpack Compose) — feature parity reference, not iOS code |
| `prd/` | Product specs (`prd/IOS_MVP_SCOPE.md` for iOS) |
| `shared/resolution/` | Cross-platform stream-resolver assets |
| `supabase/` | Shared cloud schema / migrations |
| `website/` | Marketing / GitHub Pages |

---

## Code Style & Architecture

### Language & UI

- **Swift 5** / **SwiftUI** for screens, chrome, sheets, and lists.
- **UIKit** is used only where SwiftUI is insufficient: `UIApplicationDelegate`, `AVPlayerViewController` PiP, AdMob / UMP, some media and orientation helpers.
- Prefer Swift concurrency (`async`/`await`, `Task`) over new Combine pipelines. Existing `ObservableObject` + Combine (`@Published`, `AnyCancellable`) is the dominant view-model style — match it in the same file/module.
- `@MainActor` on types that own UI state (`*Controller`, `*ViewModel`, `*Store`, `*Service` that publish).

### Architecture (MVVM + domain stores)

Not a strict Clean Architecture / TCA app. Pattern in practice:

| Layer | Typical types | Location |
|-------|----------------|----------|
| Views | `*View`, `*Sheet`, `*Host` | `ios/YTLite/UI/<Feature>/` |
| View models / presenters | `*ViewModel`, `*Presenter`, `*Presentation` | Next to the view, or `UI/<Feature>/` |
| App / session state | `AppModel`, `PlaybackController`, `AuthService` | Injected as `@EnvironmentObject` from `YTLiteApp` / `RootView` |
| Persistence stores | `*Store` (`LibraryStore`, `ThemeStore`, `HomeFeedStore`, …) | Domain folders (`Library/`, `UI/Theme/`, …) |
| Network | `*Client`, `*Service` | `Network/`, `Auth/`, `Captions/`, `Resolution/` |
| Models | `VideoItem`, `SearchHit`, SwiftData `@Model` types | `Models/`, `Library/LibraryModels.swift` |

- Screens: `struct FooView: View` with `@StateObject` for a local VM and `@EnvironmentObject` for shared session objects.
- Shared session objects: `PlaybackController`, `AppModel`, `AuthService`, `TrackActionPresenter`, `PlaylistActionPresenter`, `PlayerPresentation`.
- New persistence types: `*Store`. New network facades: `*Service` or `*Client`. Action sheets: `*Presenter` + `*Sheet` + `*Context`.
- `LibraryStore` uses `@Observable` (Observation); most other VMs still use `ObservableObject`. Do not migrate a type’s observation style in a drive-by change.

### Module layout (`ios/YTLite/`)

Keep new files in the existing domain folder. Do not flatten or invent parallel trees.

- `App/` — bootstrap, language, orientation, review prompts, Firebase
- `UI/` — `Home`, `Search`, `You`, `Library`, `Shorts`, `Player`, `Settings`, `Chrome`, `Theme`, `Auth`, `TrackAction`, `PlaylistAction`
- `Playback/` — queue, AVPlayer, PiP, session, sleep timer
- `Library/` — SwiftData models + `LibraryStore`
- `Auth/` — Supabase / Apple / Google + library sync
- `Network/` — InnerTube, YouTube Data API, HTTP
- `Resolution/` — stream resolver + remote JS bundle
- `Ads/` — AdMob, UMP/ATT, eligibility
- `Captions/`, `Notifications/`, `Models/`, `AppDebugKit/`

Tabs (see `RootView`): Home / Shorts / Search / You / Library, plus mini player chrome in `AppChrome`.

### Naming

- Types: `UpperCamelCase`. Functions / properties: `lowerCamelCase`.
- Views end in `View` or `Sheet`. Avoid generic names like `ContentView` / `MainView`.
- Localization: `L("key.path")` and `Lf("key.path", args)` from `AppLanguage.swift`. Add keys to `Localizable.xcstrings` — never hard-code user-visible English in UI.
- Theme tokens: `YTLiteColor.*`, `YTLiteType.*`, `YTLiteLayout.*`, `YTLiteAdaptive.*`. Do not introduce ad-hoc `Color.black` / magic font sizes for product UI.
- Probe / debug logs: tagged print such as `[YTLite.HomeFeed]`. Keep behind existing probe types; do not spam production logs.
- URL scheme: `ytlite://` (auth callback `ytlite://auth-callback`). Bundle ID stays `com.ytlite.player` even when the display name is Mixtube.

### UI style to preserve

- Music/YouTube-lite chrome: tab bar + mini player + full-screen player sheet.
- Adaptive iPhone/iPad via `YTLiteAdaptive` (columns, padding, sheet detents, player split layout).
- Theme-driven surfaces (`background`, `surface`, `surfaceElevated`, `accent`, `onSurface`, `onSurfaceVariant`).
- Sheets use existing chrome helpers (`YTLiteSheetChrome`, presentation detents from `YTLiteAdaptive.sheetDetents`).
- Match Android behavior where `prd/android/` specs exist, but implement with current iOS patterns — do not port Compose structure literally.

### Swift hygiene

- Prefer `guard` / early return; avoid force unwrap (`!`) and `try!` except in existing fatal bootstrap paths.
- Keep optionals honest; do not paper over missing data with empty UI that hides errors the surrounding screen already surfaces.
- Mark incomplete work with a short comment only when the surrounding file already does; do not leave `TODO` without a concrete next step.
- Access control: `private` / `private(set)` for VM state that views should not write.

---

## Build & Modification Safety

### Do not touch project config without permission

Do **not** edit these unless the user explicitly asks:

- `ios/YTLite.xcodeproj/project.pbxproj`
- `ios/YTLite.xcodeproj/project.xcworkspace/**`
- `ios/project.yml` (XcodeGen source of truth)
- `ios/YTLite/Info.plist`, entitlements, `*.xcconfig`, `GoogleService-Info.plist`
- Signing (`DEVELOPMENT_TEAM`, capabilities, bundle ID, URL schemes)
- SPM package versions / `Package.resolved`

Adding a new `.swift` file under `ios/YTLite/` is usually picked up because the target uses a folder reference via XcodeGen. If a file must be registered in the pbxproj, **stop and ask** — do not hand-edit UUIDs.

### Before every Swift change

1. Read the surrounding types, call sites, and environment objects. Do not invent parallel state that `PlaybackController` / `AppModel` / `LibraryStore` already own.
2. Keep the change **type-safe**: no implicit `Any`, no unmatched optionals, no incomplete `switch` over public enums.
3. Keep logic **complete**: handle loading, empty, error, and authenticated vs guest where the existing screen already does. Do not leave stub branches that compile but break playback, sync, or navigation.
4. Compile mentally against iOS 17 APIs only (deployment target 17.0).
5. Do not change observation style (`ObservableObject` ↔ `@Observable`) or DI (`EnvironmentObject` ↔ globals) unless that is the task.

### Preserve UI and module boundaries

- Do not restyle screens with a new design system, hardcoded colors, or different tab/navigation structure.
- Put playback code in `Playback/`, ads in `Ads/`, library mutations in `LibraryStore`, UI in `UI/<Feature>/`.
- Do not “simplify” by merging stores, moving files across domains, or rewriting a large `*View.swift` when a local fix suffices.
- Cross-platform: iOS and Android share product behavior and Supabase schema, not UI code. Do not copy Android packages into iOS.

### Secrets and generated files

Never commit or inline: `Secrets.xcconfig.local`, API keys, anon keys, `GoogleService-Info.plist` values, or `.env`. Do not regenerate `project.pbxproj` via XcodeGen as a side effect of a UI tweak.

### Preferred edit loop

1. Smallest Swift change that implements the request.
2. Match naming, tokens, and folder of neighboring files.
3. If a build is needed, use scheme `YTLite` on simulator `iPhone 17 Pro`.
4. If XcodeGen or pbxproj must change, explain why and wait for approval.
