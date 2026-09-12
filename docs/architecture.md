# Architecture (tech / backend)

## Stack

| Layer | Choice |
|---|---|
| Language | Swift 5 |
| UI | AppKit status item + `NSPopover` hosting SwiftUI |
| Build | `swiftc` via `build.sh` (no Xcode project) |
| Networking | `URLSession` |
| Auth | Read-only local credentials already on the Mac |
| Packaging | `.app` bundle, `LSUIElement=true` (menu-bar accessory) |

There is no server, database, or cloud backend for this app. It only **reads local auth** and **calls vendor HTTP APIs**.

## Runtime flow

```text
App launch
  → UsageMonitor starts (immediate refresh + 60s timer)
  → ChatGPTUsageClient + CursorUsageClient + HermesUsageClient + DeepSeekUsageClient fetch in parallel
  → Status item title updates (three configured slots)
  → Hover/click shows PopoverView bound to UsageMonitor
```

## Source files

| File | Role |
|---|---|
| `Sources/App.swift` | `NSApplicationDelegate`, status item title, hover/click popover lifecycle, right-click menu |
| `Sources/UsageMonitor.swift` | Shared models, formatting helpers, polling, menu bar slots + Cursor status-metric preferences, provider status |
| `Sources/ChatGPTUsage.swift` | ChatGPT usage fetch + parse |
| `Sources/CursorUsage.swift` | Cursor token read + usage fetch + parse |
| `Sources/HermesUsage.swift` | Hermes/Nous Portal token read + account fetch + parse |
| `Sources/DeepSeekUsage.swift` | DeepSeek API key read + balance fetch + parse |
| `Sources/PopoverView.swift` | Popover SwiftUI, design tokens, AppKit hosting view controller |
| `Sources/SlotMenu.swift` | Slot menu builder shared by both entry points |

## ChatGPT data path

1. **Auth (read-only):** `~/.codex/auth.json`
   - `tokens.access_token` (or top-level variants)
   - `tokens.account_id` when present
2. **API:** `GET https://chatgpt.com/backend-api/wham/usage`
   - Headers: `Authorization: Bearer <token>`, optional `ChatGPT-Account-Id`, `User-Agent: codex_cli_rs/widget`
3. **Parsed fields:**
   - `plan_type`
   - `rate_limit.primary_window` → 5-hour meter (`used_percent`, `reset_at`, `limit_window_seconds`)
   - `rate_limit.secondary_window` → 7-day meter

Credentials are never written back. A 401/403 surfaces as “sign in again.”

## Cursor data path

1. **Auth (read-only):** JWT from Cursor SQLite
   - `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
   - Fallback: Cursor Insiders path
   - Query: `ItemTable` key `cursorAuth/accessToken` via `/usr/bin/sqlite3` (`mode=ro&immutable=1`)
2. **API:** `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`
   - Body: `{}`
   - Headers include `Authorization: Bearer <jwt>`, `Connect-Protocol-Version: 1`, and `Cookie: WorkosCursorSessionToken=<sub>%3A%3A<jwt>`
3. **Parsed `planUsage` fields:**
   - `autoPercentUsed` → **Cursor Models** (popover; optional menu-bar `C`)
   - `apiPercentUsed` → **Other Models** (popover; default menu-bar `C`)
   - `totalSpend` / `includedSpend` / `limit` kept on the model but not primary UI
   - `billingCycleEnd` → cycle reset text
4. **Menu-bar Cursor metric:** `UsageMonitor.cursorStatusMetric` (`CursorStatusMetric`), persisted as `UserDefaults` key `cursorStatusMetric` (default `otherModels`). Changing it calls `onChange` so the status item redraws immediately. Switch via the column radio in the popover or the status-item right-click menu.

### Important Cursor caveat

`totalPercentUsed` is **not** the same as `includedSpend / limit`. Cursor exposes separate Auto/API-style percentages. The app prefers the bucket fields so the UI matches Cursor Settings → Usage (“Cursor Models” / “Other Models”).

## Hermes / Nous Portal data path

1. **Auth (read-only):** `~/.hermes/auth.json`
   - `providers.nous.access_token` (fallback `agent_key`)
   - `providers.nous.portal_base_url` when present (else `https://portal.nousresearch.com`)
   - If `expires_at` / JWT `exp` is in the past (15s skew), Catel does **not** refresh; it asks you to open Hermes
2. **API:** `GET {portal}/api/oauth/account`
   - Header: `Authorization: Bearer <token>`
3. **Parsed fields:**
   - `subscription.plan` → popover tag
   - `subscription.monthly_credits` + `subscription.credits_remaining` → `% used` for menu-bar `N` (skip `%` when remaining exceeds the monthly cap / rollover)
   - `paid_service_access.purchased_credits_remaining` (or top-level) → optional top-up line
   - `subscription.current_period_end` → cycle reset text

