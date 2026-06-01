# GitHub Wiki — Design Spec

**Date:** 2026-06-01
**Status:** Approved

---

## Goal

Create a GitHub Wiki for the YourSSH repository covering both end-user feature documentation and developer/contributor guides. Wiki content is version-controlled inside the repo (`docs/wiki/`) and automatically synced to GitHub Wiki on every push to `master`.

---

## Audience

- **End users** — people who download and use the app; need feature explanations, screenshots, and quick-start guides.
- **Contributors / developers** — people building on or contributing to the codebase; need architecture diagrams, build instructions, and plugin authoring references.

---

## Content Structure

Wiki content lives in `docs/wiki/` in the main repo. Files are organized into two subdirectories but flattened when synced to GitHub Wiki (using a `User-Guide:-` / `Developer-Guide:-` prefix to avoid name collisions).

```
docs/wiki/
├── Home.md                          # Landing page + navigation index
│
├── user-guide/
│   ├── 01-Getting-Started.md        # Install, first connection, platform notes
│   ├── 02-SSH-Connections.md        # Host mgmt, auth types (password/key/cert/agent), tags, groups
│   ├── 03-Terminal.md               # Split view, broadcast, search-in-scrollback, hotkeys, command palette
│   ├── 04-SFTP.md                   # Dual-panel file manager, transfers, file ops
│   ├── 05-Port-Forwarding.md        # Local/remote/dynamic, active tunnel management
│   ├── 06-Recording.md              # Asciicast recording, playback, library
│   ├── 07-AI-Chat.md                # Multi-provider AI sidebar (Anthropic/OpenAI/Gemini), tool calling
│   ├── 08-Sync.md                   # Supabase cloud sync + P2P LAN sync via QR
│   ├── 09-DevOps-Plugin.md          # Docker/K8s containers, Cloudflare tunnel, MCP server, mail catcher, network stats
│   └── 10-Settings.md               # Hotkeys, keep-alive interval, auto-reconnect, themes
│
└── developer-guide/
    ├── Architecture.md              # Data flow, providers/services map, monorepo layout
    ├── Build.md                     # Build for macOS / Windows / Linux
    ├── Plugin-System.md             # Dart compile-time plugins + JS runtime plugins, HookBus, bridges
    ├── Plugin-Authoring.md          # Sync from docs/plugin-authoring-guide.md
    └── Contributing.md              # PR guidelines, release workflow, wiki update process
```

### GitHub Wiki page naming (after flatten)

| Source file | GitHub Wiki page |
|---|---|
| `Home.md` | `Home` |
| `user-guide/01-Getting-Started.md` | `User-Guide:-Getting-Started` |
| `user-guide/03-Terminal.md` | `User-Guide:-Terminal` |
| `developer-guide/Architecture.md` | `Developer-Guide:-Architecture` |

---

## GitHub Action: Auto-sync

```yaml
# .github/workflows/wiki-sync.yml
name: Sync Wiki

on:
  push:
    branches: [master]
    paths:
      - 'docs/wiki/**'

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Sync docs/wiki/ to GitHub Wiki
        uses: Andrew-Chen-Wang/github-wiki-action@v4
        with:
          path: docs/wiki/
          token: ${{ secrets.GITHUB_TOKEN }}
```

The Action clones `<repo>.wiki.git`, copies the flattened contents of `docs/wiki/`, commits, and pushes. Triggers only when files under `docs/wiki/` change, so unrelated pushes to `master` do not incur wiki sync overhead.

---

## Content Format

### User Guide page template

```markdown
# Feature Name

Brief 1-2 sentence description.

<!-- SCREENSHOT: [describe what to capture, e.g. "Main terminal with split view active, two panes visible"] -->

## Overview

ASCII diagram or flow if the feature has non-obvious structure.

## Quick Start

1. Step one
2. Step two
3. Step three

## Key Features

- **Feature A** — short description
- **Feature B** — short description

## Tips & Shortcuts

| Shortcut | Action |
|---|---|
| Cmd/Ctrl+K | Open command palette |

## Related Pages

- [Link to related page](Wiki-Page-Name)
```

### Developer Guide page template

```markdown
# Component Name

## Purpose

One paragraph — what this does and why it exists.

## Architecture

ASCII diagram showing data flow or class relationships.

## Key Files

| File | Role |
|---|---|
| `app/lib/providers/foo.dart` | ... |

## Extension Points

How to hook into or extend this component.
```

### ASCII diagram style (used consistently)

```
SSH Service ──► dartssh2 ──► Remote Host
     │
     ▼
SessionProvider ──► Terminal Widget
```

---

## Update Workflow

When shipping a new feature:

1. The implementing PR must include updates to the relevant `docs/wiki/` page (or create a new page if it's a new feature area).
2. Merge to `master` triggers the wiki sync Action automatically.
3. The `yourssh-roadmap` skill will be updated to include a reminder: "Update `docs/wiki/` page for any shipped feature."

The `Contributing.md` wiki page will document this process so external contributors know to include wiki updates in their PRs.

---

## Out of Scope

- Localization of wiki content (English only, per project convention).
- Automated screenshot capture (screenshots are added manually as placeholders are filled in).
- A versioned wiki per app release (single `HEAD` wiki tracking `master`).
