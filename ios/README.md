# YTLite iOS

Specs: [`prd/IOS_MVP_SCOPE.md`](../prd/IOS_MVP_SCOPE.md)

## Setup

```bash
cd ios
xcodegen generate
open YTLite.xcodeproj
```

Configure Supabase redirect URL `ytlite://auth-callback` for Google OAuth.

## Features

- Tabs: **Home / Shorts / Search / You / Library**
- Extractor + play queue + speed + Share
- SwiftData library + Supabase auth/sync
- **PiP** via `AVPlayerViewController`
- **Lyrics** caption sheet (VTT)
- **You**: Liked, Trending music, channel/playlist deep browse

Still later: Cookie Web login, Data API subscriptions (needs YouTube OAuth token).

Shared assets: [`shared/extractor/`](../shared/extractor/)