### Important Hermes caveat

Nous Portal **refresh tokens are single-use**. Calling `POST /api/oauth/token` from Catel would rotate the token and can revoke Hermes’s session. Catel only **reads** the current access token that Hermes already wrote. If that JWT expires, open Hermes Agent so its keepalive can refresh `auth.json`.

## DeepSeek data path

1. **Auth (read-only):** `DEEPSEEK_API_KEY` parsed out of `~/.hermes/.env` (supports `export ` prefix and quoted values); the file is only read, never written
2. **API:** `GET https://api.deepseek.com/user/balance`
   - Header: `Authorization: Bearer <key>`
3. **Parsed fields:**
   - `balance_infos[]` → prefers the `USD` entry, falls back to the first
   - `total_balance` → menu-bar `D` (`$` formatted)
   - `granted_balance` / `topped_up_balance` kept on the model
   - `is_available` → drives the “no balance on this account” message

DeepSeek has no percent concept, so it renders as a balance row rather than a meter.

### Unofficial endpoints

Every endpoint used here is **unofficial / undocumented** and can change: ChatGPT `wham/usage`, Cursor `GetCurrentPeriodUsage`, and the Nous Portal account API. The DeepSeek balance endpoint is documented.

## Menu bar slots

- `UsageMonitor.menuBarSlots` holds exactly `UsageMonitor.menuBarSlotCount` (3) `MenuBarProvider` values in display order, persisted as a `UserDefaults` array under `menuBarSlots` (default `[chatGPT, cursor, hermes]`)
- `MenuBarProvider`: `chatGPT` (`G`), `cursor` (`C`), `hermes` (`N`, titled “Nous”), `deepSeek` (`D`), `none` (hidden)
- `loadMenuBarSlots()` drops duplicate providers, allows at most `menuBarSlotCount - 1` (2) hidden slots, backfills the rest from real providers, and therefore migrates a store written by the two-slot version without losing it
- `setMenuBarSlot(_:at:)` swaps when the chosen provider already occupies another slot, so slots stay distinct; `none` is refused when every other slot is already hidden
- The slot menu is built by `SlotMenuFactory` (`Sources/SlotMenu.swift`) for both the popover picker and the status-item right-click submenus. It sets `autoenablesItems = false`, because AppKit's automatic enabling re-enables any item whose target responds to the action at display time, undoing an explicit `isEnabled = false`. `None` is then simply disabled: AppKit greys it out and refuses the click
- Quick switching also lives in the status-item right-click menu as one “Menu bar slot N” submenu per slot
- Values come from `UsageMonitor.value(for:)`: percent for quota providers, `$` balance for DeepSeek

## Polling & freshness

- Timer: **60s**
- On hover: refresh if last success is older than 60s (`refreshIfStale`)
- Concurrent refreshes are skipped while the provider requests are in flight (`pendingRequests` counter)
- Failures keep last good snapshot and mark provider status `stale` / `unavailable`

## Read-only guarantee

The app makes no writes to any credential or data file. The only `FileManager`/`Process` reads are:

- `Data(contentsOf:)` for `~/.codex/auth.json` and `~/.hermes/auth.json`, with `.mappedIfSafe` (mapped read, no write)
- `String(contentsOf:)` for `~/.hermes/.env`, to pull `DEEPSEEK_API_KEY`
- `/usr/bin/sqlite3` opened with `-readonly` against `file:<db>?mode=ro&immutable=1`, selecting one `ItemTable` row

Nothing calls `write`, `createFile`, `setAttributes`, or any mutating API. The only persisted state is `UserDefaults` (`menuBarSlots`, `cursorStatusMetric`).

## Error model

`UsageClientError` → user-facing strings:

- Missing credentials → open Codex/Cursor/Hermes and sign in
- 401/403 → sign in again
- Network / invalid JSON → usage unavailable / stale note

## App packaging

- `Info.plist`: bundle id `com.mark.catel`, `LSUIElement`, `CFBundleIconFile=AppIcon`
- `build.sh`: compile sources → copy plist → build `.icns` from `Resources/AppIcon-source.png` (full iconset incl. `@2x`) → copy into `Contents/Resources/`

## Security notes

- Tokens stay on disk where Codex/Cursor/Hermes already store them; this app only reads them
- Do not log tokens, cookies, or raw auth JSON
- Do not write Codex `auth.json`, Hermes `auth.json`, or Cursor DB (refresh-token writes can log the user out)
- No telemetry or outbound calls other than the four provider APIs above
- The only persisted state is the menu bar slot selection and Cursor bucket preference in `UserDefaults`

## When changing backend behavior

Update this file if you change endpoints, auth sources, which Cursor percentage maps to `C`, Hermes credit math, DeepSeek balance handling, menu bar slots, polling, or packaging.
