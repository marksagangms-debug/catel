# Design (UI/UX)

## Product feel

Minimal menu-bar utility. Glanceable numbers in the bar; detail only on hover/click. One small Settings window holds provider API keys (added in 1.3); nothing else is configurable.

## Status item

Lives in the macOS menu bar via a custom `HoverStatusButton` assigned to the
`NSStatusItem`, sized to the system menu-bar thickness for consistent alignment.

### Content

The title is built from the three configured slots (default ChatGPT + Cursor + Nous):

```text
G{4px}20% | C{4px}13% | N{4px}7%
```

- Plain text only — **no** left border, **no** colored backgrounds/gradients
- Letter → value spacing: **4px** (`NSKernAttributeName` / kern = 4)
- Between slots: thin `|` divider at ~40% text opacity, with spaces around it (`" | "`)
- Slot labels: `G` ChatGPT, `C` Cursor, `N` Nous, `D` DeepSeek, `O` OpenCode, `CC` CommandCode; a `None` slot renders nothing at all (no label, no divider)
- The letter→value gap is the kern on the label's **last character only**, so multi-letter labels stay grouped (`CC 61%`, never `C C61%`)
- Monospaced system font, 11pt semibold
- Text is rendered as a **template image** so macOS tints it for light/dark menu bar backgrounds (same mechanism as system status icons)

### Interaction

| Action | Behavior |
|---|---|
| Hover | Show popover after ~120ms (if not pinned) |
| Leave status item + popover | Close after ~200ms (if not pinned) |
| Click | Pin open / unpin close |
| Right-click | Cursor Models / Other Models, Menu bar slot 1-3 submenus, Settings… (⌘,), Quit |
| Click outside | Close |

Hover tracking is handled by the custom `HoverStatusButton` view assigned to
the status item, using an `NSTrackingArea`; movement inside the item also
recovers from frame-layout events that can omit the initial enter callback.

## Popover

- Size **360×575**, no system popover animation (`animates = false`). The wider canvas gives the three slot fields and three usage columns enough room while leaving the title selectors compact.
- SwiftUI content in `NSPopover` inside a `PopoverTrackingView` (which reports pointer enter/exit back to the status item controller)
- Sections stack top to bottom: **Menu bar** picker, configured provider sections in fixed order (ChatGPT, Cursor, Nous, DeepSeek, OpenCode Go, CommandCode), footer. Providers without readable local credentials are omitted; their saved slot choice is preserved and they return after the footer refresh action.
- Design tokens live in `CatelToken` (`PopoverView.swift`) — the exact computed styles from the Paper file “Catel”. Keep them in sync when the design changes.

### Menu bar section

- Header row: `MENU BAR` + `3 slots`
- One picker per slot: current provider name + chevron, 30pt field with rounded 7pt border
- Width math: the three fields share the 336pt content area inside the 360pt popover, with 8pt gaps. Labels carry `minimumScaleFactor(0.85)`, so the longest provider name scales instead of truncating.
- Height math: measured intrinsic content height is **515pt** for the six provider sections (a `NSHostingView.fittingSize` measurement with live data; the five-section build measured 468pt against its 528pt frame). 575pt keeps the same ~60pt headroom for stale/loading notes. A key-only machine measures smaller (483pt with two provider sections), which is why the frame stays fixed rather than shrinking.
- Menu offers only providers with readable local credentials, plus `None`; the active one is checked. A provider whose credentials disappear stays in the saved slots but is omitted from the menu until the footer refresh action finds it again.
- `None` stays visible but is **disabled** when the other two slots are already hidden: AppKit greys it out and refuses the click. The menu is created with `autoenablesItems = false`, because with AppKit's default automatic enabling an item whose target responds to the action is re-enabled before display, which made that row look and behave as if it were selectable. `SlotMenuFactory` builds this menu for both the popover picker and the status-item right-click submenus so the rule cannot drift.

### ChatGPT section

- Title: `ChatGPT` + plan tag (e.g. `PLUS`, fallback `PLAN`)
- Compact `5h / W` selector at the far right. `W` represents the 7-day window; the selected value drives menu-bar `G` and persists in `UserDefaults`.
- Columns: **5-hour** | **7-day**, display-only with no radio buttons
- Each column: label, `%`, thin progress bar, reset countdown (`10m`, `5d 17h`)
- Bar / `%` color: blue (`#007AFF`)

### Cursor section

- Title: `Cursor` + plan tag (e.g. `PRO`, fallback `PRO`)
- Columns: **Cursor Models** | **Other Models** (same two-column layout as ChatGPT)
- Each column row: label + **radio** grouped on the left, `%` on the far right; tap the column to choose which bucket drives menu-bar `C` (persisted in `UserDefaults`)
- Radio: 9px ring; unselected = gray ring (`#6E6E73` @ 40%); selected = ring + 4px dot in the Cursor accent
- Bar / `%` color: indigo (`#5856D6`) for both buckets
- Cycle reset line under the columns: compact countdown only (`30d 8h`)

### Nous section

- Title: `Nous` + plan tag (e.g. `PLUS`, fallback `PORTAL`)
- Meter: **Subscription** `% used` of monthly credits (`(monthly − remaining) / monthly`)
- Caption: `$20.44 of $22.00 left  ·  29d 6h`, plus `top-up $X.XX` when purchased credits exist
- Bar / `%` color: orange (`#FF9500`)

### DeepSeek section

