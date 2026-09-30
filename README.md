# Catel

<img src="Resources/AppIcon-source.png" alt="Catel app icon" width="128" align="right" />

A tiny macOS **menu-bar app** that shows your AI subscription usage at a glance: ChatGPT, Cursor, Nous Portal (Hermes), DeepSeek, OpenCode Go, and CommandCode.

No Dock icon. No account, no server, no telemetry. Catel reads the credentials your other tools already stored on your Mac, and for the key-based providers you can paste an API key into its Settings window instead. Either way it calls the vendor APIs directly and prints the numbers in your menu bar.

```text
G 20% | C 13% | N 7%
```

The three slots are yours to assign, so the bar can show any mix of `G` ChatGPT (selected window), `C` Cursor (selected bucket), `N` Nous subscription credits, `D` DeepSeek balance, `O` OpenCode Go (selected window), and `CC` CommandCode (selected window). The example above is the default layout.

## Features

- **Menu bar at a glance** -- three configurable slots, plain monospaced text, tinted by macOS for light and dark menu bars.
- **Hover popover** -- hover the item (or click to pin it) for the detail:
  - **ChatGPT**: 5-hour and 7-day meters with a compact `5h / W` title selector. The chosen window drives the status bar.
  - **Cursor**: Cursor Models and Other Models meters, billing-cycle reset, radio dot to pick which bucket drives the menu bar.
  - **Nous / Hermes**: subscription meter, credits left of the monthly allowance, top-up line when purchased credits exist, cycle reset.
  - **DeepSeek**: account balance (API account, denominated in USD).
  - **OpenCode Go**: 5-hour / weekly / monthly limit meters with compact window selection. The chosen window drives the menu bar.
  - **CommandCode**: 5-hour / weekly rolling caps + monthly plan-credit meter with compact window selection. The chosen window drives the menu bar (plan tag: GOAT, Pro, Max, ...).
- **Provider API keys in Settings** -- open it from the popover's gear or **Settings…** in the right-click menu. Paste a DeepSeek, CommandCode, or OpenCode Go key and Catel uses that key instead of the file it would otherwise read, so those providers work without Hermes or OpenCode installed. Each row shows whether it is using a saved key or the detected file, and `Save` / `Test` / `Clear` are right there. Keys are stored only in `~/Library/Application Support/Catel/credentials.json` (`0600`, never synced) and are never displayed back. ChatGPT, Cursor, and Nous stay read-only from the apps that own their sessions.
- **Choose what the menu bar shows** -- pick providers per slot from the popover, or right-click the menu bar item for a quick switcher. Providers with no local credentials and no saved key are hidden, while the configured slot choice is preserved. Up to two slots can be hidden.
- **Polls every 60 seconds** and refreshes on hover when the data is stale.
- **Fails soft** -- a dead endpoint keeps the last good numbers and marks them stale instead of blanking out.
- **Quit** lives in the popover footer (there is no Dock icon).

## Requirements

- macOS 13 or later (built and tested on macOS 26)
- Apple Command Line Tools for `swiftc` -- the full Xcode app is **not** required:
  ```bash
  xcode-select --install
  ```
- At least one provider signed in locally (see below) or a key saved in Settings. Providers with neither are hidden until they are configured again.

## Build and install

```bash
git clone https://github.com/marksagangms-debug/catel.git
cd catel
zsh build.sh
open Catel.app
```

`build.sh` compiles `Sources/*.swift` with `swiftc`, assembles `Catel.app`, and regenerates the `.icns` from `Resources/AppIcon-source.png`.

To install it:

```bash
rm -rf /Applications/Catel.app
cp -R Catel.app /Applications/Catel.app
open /Applications/Catel.app
```

Optional: **System Settings → General → Login Items → Open at Login** and add Catel.

The app is built locally and unsigned, which is fine for your own machine. If you ever move a downloaded copy between Macs, clear the quarantine flag first:

```bash
xattr -dr com.apple.quarantine /Applications/Catel.app
```

Headless test binaries (provider availability, credential vault, window selection, visible providers) run with:

```bash
CATEL_RUN_TESTS=1 zsh build.sh
```

## Usage

