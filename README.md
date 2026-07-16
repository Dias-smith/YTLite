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

1. GitHub → **Settings → Pages → Source = GitHub Actions**
2. Push to **`ios`** (or `main`/`master`), or run **Deploy website to GitHub Pages** manually
3. **Custom domain** = `ytlite.cc` → Save → wait for DNS check → **Enforce HTTPS**

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
