# Design (UI/UX)

## Product feel

Minimal menu-bar utility. Glanceable numbers in the bar; detail only on hover/click. No settings window in v1.

## Status item

Lives in the macOS menu bar via a custom `HoverStatusButton` assigned to the
`NSStatusItem`, sized to the system menu-bar thickness for consistent alignment.

### Content

The title is built from the two configured slots (default ChatGPT + Cursor):

```text
G{4px}20% | C{4px}13%
```

- Plain text only — **no** left border, **no** colored backgrounds/gradients
- Letter → value spacing: **4px** (`NSKernAttributeName` / kern = 4)
- Between slots: thin `|` divider at ~40% text opacity, with spaces around it (`" | "`)
- Slot labels: `G` ChatGPT, `C` Cursor, `N` Nous, `D` DeepSeek; a `None` slot renders nothing at all (no label, no divider)
- Monospaced system font, 11pt semibold
- Text is rendered as a **template image** so macOS tints it for light/dark menu bar backgrounds (same mechanism as system status icons)

### Interaction

| Action | Behavior |
|---|---|
| Hover | Show popover after ~120ms (if not pinned) |
| Leave status item + popover | Close after ~200ms (if not pinned) |
| Click | Pin open / unpin close |
| Right-click | Cursor Models / Other Models, Menu bar slot 1, Quit |
| Click outside | Close |

Hover tracking is handled by the custom `HoverStatusButton` view assigned to
the status item, using an `NSTrackingArea`; movement inside the item also
recovers from frame-layout events that can omit the initial enter callback.

## Popover

- Size **300×452**, no system popover animation (`animates = false`)
- SwiftUI content hosted in `NSPopover` inside a `PopoverTrackingView` (which reports pointer enter/exit back to the status item controller)
- Sections stack top to bottom: **Menu bar** picker, ChatGPT, Cursor, Nous, DeepSeek, footer
- Design tokens live in `CatelToken` (`PopoverView.swift`) — the exact computed styles from the Paper file “Catel”. Keep them in sync when the design changes.

### Menu bar section

- Header row: `MENU BAR` + `2 slots`
- One picker per slot: current provider name + chevron, 30pt field with rounded 7pt border
- Menu offers ChatGPT / Cursor / Nous / DeepSeek / None; the active one is checked
- `None` is disabled when the other slot is already hidden (the menu bar must never be empty)

### ChatGPT section

- Title: `ChatGPT` + plan tag (e.g. `PLUS`, fallback `PLAN`)
- Columns: **5-hour** | **7-day**
- Each column: label, `%`, thin progress bar, reset countdown (`10m`, `5d 17h`)
- Bar / `%` color: blue (`#007AFF`)

### Cursor section

- Title: `Cursor` + plan tag (e.g. `PRO`, fallback `PRO`)
- Columns: **Cursor Models** | **Other Models** (same two-column layout as ChatGPT)
- Each column row: label + **radio** grouped on the left, `%` on the far right; tap the column to choose which bucket drives menu-bar `C` (persisted in `UserDefaults`)
- Radio: 9px ring; unselected = gray ring (`#6E6E73` @ 40%); selected = ring + 4px dot in the Cursor accent
- Bar / `%` color: indigo (`#5856D6`) for both buckets
- Cycle reset line under the columns: `Cycle resets in 30d 8h`

### Nous section

- Title: `Nous` + plan tag (e.g. `PLUS`, fallback `PORTAL`)
- Meter: **Subscription** `% used` of monthly credits (`(monthly − remaining) / monthly`)
- Caption: `$20.44 of $22.00 left  ·  resets in 29d 6h`, plus `top-up $X.XX` when purchased credits exist
- Bar / `%` color: orange (`#FF9500`)

### DeepSeek section

- Title: `DeepSeek` + tag `API`
- Single row: `Balance` on the left, `$` amount on the right (DeepSeek has no percent concept)
- Value color: green (`#248A3D`)

### Footer

- Hairline divider, then left: relative last-updated text (`Updated 1 second ago`) and right: **Quit**

### States

- Loading: small progress spinner + `Updating...`
- Missing auth: short “sign in” guidance from the client error
- Stale: keep last good numbers and add `Stale · <message>` under the section

## Design decisions (current)

- The menu bar shows **exactly two slots** so the item stays narrow; slot choice is user-configured rather than fixed
- Status bar `C` defaults to **Other Models** (tighter / more actionable), but can switch to **Cursor Models** via the column radio or the right-click menu
- Popover always shows **both** Cursor buckets; the radio dot marks which one drives `C`
- Intentionally **not** showing Cursor `$used / $limit` in the popover (that mixed metrics and confused the UI)
- Nous **does** show remaining dollars under the percent meter because the Portal is credit-denominated; `%` still matches the menu-bar `N`
- DeepSeek is a balance, not a quota, so it uses a label/value row instead of a meter
- Accessory app (`LSUIElement`): no Dock icon; Quit must live in the popover and the right-click menu

## When changing UI

Update this file if you change spacing, labels, which `%` the menu bar shows, popover layout, slot behavior, or interaction timing.