| Action | Result |
|---|---|
| Hover the menu bar item | Shows the popover after ~120 ms |
| Move away from item and popover | Closes after ~200 ms |
| Click the item | Pins the popover open; click again to unpin |
| Right-click the item | Cursor Models / Other Models, Menu bar slot 1-3 submenus, Settings…, Quit |
| Click the popover gear (footer) | Opens Settings (provider API keys) |
| Click anywhere else | Closes the popover |

**Menu bar slots.** The popover's *Menu bar* row has three slot pickers: ChatGPT, Cursor, Nous, DeepSeek, OpenCode, CmdCode, or None (hidden). Providers with no readable local credentials and no saved key are omitted from this menu and their detail sections are hidden, but the saved slot choice is kept. Click the refresh icon in the footer after reconnecting a provider; it will reappear without restarting Catel. At most two slots can be hidden, so on the last visible slot `None` is greyed out and cannot be clicked. Picking a provider that already occupies another slot swaps the two instead of duplicating it. Slot choice and the Cursor bucket are remembered in `UserDefaults`.

**Values shown:** `G` = the selected ChatGPT window (`5h` or `W`, representing the 7-day window), `C` = the Cursor bucket you selected, `N` = Nous subscription credits used this period, `D` = DeepSeek balance in dollars, `O` = the selected OpenCode Go window, `CC` = the selected CommandCode window. The popover's compact `5h / W / M` title selector controls each provider's status-bar window; the matching usage column is display-only. The choice is remembered in `UserDefaults` and updates the status bar immediately.

## Credentials and privacy

Catel never asks you to sign in to anything and never writes to another app's credential store. It **reads** files your existing tools already maintain (or keys you paste into its own Settings window), and only **calls** the vendor APIs listed below.

