# Overview

## Purpose

Catel is a lightweight macOS **menu-bar only** app (no Dock icon). It surfaces usage and balance for:

- **ChatGPT** (Plus/Pro quota via the Codex/ChatGPT local session)
- **Cursor** (Pro plan quotas via Cursor’s local session + dashboard API)
- **Nous / Hermes Agent** (Nous Portal subscription credits via local Hermes OAuth)
- **DeepSeek** (API account balance via `DEEPSEEK_API_KEY`)

It does **not** track OpenAI developer API spend (`platform.openai.com`). Those are different products.

## Current features

- Menu bar title built from **two configurable slots**, default `G` (ChatGPT) and `C` (Cursor):
  - `G` = ChatGPT **5-hour** window `% used`
  - `C` = selected Cursor bucket `% used` (default **Other Models**; switch in the popover or right-click menu)
  - `N` = Nous Portal subscription credits `% used` this billing period
  - `D` = DeepSeek account balance (`$`)
  - A slot can be set to **None** (hidden); at most one, so the item never disappears
- Hover (or click to pin) a compact popover with:
  - a **Menu bar** row: one picker per slot (ChatGPT / Cursor / Nous / DeepSeek / None)
  - ChatGPT: 5-hour + 7-day meters and reset times
  - Cursor: Cursor Models + Other Models meters, billing-cycle reset; radio dot on each column picks which bucket drives `C`
  - Nous: subscription meter, remaining `$` of monthly credits, cycle reset; top-up line when purchased credits exist
  - DeepSeek: balance row
- Polls every **60 seconds**; refreshes on hover if stale
- Quit from the popover footer; right-click the item for Cursor bucket + slot 1 shortcuts
- App icon: cat avatar (`Resources/AppIcon.icns`), copied into the `.app` / Applications install
- If Finder still shows a generic icon after reinstall, relaunch Finder or log out/in once (icon cache)

## Requirements

- macOS 13+
- Apple Command Line Tools (`swiftc`) — Xcode app not required
- Signed in to **Codex/ChatGPT** locally (`~/.codex/auth.json`)
- Signed in to **Cursor** on this Mac (token in Cursor `state.vscdb`)
- Signed in to **Hermes Agent / Nous Portal** locally (`~/.hermes/auth.json`). Hermes must refresh that file (open Hermes occasionally); Catel does **not** rotate the Portal refresh token.
- Optional: `DEEPSEEK_API_KEY` in `~/.hermes/.env` for the DeepSeek balance

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
  PopoverView.swift    # SwiftUI popover UI + AppKit hosting
Info.plist             # LSUIElement accessory app + icon
build.sh               # Compiles .app bundle + icon
Resources/             # AppIcon source + .icns
docs/                  # This documentation
.cursor/rules/         # Agent rules (keep docs updated)
```