- Title: `DeepSeek` + tag `API`
- Single row: `Balance` on the left, `$` amount on the right (DeepSeek has no percent concept)
- Value color: green (`#248A3D`)

### OpenCode Go section

- Title: `OpenCode Go` + tag `GO`
- Columns: **5-hour** | **Weekly** | **Monthly**, same label/`%`/bar/reset shape as the ChatGPT windows, three columns instead of two
- A compact `5h / W / M` segmented selector beside the title is the only selector. The usage columns have no radio buttons. The selected window drives menu-bar `O` and is remembered in `UserDefaults`.
- The three windows come from OpenCode's Go limits: 5-hour, weekly, and monthly dollar caps, reported as a `%` used per window
- Bar / `%` color: purple (`#AF52DE`)
- Column width is about 102pt at the 360pt popover width; compact reset captions fit without the removed `resets in` prefix.

### CommandCode section

- Title: `CommandCode` + plan tag (`GOAT`, `PRO`, `MAX`, ...; fallback `API`)
- Columns: **5-hour** | **Weekly** | **Monthly**, same shape as the OpenCode Go windows
- A compact `5h / W / M` segmented selector beside the title is the only selector. The usage columns have no radio buttons. The selected window drives menu-bar `CC` and is remembered in `UserDefaults`.
- 5-hour and weekly are rolling caps (`used / cap` from `windowLimits`); monthly is the plan-credit pool with the billing-period-end reset
- Bar / `%` color: rust (`#BF5A2A`)
- With no active plan (pay-as-you-go) the Monthly column shows `--` / empty bar; the caps still render

### Footer

- Hairline divider, then left: relative last-updated text, center: refresh icon for rechecking local credentials, then the Settings gear, right: **Quit**. The gear shares the existing row, so the popover height is unchanged.

### States

- Loading: small progress spinner + `Updating...`
- Missing auth: short “sign in” guidance from the client error, now naming Settings as the alternative (`…or save a key in Catel Settings`)
- Stale: keep last good numbers and add `Stale · <message>` under the section
- Window/cycle captions are compact countdowns only (`5h 12m`, `3d 4h`, `29d 6h`); the word `resets in` is omitted. Missing reset data is simply `unavailable`.

## Settings panel

`CatelSettingsView` in a hand-built `NSWindow` (`SettingsWindowController`, "Catel Settings"). Entry points: **Settings…** in the status item's right-click menu and the popover footer gear. Opening it closes the popover first.

- Width **460pt**; content height is measured (`NSHostingView.fittingSize`) and the window content size is set from it, so nothing clips. Current measurement: **616pt** content (648pt window including the title bar).
- Built from the same `CatelToken` values as the popover: 18pt padding, 16pt between sections, 11/9/10pt type, hairline dividers between key rows.
- Header: `Provider API keys` + one explanatory sentence (paste a key to skip the local file; keys stay on this Mac).
- One row per key-based provider (DeepSeek, CommandCode, OpenCode Go):
  - provider name + status badge on the right: `Saved in Catel` (green), `Using ~/.hermes/.env` (secondary), or `Not set`
  - a `SecureField` (placeholder `Paste <Provider> API key`, `Replace saved key` when one exists), then `Save`, `Test`, and `Clear` (Clear only when a key is saved)
  - caption line: `Falls back to <source> · <key name>` on the left, live `Test` result on the right (`Checking…` / `Key works · <detail>` / the client's error message)
  - `Save` is disabled while the field is empty; `Test` needs a saved key or a detected fallback file, and works against whichever source is in effect
- Read-only section (`READ-ONLY FROM OTHER APPS`): ChatGPT, Cursor, Nous with their source file and `Detected` / `Not found`, plus a note that Nous stays on the local Hermes session because Portal refresh tokens are single-use.
- Footer: the storage path (`~/Library/Application Support/Catel/credentials.json`, owner-only `0600`), a line stating nothing is synced or uploaded, and a **Done** button.
- Saved keys are never rendered back into the field: after saving, the field clears and the badge changes instead.

## Design decisions (current)

- The menu bar keeps exactly three configured slots, but providers without local credentials are hidden from the rendered title and popover without deleting their saved assignment. If reconnecting a provider makes it available again, it reappears in the same slot. A key saved in Settings counts as available.
- Key entry is deliberately limited to providers that accept a plain API key. ChatGPT/Cursor/Nous stay file-only, and the Read-only list states why, so nobody expects a token paste to work where it cannot.
- Keys are write-once from the user's side: the panel shows status, never the value.
- Status bar `C` defaults to **Other Models** (tighter / more actionable), but can switch to **Cursor Models** via the column radio or the right-click menu
- Popover always shows **both** Cursor buckets; the radio dot marks which one drives `C`
- Intentionally **not** showing Cursor `$used / $limit` in the popover (that mixed metrics and confused the UI)
- Nous **does** show remaining dollars under the percent meter because the Portal is credit-denominated; `%` still matches the menu-bar `N`
- DeepSeek is a balance, not a quota, so it uses a label/value row instead of a meter
- ChatGPT, OpenCode Go, and CommandCode use compact title selectors with display-only window columns. Cursor keeps its two-column radio selector because its buckets represent different model categories rather than time windows.
- Accessory app (`LSUIElement`): no Dock icon; Quit must live in the popover, the right-click menu, and the Settings window is the only extra window the app can show.

## When changing UI

Update this file if you change spacing, labels, which `%` the menu bar shows, popover layout, Settings layout, slot behavior, or interaction timing.
