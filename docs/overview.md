# Overview

## Purpose

Catel is a lightweight macOS **menu-bar only** app (no Dock icon). It surfaces usage and balance for:

- **ChatGPT** (Plus/Pro quota via the Codex/ChatGPT local session)
- **Cursor** (Pro plan quotas via Cursor’s local session + dashboard API)
- **Nous / Hermes Agent** (Nous Portal subscription credits via local Hermes OAuth)
- **DeepSeek** (API account balance via `DEEPSEEK_API_KEY`)
- **OpenCode Go** (5-hour / weekly / monthly limit windows via the local OpenCode credentials)
- **CommandCode** (5-hour / weekly rolling caps + monthly plan credits via the `COMMANDCODE_API_KEY` Hermes stores)

It does **not** track OpenAI developer API spend (`platform.openai.com`). Those are different products.

## Current features

- Menu bar title built from **three configurable slots**, default `G` (ChatGPT), `C` (Cursor), and `N` (Nous):
  - `G` = ChatGPT **5-hour** window `% used`
  - `C` = selected Cursor bucket `% used` (default **Other Models**; switch in the popover or right-click menu)
  - `N` = Nous Portal subscription credits `% used` this billing period
  - `D` = DeepSeek account balance (`$`)
  - `O` = OpenCode Go 5-hour limit `% used`
  - `CC` = CommandCode 5-hour cap `% used`
  - Slots can be set to **None** (hidden); at most two, so the item never disappears
- Hover (or click to pin) a compact popover with:
  - a **Menu bar** row: one picker per slot (ChatGPT / Cursor / Nous / DeepSeek / OpenCode / CmdCode / None)
  - ChatGPT: 5-hour + 7-day meters and reset times
  - Cursor: Cursor Models + Other Models meters, billing-cycle reset; radio dot on each column picks which bucket drives `C`
  - Nous: subscription meter, remaining `$` of monthly credits, cycle reset; top-up line when purchased credits exist
  - DeepSeek: balance row
  - OpenCode Go: 5-hour + weekly + monthly meters and reset times
  - CommandCode: 5-hour + weekly + monthly plan-credit meters, plan tag, billing reset
- Polls every **60 seconds**; refreshes on hover if stale
- Quit from the popover footer; right-click the item for Cursor bucket + slot 1/2/3 shortcuts
- App icon: cat avatar (`Resources/AppIcon.icns`), copied into the `.app` / Applications install
- If Finder still shows a generic icon after reinstall, relaunch Finder or log out/in once (icon cache)

## Requirements

- macOS 13+
- Apple Command Line Tools (`swiftc`) — Xcode app not required
- Signed in to **Codex/ChatGPT** locally (`~/.codex/auth.json`)
- Signed in to **Cursor** on this Mac (token in Cursor `state.vscdb`)
- Signed in to **Hermes Agent / Nous Portal** locally (`~/.hermes/auth.json`). Hermes must refresh that file (open Hermes occasionally); Catel does **not** rotate the Portal refresh token.
- Optional: `DEEPSEEK_API_KEY` in `~/.hermes/.env` for the DeepSeek balance
- Optional: OpenCode Go connected in OpenCode (`opencode providers` / `/connect`), which writes `~/.local/share/opencode/auth.json`
- Optional: `COMMANDCODE_API_KEY` in `~/.hermes/.env` for the CommandCode provider (generate at commandcode.ai → Studio → API keys)

## Build / install

```bash
git clone https://github.com/marksagangms-debug/catel.git
cd catel
zsh build.sh
```

Produces `Catel.app` in the project root.

Copy to Applications:

```bash
rm -rf "/Applications/Catel.app"
cp -R "Catel.app" "/Applications/Catel.app"
open "/Applications/Catel.app"
```

Optional: **System Settings → General → Login Items** → add the app to open at login.

## Project layout

```text
Sources/
  App.swift            # Status item, hover/click popover, title rendering
  UsageMonitor.swift   # Models + 60s polling coordinator + slot preferences
  ChatGPTUsage.swift   # ChatGPT wham/usage client
  CursorUsage.swift    # Cursor dashboard usage client
  HermesUsage.swift    # Nous Portal account/credits client
  DeepSeekUsage.swift  # DeepSeek balance client
  OpenCodeUsage.swift  # OpenCode Go limit-window client
  CommandCodeUsage.swift # CommandCode caps/plan-credit client
  PopoverView.swift    # SwiftUI popover UI + AppKit hosting
  SlotMenu.swift       # Slot menu builder for both entry points
Info.plist             # LSUIElement accessory app + icon
build.sh               # Compiles .app bundle + icon
Resources/             # AppIcon source + .icns
docs/                  # This documentation
.cursor/rules/         # Agent rules (keep docs updated)
```
