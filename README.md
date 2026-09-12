# Catel

<img src="Resources/AppIcon-source.png" alt="Catel app icon" width="128" align="right" />

A tiny macOS **menu-bar app** that shows your AI subscription usage at a glance: ChatGPT, Cursor, Nous Portal (Hermes), and DeepSeek.

No Dock icon. No settings window. No account, no server, no telemetry. Catel reads the credentials your other tools already stored on your Mac, calls the vendor APIs directly, and prints the numbers in your menu bar.

```text
G 20% | C 13% | N 7%
```

`G` ChatGPT 5-hour window · `C` Cursor selected bucket · `N` Nous subscription credits

## Features

- **Menu bar at a glance** -- three configurable slots, plain monospaced text, tinted by macOS for light and dark menu bars.
- **Hover popover** -- hover the item (or click to pin it) for the detail:
  - **ChatGPT**: 5-hour and 7-day meters with reset countdowns and plan tag.
  - **Cursor**: Cursor Models and Other Models meters, billing-cycle reset, radio dot to pick which bucket drives the menu bar.
  - **Nous / Hermes**: subscription meter, credits left of the monthly allowance, top-up line when purchased credits exist, cycle reset.
  - **DeepSeek**: account balance (API account, denominated in USD).
- **Choose what the menu bar shows** -- pick providers per slot from the popover, or right-click the menu bar item for a quick switcher. Up to two slots can be hidden.
- **Polls every 60 seconds** and refreshes on hover when the data is stale.
- **Fails soft** -- a dead endpoint keeps the last good numbers and marks them stale instead of blanking out.
- **Quit** lives in the popover footer (there is no Dock icon).

## Requirements

- macOS 13 or later (built and tested on macOS 26)
- Apple Command Line Tools for `swiftc` -- the full Xcode app is **not** required:
  ```bash
  xcode-select --install
  ```
- At least one provider signed in locally (see below). Providers you are not signed in to simply show a sign-in hint.

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

## Usage

| Action | Result |
|---|---|
| Hover the menu bar item | Shows the popover after ~120 ms |
| Move away from item and popover | Closes after ~200 ms |
| Click the item | Pins the popover open; click again to unpin |
| Right-click the item | Cursor Models / Other Models, Menu bar slot 1-3 submenus, Quit |
| Click anywhere else | Closes the popover |

**Menu bar slots.** The popover's *Menu bar* row has three slot pickers: ChatGPT, Cursor, Nous, DeepSeek, or None (hidden). At most two slots can be hidden, so on the last visible slot `None` is greyed out and cannot be clicked. Picking a provider that already occupies another slot swaps the two instead of duplicating it. Slot choice and the Cursor bucket are remembered in `UserDefaults`.

**Values shown:** `G` = ChatGPT 5-hour window % used, `C` = the Cursor bucket you selected (Cursor Models or Other Models), `N` = Nous subscription credits used this period, `D` = DeepSeek balance in dollars.

## Credentials and privacy

Catel never asks for a login and never writes to any credential store. It only **reads** files your existing tools already maintain, and only **calls** the vendor APIs listed below.

| Provider | Read from (read-only) | Request |
|---|---|---|
| ChatGPT | `~/.codex/auth.json` (access token, account id) | `GET https://chatgpt.com/backend-api/wham/usage` |
| Cursor | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, table `ItemTable`, key `cursorAuth/accessToken` (via `/usr/bin/sqlite3` in read-only mode; Insiders path as fallback) | `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage` |
| Nous / Hermes | `~/.hermes/auth.json` (token, optional `portal_base_url`) | `GET {portal}/api/oauth/account` |
| DeepSeek | `DEEPSEEK_API_KEY` from `~/.hermes/.env` | `GET https://api.deepseek.com/user/balance` |

What Catel does **not** do:

- No telemetry, analytics, crash reporting, or "phone home".
- No tokens, cookies, or raw auth JSON written to logs or disk.
- No writes to `~/.codex/auth.json`, `~/.hermes/auth.json`, or the Cursor database. **Refresh-token writes would log you out**, so Catel only reads.
- No local history of your usage. The only persisted state is the menu bar slot selection and the Cursor bucket preference (`UserDefaults`).

### Two caveats worth knowing

1. **Nous Portal refresh tokens are single-use.** Calling `POST /api/oauth/token` from Catel would rotate the token and could kill your Hermes session, so Catel deliberately does not refresh. If the token expires, open Hermes Agent once and it will refresh `~/.hermes/auth.json` for you.
2. **Every endpoint here is unofficial / undocumented** and can change without notice. These are the same private APIs the vendor clients use. If a provider starts showing "Usage data unavailable", the response shape most likely moved.

## Project layout

```text
Sources/
  App.swift            Status item, title rendering, hover/click popover lifecycle
  UsageMonitor.swift   Shared models, formatting, 60s polling, slot preferences
  ChatGPTUsage.swift   ChatGPT wham/usage client
  CursorUsage.swift    Cursor token read + dashboard usage client
  HermesUsage.swift    Nous Portal account/credits client
  DeepSeekUsage.swift  DeepSeek balance client
  PopoverView.swift    SwiftUI popover + AppKit hosting
  SlotMenu.swift       Slot menu builder for both entry points
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
| `N --`, "Open Hermes Agent and sign in" | Make sure you are signed in to Nous Portal in Hermes, then open Hermes once so it refreshes `~/.hermes/auth.json`. |
| DeepSeek shows nothing | Add `DEEPSEEK_API_KEY=...` to `~/.hermes/.env`. |
| Generic icon in Finder after rebuilding | Finder's icon cache; relaunch Finder or log out and back in once. |
| Stale note under a provider | Last refresh failed; the previous numbers are kept on purpose. Hover to retry or wait for the next 60s poll. |

## Contributing

Issues and pull requests are welcome. A few things to keep in mind:

- The build is plain `swiftc` -- no Xcode project, no package manager, no dependencies. Keep it that way unless there is a strong reason.
- Keep credential reads read-only. Never write to `~/.codex/auth.json`, `~/.hermes/auth.json`, or the Cursor database.
- Never log tokens, cookies, or raw auth JSON.
- If you change endpoints, auth sources, polling, menu bar behavior, or packaging, update the matching file in `docs/` in the same change.

## License

[MIT](LICENSE) © 2026 Mark Sagang

Catel is an independent, unofficial tool. It is not affiliated with, endorsed by, or supported by OpenAI, Anysphere (Cursor), Nous Research, or DeepSeek.
