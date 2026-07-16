# YTLite

Hybrid YouTube / music-style client.

| Path | Role |
|------|------|
| [`app/`](app/) | Android (Compose) |
| [`ios/`](ios/) | iOS (SwiftUI) — see [`ios/README.md`](ios/README.md) |
| [`website/`](website/) | Marketing / support site (static) — GitHub Pages |
| [`prd/`](prd/) | Product specs — start at [`prd/ANDROID_FEATURE_INDEX.md`](prd/ANDROID_FEATURE_INDEX.md) |
| [`supabase/`](supabase/) | Shared cloud schema |
| [`shared/extractor/`](shared/extractor/) | Cross-platform JS stream extractor assets |

iOS MVP priorities: [`prd/IOS_MVP_SCOPE.md`](prd/IOS_MVP_SCOPE.md).

## Website (GitHub Pages)

Static files live in [`website/`](website/) (landing, privacy, terms, support).

**Production URL:** [https://ytlite.cc/](https://ytlite.cc/)  
**Contact:** [jimo.cgg@gmail.com](mailto:jimo.cgg@gmail.com)

### Enable Pages + custom domain

1. GitHub → **Settings → Pages**
2. **Build and deployment → Source** 必须选 **GitHub Actions**（不要选 “Deploy from a branch”）
3. 打开 **Actions** → 工作流 **Deploy website to GitHub Pages** → **Run workflow**（选 `ios` 分支）
4. **Custom domain** = `ytlite.cc` → Save → 等 DNS check 变绿 → 勾选 **Enforce HTTPS**

若打开站点看到的是仓库 README（路径表 `app/` `ios/`…），说明 Pages 仍在发布**分支根目录**，请回到步骤 2 改为 GitHub Actions 并手动跑一次 workflow。

正式站内容来自 [`website/`](website/)（落地页等），不是根目录 README。

### DNS (`ytlite.cc`)

| Type | Host | Value |
|------|------|-------|
| A | `@` | `185.199.108.153` |
| A | `@` | `185.199.109.153` |
| A | `@` | `185.199.110.153` |
| A | `@` | `185.199.111.153` |
| CNAME | `www` | `<owner>.github.io` |

Repo includes [`website/CNAME`](website/CNAME) (`ytlite.cc`) so the published site keeps the custom domain.

Local preview:

```bash
cd website && python3 -m http.server 8080
# open http://127.0.0.1:8080/
```

Replace App Store / Play CTA links on the landing page when listings go live.
