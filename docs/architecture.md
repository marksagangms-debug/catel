# Architecture (tech / backend)

## Stack

| Layer | Choice |
|---|---|
| Language | Swift 5 |
| UI | AppKit status item + `NSPopover` hosting SwiftUI; one AppKit `NSWindow` for Settings |
| Build | `swiftc` via `build.sh` (no Xcode project) |
| Networking | `URLSession` |
| Auth | Read-only local credentials already on the Mac, plus optional API keys saved in Catel Settings |
| Credential storage | `~/Library/Application Support/Catel/credentials.json` (0600, this app only) |
| Packaging | `.app` bundle, `LSUIElement=true` (menu-bar accessory) |

There is no server, database, or cloud backend for this app. It only **reads local auth** and **calls vendor HTTP APIs**. The one file it writes is its own key store; it never writes another app's credential file.

## Runtime flow

```text
App launch
  → UsageMonitor starts (immediate refresh + 60s timer)
  → ProviderAvailability checks credential presence (local files + keys saved in Settings)
  → ChatGPTUsageClient + CursorUsageClient + HermesUsageClient + DeepSeekUsageClient + OpenCodeUsageClient + CommandCodeUsageClient fetch in parallel
  → Status item title updates (three configured slots, with missing providers hidden)
  → Hover/click shows PopoverView bound to UsageMonitor
  → Right-click → "Settings…" (or the popover footer gear) opens the key panel
```

## Source files

| File | Role |
|---|---|
| `Sources/App.swift` | `NSApplicationDelegate`, status item title, hover/click popover lifecycle, right-click menu, Settings window presentation |
| `Sources/UsageMonitor.swift` | Shared models, formatting helpers, polling, menu bar slots + Cursor status-metric preferences, provider status |
| `Sources/ProviderAvailability.swift` | Which providers have credentials (local files and/or saved keys) |
| `Sources/ProviderCredentials.swift` | `CredentialProvider` (key-based providers) + `CredentialVault` (local-only key store) |
| `Sources/ChatGPTUsage.swift` | ChatGPT usage fetch + parse |
| `Sources/CursorUsage.swift` | Cursor token read + usage fetch + parse |
| `Sources/HermesUsage.swift` | Hermes/Nous Portal token read + account fetch + parse |
| `Sources/DeepSeekUsage.swift` | DeepSeek API key read (Settings key first) + balance fetch + parse |
| `Sources/OpenCodeUsage.swift` | OpenCode Go key read (Settings key first) + limit-window fetch + parse |
| `Sources/CommandCodeUsage.swift` | CommandCode key read (Settings key first) + caps/plan-credit fetch + parse |
| `Sources/PopoverView.swift` | Popover SwiftUI, design tokens, AppKit hosting view controller |
| `Sources/SettingsView.swift` | Settings panel SwiftUI (`CatelSettingsView`) + `SettingsWindowController` |
| `Sources/SlotMenu.swift` | Slot menu builder shared by both entry points |

## Settings / provider API keys

Three providers authenticate with a plain API key, so Catel lets you paste one instead of depending on another app's files:

| Provider | Saved-key name in the store | Fallback source when nothing is saved |
|---|---|---|
| DeepSeek | `deepSeek` | `DEEPSEEK_API_KEY` in `~/.hermes/.env` |
| CommandCode | `commandCode` | `COMMANDCODE_API_KEY` in `~/.hermes/.env` |
| OpenCode Go | `openCode` | `opencode-go.key` in `~/.local/share/opencode/auth.json` |

