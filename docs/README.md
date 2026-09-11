# Catel docs

Index for the durable project documentation. Start with the [top-level README](../README.md) for install and usage.

| Doc | Covers |
|---|---|
| [../README.md](../README.md) | Install, usage, credentials/privacy, troubleshooting |
| [overview.md](overview.md) | Purpose, features, build/install, layout |
| [design.md](design.md) | UI/UX: status item + hover popover |
| [architecture.md](architecture.md) | Tech stack, auth, APIs, data flow |

## Quick start

```bash
git clone https://github.com/marksagangms-debug/catel.git
cd catel
zsh build.sh
open Catel.app
```

Installed copy (when present): `/Applications/Catel.app`

## Keeping docs current

`docs/` is the durable context for this repo, so update the matching file in the **same change** as the code:

- Menu bar copy/spacing, popover layout, labels, what a `%` means → `design.md`
- Endpoints, auth files, polling, models, packaging → `architecture.md`
- Feature list, requirements, install steps → `overview.md`

Rules: document what the code actually does, keep bullets short and concrete, call out unofficial endpoints and known caveats, and never put tokens or raw `auth.json` contents in docs.