| Provider | Credential (read-only) | Request |
|---|---|---|
| ChatGPT | `~/.codex/auth.json` (access token, account id) | `GET https://chatgpt.com/backend-api/wham/usage` |
| Cursor | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, table `ItemTable`, key `cursorAuth/accessToken` (via `/usr/bin/sqlite3` in read-only mode; Insiders path as fallback) | `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage` |
| Nous / Hermes | `~/.hermes/auth.json` (token, optional `portal_base_url`) | `GET {portal}/api/oauth/account` |
| DeepSeek | key saved in Catel Settings, else `DEEPSEEK_API_KEY` from `~/.hermes/.env` | `GET https://api.deepseek.com/user/balance` |
| OpenCode Go | key saved in Catel Settings, else `~/.local/share/opencode/auth.json` (`opencode-go` API key written by `opencode providers` / `/connect`) | `GET https://opencode.ai/zen/go/v1/usage` |
| CommandCode | key saved in Catel Settings, else `COMMANDCODE_API_KEY` from `~/.hermes/.env` | `GET https://api.commandcode.ai/alpha/billing/credits` + `GET .../alpha/billing/subscriptions` (the same endpoints the `cmd` CLI's `/usage` meter reads) |

Keys you paste into Settings are stored in `~/Library/Application Support/Catel/credentials.json`, written `0600` inside a `0700` directory, and never leave the Mac: no sync, no upload, no logging, and no echoing the value back into the UI. Catel keeps its own file only, so `~/.codex/auth.json`, `~/.hermes/auth.json`, `~/.hermes/.env`, the OpenCode `auth.json`, and the Cursor database stay untouched.

What Catel does **not** do:

- No telemetry, analytics, crash reporting, or "phone home".
- No tokens, cookies, or raw auth JSON written to logs or disk.
- No writes to `~/.codex/auth.json`, `~/.hermes/auth.json`, `~/.hermes/.env`, the OpenCode `auth.json`, or the Cursor database. **Refresh-token writes would log you out**, so Catel only reads.
- No local history of your usage. The only persisted state is the menu bar slot selection and the metric preferences (`UserDefaults`), plus the API keys you deliberately save in Settings.

### Two caveats worth knowing

1. **Nous Portal refresh tokens are single-use.** Calling `POST /api/oauth/token` from Catel would rotate the token and could kill your Hermes session, so Catel deliberately does not refresh. If the token expires, open Hermes Agent once and it will refresh `~/.hermes/auth.json` for you. This is also why Nous has no key field in Settings.
2. **Every endpoint here is unofficial / undocumented** and can change without notice. These are the same private APIs the vendor clients use. If a provider starts showing "Usage data unavailable", the response shape most likely moved. The OpenCode Go usage endpoint is the one the OpenCode console/TUI reads; it is not documented as a public API. The CommandCode billing endpoints are the ones its CLI's `/usage` meter reads; the public Provider API (`/provider/v1/*`) does not expose usage.

## Project layout

```text
Sources/
  App.swift            Status item, title rendering, hover/click popover lifecycle, Settings entry
  UsageMonitor.swift   Shared models, formatting, 60s polling, slot preferences
  ProviderAvailability.swift Credential presence (local files + saved keys)
  ProviderCredentials.swift  Key-based providers + local-only key vault
  ChatGPTUsage.swift   ChatGPT wham/usage client
  CursorUsage.swift    Cursor token read + dashboard usage client
  HermesUsage.swift    Nous Portal account/credits client
  DeepSeekUsage.swift  DeepSeek balance client
  OpenCodeUsage.swift  OpenCode Go limit client
  CommandCodeUsage.swift CommandCode caps/plan-credit client
  PopoverView.swift    SwiftUI popover + AppKit hosting
  SettingsView.swift   Settings panel + window controller
  SlotMenu.swift       Slot menu builder for both entry points
Tests/                 Headless test binaries (no XCTest)
Info.plist             LSUIElement accessory app, icon, bundle id
build.sh               Compiles the .app bundle and the icon
Resources/             AppIcon-source.png + generated AppIcon.icns
docs/                  overview, design, architecture
```

Deeper docs: [docs/overview.md](docs/overview.md) · [docs/design.md](docs/design.md) · [docs/architecture.md](docs/architecture.md)

## Troubleshooting

| Symptom | Fix |
|---|---|
| `G --` and a sign-in hint | Open ChatGPT or the Codex CLI and sign in so `~/.codex/auth.json` exists. |
| `C --` | Open Cursor and sign in. Catel also needs `/usr/bin/sqlite3`, which ships with macOS. |
| `N --`, "Open Hermes Agent and sign in" | Make sure you are signed in to Nous Portal in Hermes, then open Hermes once so it refreshes `~/.hermes/auth.json`. Nous cannot be key-entered in Settings on purpose. |
| `D --`, `O --`, or `CC --` | Save that provider's key in **Settings…** (popover gear), or restore the file Catel reads (`DEEPSEEK_API_KEY` / `COMMANDCODE_API_KEY` in `~/.hermes/.env`, or connect OpenCode Go in OpenCode). |
| A saved key stopped working | Open Settings and press `Test` on that row: it shows the client's real error. `Sign in again to refresh` means the API rejected the key; save a new one or press `Clear` to fall back to the local file. |
| Settings window did not appear | Opening it closes the popover first by design. Use **Settings…** in the right-click menu if the gear click was swallowed. |
| DeepSeek is missing after removing its key | Reconnect it by saving a key in Settings or restoring `DEEPSEEK_API_KEY` in `~/.hermes/.env`, then click the popover's refresh icon. The provider and its saved slot return automatically. |
| Generic icon in Finder after rebuilding | Finder's icon cache; relaunch Finder or log out and back in once. |
| Stale note under a provider | Last refresh failed; the previous numbers are kept on purpose. Hover to retry or wait for the next 60s poll. |

## Contributing

Issues and pull requests are welcome. A few things to keep in mind:

- The build is plain `swiftc` -- no Xcode project, no package manager, no dependencies. Keep it that way unless there is a strong reason.
- Credential reads stay read-only. Never write to `~/.codex/auth.json`, `~/.hermes/auth.json`, `~/.hermes/.env`, the OpenCode `auth.json`, or the Cursor database. The only file Catel writes is its own key store.
- Never log tokens, cookies, or raw auth JSON, and never print a key saved in Settings.
- If you change endpoints, auth sources, key storage, polling, menu bar behavior, or packaging, update the matching file in `docs/` in the same change.

## License

[MIT](LICENSE) © 2026 Mark Sagang

Catel is an independent, unofficial tool. It is not affiliated with, endorsed by, or supported by OpenAI, Anysphere (Cursor), Nous Research, or DeepSeek.