1. **Precedence:** each of those clients calls `CredentialVault.shared.key(for:)` first and returns the saved key when present; only otherwise does it fall back to the vendor file. The provider therefore works with Hermes (or OpenCode) not installed at all.
2. **Store:** `~/Library/Application Support/Catel/credentials.json`, JSON keyed by the provider's raw name, written with `0600` inside a `0700` directory. `.atomic` writes replace the file, so the mode is re-applied after every save. Clearing the last key deletes the file.
3. **Local only:** the vault is cached in memory behind an `NSLock` for background fetches. Nothing syncs, uploads, or logs it.
4. **Availability:** `ProviderAvailability.make(homeDirectory:savedKeys:)` treats a saved key as configured, so the provider appears in the popover and slot menus with no local file present. `ProviderAvailability.detectedLocally(_:)` answers "is the fallback file there?" for the Settings status badge.
5. **Settings window:** `CatelSettingsView` + `SettingsWindowController`, built by hand: an `LSUIElement` accessory app owns no main menu, so SwiftUI's `Settings` scene has no menu item to open it. Entry points are the right-click menu (`Settings…`, ⌘,) and the popover footer gear, which closes the popover first.
6. **Test:** the panel's `Test` button runs the provider's own client, so it validates whichever source is in effect (saved key or fallback file) and reports the real API result.
7. **Read-only providers stay read-only:** ChatGPT, Cursor, and Nous are listed with their detected status but have no key field. Nous in particular stays on the local Hermes token, because Portal refresh tokens are single-use.

## ChatGPT data path

1. **Auth (read-only):** `~/.codex/auth.json`
   - `tokens.access_token` (or top-level variants)
   - `tokens.account_id` when present
2. **API:** `GET https://chatgpt.com/backend-api/wham/usage`
   - Headers: `Authorization: Bearer *** optional `ChatGPT-Account-Id`, `User-Agent: codex_cli_rs/widget`
3. **Parsed fields:**
   - `plan_type`
   - `rate_limit.primary_window` → 5-hour meter (`used_percent`, `reset_at`, `limit_window_seconds`)
   - `rate_limit.secondary_window` → 7-day meter
4. **Menu-bar `G` window:** `UsageMonitor.chatGPTStatusMetric` (`ChatGPTSessionWindow`), persisted as `UserDefaults` key `chatGPTStatusMetric` (default `fiveHour`). The compact `5h / W` title selector is the only control; both window columns are display-only.

Credentials are never written back. A 401/403 surfaces as “sign in again.”

## Cursor data path

1. **Auth (read-only):** JWT from Cursor SQLite
   - `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
   - Fallback: Cursor Insiders path
   - Query: `ItemTable` key `cursorAuth/accessToken` via `/usr/bin/sqlite3` (`mode=ro&immutable=1`)
2. **API:** `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`
   - Body: `{}`
   - Headers include `Authorization: Bearer *** `Connect-Protocol-Version: 1`, and `Cookie: WorkosCursorSessionToken=<sub>%3A%3A<jwt>`
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
   - Header: `Authorization: Bearer ***
3. **Parsed fields:**
   - `subscription.plan` → popover tag
   - `subscription.monthly_credits` + `subscription.credits_remaining` → `% used` for menu-bar `N` (skip `%` when remaining exceeds the monthly cap / rollover)
   - `paid_service_access.purchased_credits_remaining` (or top-level) → optional top-up line
   - `subscription.current_period_end` → cycle reset text

### Important Hermes caveat

Nous Portal **refresh tokens are single-use**. Calling `POST /api/oauth/token` from Catel would rotate the token and can revoke Hermes’s session. Catel only **reads** the current access token that Hermes already wrote. If that JWT expires, open Hermes Agent so its keepalive can refresh `auth.json`. This is also why Nous has no key field in Settings: a pasted access token would expire with nothing here able to renew it.

## DeepSeek data path

