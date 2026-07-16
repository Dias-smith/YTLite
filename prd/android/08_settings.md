# 08 — Settings

## Entry

Library → Settings; also reachable from Downloads Hub.

## Rows

| Row | Control | Persistence / effect |
|-----|---------|----------------------|
| Night mode | Switch | `app_preferences.night_mode_enabled` (default on); theme recreate |
| Language | Sheet: System / English / 中文 | `app_language`; `Activity.recreate()` |
| Notifications | Navigate | System app notification settings |
| Rate us | Intent | Play Store / market |
| Feedback | Intent | `mailto:` |
| Download threads | Choice 1/2/4/8 | `download_preferences.thread_count` (default 2) |
| Download resume | Switch | `resume_enabled` (default true) |
| Download Wi‑Fi only | Switch | `wifi_only` (default false) |
| Default download format | Ask / Audio fast / 360p / 720p | `default_format` |

## Non-goals

- Manual “Sync now” button (sync is repository-driven)
- In-app notification preferences beyond system deep-link
- Cast setup beyond separate share/cast stub helpers

## Acceptance

- Toggling night mode and language visibly applies after recreate.
- Download prefs affect subsequent enqueue behavior.
