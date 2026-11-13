---
name: yourssh-docs-sync
description: Use before every YourSSH release, or when the user asks to update the documentation site for recent changes — e.g. "cập nhật docs", "sync docs", "docs cho bản mới", "trước khi release". Updates the YoursshLabs/docs Mintlify site (https://yoursshlabs.com) so it matches the app on develop.
---

# yourssh-docs-sync

The documentation site lives in a separate repo, **YoursshLabs/docs** (Mintlify, served at https://yoursshlabs.com). Two layers keep it current:

1. **Automatic — release notes.** `release-notes.mdx` is generated from this repo's `CHANGELOG.md` by the docs repo's `.github/workflows/release-notes.yml` (every 6 hours, on demand, or on a `yourssh-release` repository dispatch). Nothing to write by hand: a good CHANGELOG entry *is* the release note.
2. **Manual (this skill) — the guides.** User-visible behaviour, labels, screenshots and new features must be reflected in the user and developer guides **before** the release PR is merged.

## When

Run it on the release branch (or `develop`) before opening the release PR to `master`. A release isn't done until the docs PR is merged.

## Steps

1. **Scope the changes.** `git fetch --tags`; `prev=$(git describe --tags --abbrev=0 origin/master)`; list `git log --oneline $prev..HEAD` and `git diff --stat $prev..HEAD -- app/lib packages`. Keep the user-visible ones: new or changed screens, labels, shortcuts, defaults, behaviour, security behaviour, platforms, install steps. Ignore pure refactors and tests.
2. **Map changes to pages.** Clone or update the docs repo (`gh repo clone YoursshLabs/docs` or `git -C <clone> pull`), branch `docs/sync-<version>`. Use this map (docs path → app area):

   | Docs page | App area |
   |---|---|
   | `index.mdx`, `installation.mdx`, `quickstart.mdx` | platforms, release assets (`release.yml`), Homebrew tap, first launch, updater |
   | `user-guide/hosts.mdx`, `host-keys.mdx`, `bulk-actions.mdx` | `widgets/hosts_dashboard*`, `host_detail_panel/`, `host_chain_editor.dart`, known hosts, `bulk/` |
   | `user-guide/terminal.mdx`, `terminal-sharing.mdx` | `terminal_view.dart`, `session_tab*`, header/status bar, splits, search, input bar, shell integration, `HotkeyService`, share |
   | `user-guide/sftp.mdx`, `port-forwarding.mdx` | SFTP screens, `entry_context_menu.dart`, transfers, code editor; port-forward screen/service |
   | `user-guide/rdp.mdx`, `vnc.mdx` | RDP/VNC workspaces, cert trust, fullscreen |
   | `user-guide/keychain.mdx`, `recording.mdx`, `audit-log.mdx` | keychain screen, `KeyProvider`, credential storage, recordings, audit |
   | `user-guide/snippets.mdx`, `ai-chat.mdx`, `devops.mdx`, `web-tools.mdx`, `cli.mdx` | plugin packages, AI chat, `packages/yourssh_cli`, `services/cli/`, URL scheme |
   | `user-guide/settings.mdx`, `sync.mdx`, `mobile.mdx` | `widgets/settings/`, sync services, `app/lib/mobile/` |
   | `developer-guide/*` | `CLAUDE.md`, build/CI, plugin system, `docs/plugin-authoring-guide.md` |

3. **Edit the pages.** Follow the docs repo's `AGENTS.md` (style, terminology, components). Check every bold UI label against the code. Document what develop does, not what a plan says. New pages must be added to `docs.json` navigation.
4. **Refresh screenshots for changed screens.** Use the `yourssh-screenshots` skill (`tool/docs_journey.sh setup`, then `SECTIONS=<NN,...> tool/docs_journey.sh run` for the affected sections, then `teardown`). Copy the new PNGs into the docs repo's `images/<NN-section>/` with `sips -Z 1440`; keep the same file names so existing references keep working. Never publish a shot with a real host, IP, user name or secret (QR codes must carry `192.0.2.10`).
5. **Validate.** In the docs clone: `npx mint validate` and `npx mint broken-links` (both must pass; CI runs the same).
6. **Open the docs PR** against `main` of YoursshLabs/docs. Its required check **Build and check** must be green; merge it (merging deploys the site).
7. **After the app release is published,** trigger the release notes right away instead of waiting for the 6-hour schedule: `gh workflow run release-notes.yml -R YoursshLabs/docs`, then check https://yoursshlabs.com/release-notes shows the new version.

## Don't

- Don't hand-edit `release-notes.mdx` (it is regenerated; fix `CHANGELOG.md` instead).
- Don't merge the release PR to `master` while the docs PR for that release is still open.