1. **Auth:** a key saved in Catel Settings, else `DEEPSEEK_API_KEY` parsed out of `~/.hermes/.env` (supports `export ` prefix and quoted values); that file is only read, never written
2. **API:** `GET https://api.deepseek.com/user/balance`
   - Header: `Authorization: Bearer ***
3. **Parsed fields:**
   - `balance_infos[]` → prefers the `USD` entry, falls back to the first
   - `total_balance` → menu-bar `D` (`$` formatted)
   - `granted_balance` / `topped_up_balance` kept on the model
   - `is_available` → drives the “no balance on this account” message

DeepSeek has no percent concept, so it renders as a balance row rather than a meter.

## OpenCode Go data path

1. **Auth:** a key saved in Catel Settings, else `~/.local/share/opencode/auth.json`
   - `opencode-go.key` (what `opencode providers` / `/connect` writes)
2. **API:** `GET https://opencode.ai/zen/go/v1/usage`
   - Header: `Authorization: Bearer ***
3. **Parsed fields:** `usage.rolling` (5-hour), `usage.weekly`, `usage.monthly`
   - each window: `percent` → `% used`, `resetsAt` (ISO-8601) → reset countdown
   - `windowSeconds` is set client-side (5h / 7d / 30d) for reference only
4. **Menu-bar `O` window:** `UsageMonitor.openCodeStatusMetric` (`UsageWindowMetric`), persisted as `UserDefaults` key `openCodeStatusMetric` (default `fiveHour`). The compact title selector is the only control; the three window columns are display-only. Changing the selector redraws the status item immediately.

### Important OpenCode caveat

OpenCode Go limits are dollar-denominated and **per model** (the monthly allowance differs by model: $15, $30, or $60), but the usage endpoint reports a single percentage per window, already normalised against whatever model mix you actually used. Catel shows that percentage rather than recomputing dollars, so no model-price table is needed. This endpoint is not documented as a public API; it is the one the OpenCode console/TUI reads.

## CommandCode data path

1. **Auth:** a key saved in Catel Settings, else `~/.hermes/.env`, line `COMMANDCODE_API_KEY=...` (the key Hermes stores for its CommandCode provider; quotes are stripped)
2. **API (two GETs in parallel, same key):**
   - `GET https://api.commandcode.ai/alpha/billing/credits` → `credits.monthlyCredits|purchasedCredits|freeCredits` (wallet) + `windowLimits.fiveHour|weekly` (each `{used, cap, resetAt}` epoch ms)
   - `GET https://api.commandcode.ai/alpha/billing/subscriptions` → `data.planId` (e.g. `individual-goat`), `data.status`, `data.currentPeriodEnd`
3. **Parsed windows:** `fiveHour` and `weekly` are `used / cap` percentages; `monthly` is plan credits used (pool = `max(planCredits, monthlyRemaining) + purchased + free`), reset = billing period end. With no active plan (pay-as-you-go) the monthly bar is omitted: the CLI's spend-based pool needs the usage-summary endpoint Catel does not call.
4. **Plan catalog** mirrors the CLI's table (longest-prefix match): Ultra 300, Provider 15, GOAT 70, Max 150, Pro-v1 80, Teams Pro 40, Go 10, Pro 30.
5. **Menu-bar `CC` window:** `UsageMonitor.commandCodeStatusMetric`, persisted as `UserDefaults` key `commandCodeStatusMetric` (default `fiveHour`). The compact title selector updates it immediately; the three window columns are display-only.

These endpoints are the ones the CommandCode CLI's `/usage` meter reads (`/alpha/*`), not the public Provider API (`/provider/v1/*` has no usage route).

### Unofficial endpoints

Every endpoint used here is **unofficial / undocumented** and can change: ChatGPT `wham/usage`, Cursor `GetCurrentPeriodUsage`, the Nous Portal account API, the OpenCode Go usage endpoint, and the CommandCode `/alpha/billing/*` endpoints. The DeepSeek balance endpoint is documented.

## Menu bar slots

- `UsageMonitor.menuBarSlots` holds exactly `UsageMonitor.menuBarSlotCount` (3) `MenuBarProvider` values in display order, persisted as a `UserDefaults` array under `menuBarSlots` (default `[chatGPT, cursor, hermes]`)
- `MenuBarProvider`: `chatGPT` (`G`), `cursor` (`C`), `hermes` (`N`, titled “Nous”), `deepSeek` (`D`), `openCode` (`O`, titled “OpenCode”), `commandCode` (`CC`, titled “CmdCode”), `none` (hidden)
- `loadMenuBarSlots()` drops duplicate providers, allows at most `menuBarSlotCount - 1` (2) hidden slots, backfills the rest from real providers, and therefore migrates a store written by the two-slot version without losing it
- `setMenuBarSlot(_:at:)` swaps when the chosen provider already occupies another slot, so slots stay distinct; `none` is refused when every other slot is already hidden
- The slot menu is built by `SlotMenuFactory` (`Sources/SlotMenu.swift`) for both the popover picker and the status-item right-click submenus. It sets `autoenablesItems = false`, because AppKit's automatic enabling re-enables any item whose target responds to the action at display time, undoing an explicit `isEnabled = false`. `None` is then simply disabled: AppKit greys it out and refuses the click
- Quick switching also lives in the status-item right-click menu as one “Menu bar slot N” submenu per slot
- Values come from `UsageMonitor.value(for:)`: percent for quota providers, `$` balance for DeepSeek, and the selected OpenCode/CommandCode window for `O` / `CC`

