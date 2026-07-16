# YTLite iOS

Specs: [`prd/IOS_MVP_SCOPE.md`](../prd/IOS_MVP_SCOPE.md)

## Setup

```bash
cd ios
xcodegen generate
open YTLite.xcodeproj
```

### Supabase（与 Android 同一项目）

库表 / RLS / Storage 与 Android **共用**，不必新建项目或复制表。iOS 增量配置：

1. **密钥**（gitignored）— 从 Android `local.properties` 同步：

```bash
./scripts/sync_ios_supabase_secrets.sh
```

写入 [`ios/Config/Secrets.xcconfig.local`](Config/Secrets.xcconfig.local)：`SUPABASE_URL`、`SUPABASE_ANON_KEY`（可选 `GOOGLE_CLIENT_ID`、`YOUTUBE_DATA_API_KEY`）。

2. **Auth Redirect URL**（iOS OAuth 必配；Android ID Token 不需要）：

Dashboard → Authentication → URL Configuration → Redirect URLs 增加：

`ytlite://auth-callback`

或 CLI（需已 `supabase login`）：

```bash
./scripts/configure_ios_supabase_auth.sh
```

3. **核验** Google Provider、桶 `playlist-covers`、Redirect、本地密钥：

```bash
./scripts/smoke_ios_supabase.sh
```

4. **手动验收**：App 内 Google 登录回跳成功 → 建歌单/改封面出现在 Storage `playlist-covers/{user_id}/` → 同账号 Android 能拉到库。

URL Scheme `ytlite` 已在 `Info.plist`；登录代码见 `AuthService`（`redirectTo: ytlite://auth-callback`）。

Google Cloud Web 客户端的 Authorized redirect 应为  
`https://<project-ref>.supabase.co/auth/v1/callback`（指向 Supabase，不是 `ytlite://`）。

## Features

- Tabs: **Home / Shorts / Search / You / Library**
- Extractor + play queue + speed + Share
- SwiftData library + Supabase auth/sync
- **PiP** via `AVPlayerViewController`
- **Lyrics** caption sheet (VTT)
- **You**: Liked, Trending music, channel/playlist deep browse

Still later: Cookie Web login, Data API subscriptions (needs YouTube OAuth token).

Shared assets: [`shared/extractor/`](../shared/extractor/)