## Polling & freshness

- Timer: **60s**
- On hover: refresh if last success is older than 60s (`refreshIfStale`)
- Concurrent refreshes are skipped while the provider requests are in flight (`pendingRequests` counter)
- Failures keep last good snapshot and mark provider status `stale` / `unavailable`
- Saving or clearing a key in Settings calls `refreshProviderAvailability()` + `refresh()`, so the menu bar and popover update immediately

## Credential handling

Catel never writes another app's credential or data file. The only file it writes is its own key store.

Reads:

- `Data(contentsOf:)` for `~/.codex/auth.json`, `~/.hermes/auth.json`, and `~/.local/share/opencode/auth.json`, with `.mappedIfSafe` (mapped read, no write)
- `String(contentsOf:)` for `~/.hermes/.env`, to pull `DEEPSEEK_API_KEY` and `COMMANDCODE_API_KEY`
- `/usr/bin/sqlite3` opened with `-readonly` against `file:<db>?mode=ro&immutable=1`, selecting one `ItemTable` row

Writes:

- `~/Library/Application Support/Catel/credentials.json` only, created by `CredentialVault` with `0700` on the directory and `0600` on the file
- Other persisted state is `UserDefaults`: `menuBarSlots`, plus the metric keys (`cursorStatusMetric`, `chatGPTStatusMetric`, `openCodeStatusMetric`, `commandCodeStatusMetric`)

## Error model

`UsageClientError` → user-facing strings:

- Missing credentials → open Codex/Cursor/Hermes and sign in, **or** save a key in Catel Settings
- 401/403 → sign in again
- Network / invalid JSON → usage unavailable / stale note

## App packaging

- `Info.plist`: bundle id `com.mark.catel`, `LSUIElement`, `CFBundleIconFile=AppIcon`
- `build.sh`: compile sources → copy plist → build `.icns` from `Resources/AppIcon-source.png` (full iconset incl. `@2x`) → copy into `Contents/Resources/`; `CATEL_RUN_TESTS=1` also builds and runs the four headless test binaries
- The `swiftc` invocation pins `-target arm64-apple-macos13.0`. Without it the compiler stamped the binary `minos 28.0` (above the host OS 27.0), LaunchServices refused every `open` with error -10825, and only direct execution of the inner binary worked. Run `otool -l Catel.app/Contents/MacOS/Catel | grep minos` if the app "won't open".

## Security notes

- Tokens stay on disk where Codex/Cursor/Hermes already store them; this app only reads them
- Do not log tokens, cookies, or raw auth JSON
- Do not write Codex `auth.json`, Hermes `auth.json`, or Cursor DB (refresh-token writes can log the user out)
- No telemetry or outbound calls other than the six provider APIs above
- Do not write the OpenCode `auth.json` either; the Go key is read-only for Catel
- Do not write `~/.hermes/.env` either; `COMMANDCODE_API_KEY` is read-only for Catel
- Keys typed into Settings are stored only in Catel's own `credentials.json` (`0600`, local, never synced). They are never echoed back into the UI, never logged, and never committed. Never print a saved key from a test harness or a doc

## When changing backend behavior

Update this file if you change endpoints, auth sources, key storage or key precedence, which Cursor percentage maps to `C`, Hermes credit math, DeepSeek balance handling, OpenCode Go window handling, CommandCode caps/plan handling, menu bar slots, polling, or packaging.
