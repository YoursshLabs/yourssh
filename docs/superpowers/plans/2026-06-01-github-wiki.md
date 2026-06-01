# GitHub Wiki Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `docs/wiki/` with 15 markdown pages (User Guide + Developer Guide) and a GitHub Action that auto-syncs them to the GitHub Wiki on every push to `master`.

**Architecture:** All wiki content lives as flat `.md` files under `docs/wiki/`. A GitHub Actions workflow (`.github/workflows/wiki-sync.yml`) clones `<repo>.wiki.git` and copies the files on every `master` push that touches `docs/wiki/**`. The `yourssh-roadmap` skill is updated to remind contributors to update the relevant wiki page when shipping a feature.

**Tech Stack:** Markdown, GitHub Actions (`Andrew-Chen-Wang/github-wiki-action@v4`), bash (flatten pre-step).

---

## File Map

| Action | Path |
|---|---|
| Create | `docs/wiki/Home.md` |
| Create | `docs/wiki/User-Guide-Getting-Started.md` |
| Create | `docs/wiki/User-Guide-SSH-Connections.md` |
| Create | `docs/wiki/User-Guide-Terminal.md` |
| Create | `docs/wiki/User-Guide-SFTP.md` |
| Create | `docs/wiki/User-Guide-Port-Forwarding.md` |
| Create | `docs/wiki/User-Guide-Recording.md` |
| Create | `docs/wiki/User-Guide-AI-Chat.md` |
| Create | `docs/wiki/User-Guide-Sync.md` |
| Create | `docs/wiki/User-Guide-DevOps-Plugin.md` |
| Create | `docs/wiki/User-Guide-Settings.md` |
| Create | `docs/wiki/Developer-Guide-Architecture.md` |
| Create | `docs/wiki/Developer-Guide-Build.md` |
| Create | `docs/wiki/Developer-Guide-Plugin-System.md` |
| Create | `docs/wiki/Developer-Guide-Plugin-Authoring.md` |
| Create | `docs/wiki/Developer-Guide-Contributing.md` |
| Create | `.github/workflows/wiki-sync.yml` |
| Modify | `~/.claude/skills/yourssh-roadmap/skill.md` (add wiki update reminder) |

---

## Task 1: Setup — wiki directory + Home.md

**Files:**
- Create: `docs/wiki/Home.md`

- [ ] **Step 1: Create `docs/wiki/` directory and `Home.md`**

```markdown
# YourSSH Wiki

A professional, open-source SSH client for **macOS**, **Windows**, and **Linux** — built for developers and sysadmins who manage multiple servers.

> **Current version:** 0.1.12 · [Download](https://github.com/thangnm93/yourssh/releases) · [Report an issue](https://github.com/thangnm93/yourssh/issues)

---

## User Guide

| Page | Description |
|---|---|
| [Getting Started](User-Guide-Getting-Started) | Install the app and make your first connection |
| [SSH Connections](User-Guide-SSH-Connections) | Manage hosts, auth methods, groups, and tags |
| [Terminal](User-Guide-Terminal) | Split view, broadcast, search, hotkeys, command palette |
| [SFTP](User-Guide-SFTP) | Dual-panel file manager, uploads, downloads |
| [Port Forwarding](User-Guide-Port-Forwarding) | Local, remote, and dynamic SOCKS5 tunnels |
| [Recording](User-Guide-Recording) | Record and replay terminal sessions (Asciinema) |
| [AI Chat](User-Guide-AI-Chat) | AI assistant sidebar with tool calling |
| [Sync](User-Guide-Sync) | Cloud sync (Supabase) and P2P LAN transfer |
| [DevOps Plugin](User-Guide-DevOps-Plugin) | Containers, Cloudflare, MCP, network tools, and more |
| [Settings](User-Guide-Settings) | Hotkeys, keep-alive, reconnect, themes, fonts |

## Developer Guide

| Page | Description |
|---|---|
| [Architecture](Developer-Guide-Architecture) | Data flow, providers, services, monorepo layout |
| [Build](Developer-Guide-Build) | Build the app for macOS, Windows, and Linux |
| [Plugin System](Developer-Guide-Plugin-System) | Dart plugins and JS script plugins |
| [Plugin Authoring](Developer-Guide-Plugin-Authoring) | Write your first JS plugin |
| [Contributing](Developer-Guide-Contributing) | PR guidelines, release workflow, wiki updates |
```

- [ ] **Step 2: Verify file created**

```bash
ls docs/wiki/Home.md
```

Expected: file listed.

- [ ] **Step 3: Commit**

```bash
git add docs/wiki/Home.md
git commit -m "docs(wiki): add Home landing page"
```

---

## Task 2: User Guide — Getting Started + SSH Connections

**Files:**
- Create: `docs/wiki/User-Guide-Getting-Started.md`
- Create: `docs/wiki/User-Guide-SSH-Connections.md`

- [ ] **Step 1: Create `docs/wiki/User-Guide-Getting-Started.md`**

```markdown
# Getting Started

YourSSH is a dark-theme SSH client for macOS, Windows, and Linux. Install it, add a host, and connect in under a minute.

<!-- SCREENSHOT: App home screen showing the host list (empty state or with 1-2 hosts) -->

## Installation

### macOS

1. Download `YourSSH-x.x.x-macOS-arm64.dmg` from the [Releases page](https://github.com/thangnm93/yourssh/releases).
2. Open the `.dmg` and drag **YourSSH** to `/Applications`.
3. **First launch only:** macOS may block the app because it is not yet notarized. Right-click → **Open** → **Open** in the dialog. You only need to do this once.

Alternatively, remove the quarantine flag from Terminal:
```bash
xattr -dr com.apple.quarantine /Applications/YourSSH.app
```

### Windows

1. Download `YourSSH.Setup.x.x.x-Windows-x64.exe` (or `arm64` for Surface/Snapdragon).
2. Run the installer and follow the setup wizard. YourSSH is added to the Start menu.
3. **Windows SmartScreen** may warn on first run. Click **More info → Run anyway**.

### Linux (Debian / Ubuntu)

```bash
# x86_64
sudo dpkg -i yourssh_x.x.x_amd64.deb

# ARM64 (Raspberry Pi 4/5, Apple Silicon Linux)
sudo dpkg -i yourssh_x.x.x_arm64.deb
```

Requires GTK3 (pre-installed on Ubuntu 20.04+, Debian 11+). After install, run `yourssh` or launch from the application menu.

## Your First Connection

1. Click **+** (or press **Cmd/Ctrl+N**) to add a new host.
2. Fill in **Hostname / IP**, **Port** (default 22), and **Username**.
3. Choose an **Auth method**: password, private key, certificate, or SSH agent.
4. Click **Save**, then click the host card to connect.

<!-- SCREENSHOT: Add host dialog filled in with example values -->

## What's Next

- [SSH Connections](User-Guide-SSH-Connections) — organize hosts with groups and tags
- [Terminal](User-Guide-Terminal) — learn the keyboard shortcuts
- [Settings](User-Guide-Settings) — set up auto-reconnect and keep-alive
```

- [ ] **Step 2: Create `docs/wiki/User-Guide-SSH-Connections.md`**

```markdown
# SSH Connections

Manage all your saved connection profiles from the **Hosts** screen (sidebar → house icon).

<!-- SCREENSHOT: Hosts dashboard showing grouped hosts with tags and the smart filter bar active -->

## Adding a Host

Click **+** on the Hosts screen (or **Cmd/Ctrl+N** from anywhere). Required fields:

| Field | Description |
|---|---|
| Hostname / IP | Domain or IP address of the server |
| Port | SSH port (default 22) |
| Username | Login user |
| Auth method | See below |

### Auth Methods

| Method | When to use |
|---|---|
| **Password** | Simple auth; stored in OS keychain |
| **Private Key** | PEM or OpenSSH key file; optional passphrase |
| **Certificate** | CA-signed key + certificate file (`.pub` format) |
| **SSH Agent** | Delegates to `SSH_AUTH_SOCK` (macOS/Linux) or `\\.\pipe\openssh-ssh-agent` (Windows 10+) |

### Jump Host / Bastion

In the host detail panel, expand **Jump Host** and select any other saved host as the bastion. YourSSH tunnels through the bastion transparently.

## Groups

Click **New Group** to create a folder. Drag hosts into groups to keep the list organized. Groups are collapsible.

## Tags

Add comma-separated tags in the host detail panel (e.g., `production, eu-west, k8s`). Tags are searchable and filterable.

## Smart Filter

The search bar at the top of the Hosts screen supports faceted queries:

```
tag:production os:ubuntu
env:staging port:2222
```

Combine with `AND` / `OR`, or toggle the chip buttons for common filters.

## Importing Hosts

**Settings → Import** accepts:
- OpenSSH `~/.ssh/config` format (paste or file)
- YourSSH JSON export
- CSV (hostname, port, username columns)

Each import shows a per-host include/exclude toggle before committing.

## Related Pages

- [Port Forwarding](User-Guide-Port-Forwarding) — attach tunnels to a host
- [Sync](User-Guide-Sync) — back up and migrate your host list
```

- [ ] **Step 3: Verify files**

```bash
ls docs/wiki/User-Guide-Getting-Started.md docs/wiki/User-Guide-SSH-Connections.md
```

- [ ] **Step 4: Commit**

```bash
git add docs/wiki/User-Guide-Getting-Started.md docs/wiki/User-Guide-SSH-Connections.md
git commit -m "docs(wiki): add Getting Started and SSH Connections pages"
```

---

## Task 3: User Guide — Terminal + SFTP

**Files:**
- Create: `docs/wiki/User-Guide-Terminal.md`
- Create: `docs/wiki/User-Guide-SFTP.md`

- [ ] **Step 1: Create `docs/wiki/User-Guide-Terminal.md`**

```markdown
# Terminal

YourSSH wraps xterm-256color terminal emulation with productivity features built on top.

<!-- SCREENSHOT: Split terminal view with two panes side-by-side, search bar visible -->

## Opening a Session

Click any host card on the Hosts screen. A new tab opens and the connection starts automatically.

## Tabs

Each SSH session opens in its own tab in the top bar. The tab shows the host name and a colored status indicator.

| Indicator | Meaning |
|---|---|
| Green dot | Connected |
| Yellow spinner | Connecting / reconnecting |
| Red dot | Disconnected / error |

## Split View

Split the active session into two panes:

| Action | Shortcut |
|---|---|
| Split horizontally | **Cmd/Ctrl+Shift+H** |
| Split vertically | **Cmd/Ctrl+Shift+V** |
| Close split | Close one of the panes |

Both panes share the same SSH session. Splitting is useful for running commands in parallel on the same host.

## Broadcast Mode

Send the same keystrokes to **all open sessions** simultaneously. Click the **Broadcast** toolbar button (or use the keyboard shortcut) to toggle. A red banner indicates broadcast is active. Use with caution.

## Search in Scrollback

Press **Cmd/Ctrl+F** to open the search bar. Type a regex or plain string; all matches highlight in the buffer. Navigate with **Enter** (next) / **Shift+Enter** (previous). Press **Esc** to close.

## Command Palette

Press **Cmd/Ctrl+K** to open the Command Palette. Fuzzy-search across:
- Saved hosts (connect directly)
- Navigation sections
- Saved snippets
- App actions (new tab, toggle split, etc.)

## Command History

YourSSH stores a per-session command history. Press **↑ / ↓** in the input bar to navigate. History is also searchable via the suggestion popup.

## Snippets

Open the **Snippets** panel from the sidebar to inject saved commands. Snippets support variables (e.g., `{{hostname}}`). See [SSH Connections](User-Guide-SSH-Connections) for adding snippets.

## Hotkeys

All keyboard shortcuts are customizable. See [Settings](User-Guide-Settings) for the full list and how to rebind.

## Themes & Fonts

35 built-in terminal color themes (Dracula, Solarized, Gruvbox, Nord, One Dark, and more) plus 7 monospace fonts including Nerd Font support. Configure in **Settings → Terminal**.

<!-- SCREENSHOT: Theme picker showing the grid of color previews -->

## Network Stats Overlay

Click the **signal bars** icon in the session toolbar to show a real-time traffic widget for the active session.

## Local Terminal

The sidebar also has a **Local Terminal** section that opens a native shell (zsh/bash/PowerShell) alongside SSH sessions.

## Related Pages

- [Recording](User-Guide-Recording) — record the current session to an Asciinema file
- [Settings](User-Guide-Settings) — customize hotkeys and themes
```

- [ ] **Step 2: Create `docs/wiki/User-Guide-SFTP.md`**

```markdown
# SFTP

The dual-panel SFTP screen lets you browse and transfer files between local and remote filesystems side-by-side.

<!-- SCREENSHOT: Dual-panel SFTP view with local panel on left, remote panel on right, a transfer in progress shown at the bottom -->

## Opening SFTP

Click the **SFTP** tab in the top bar or select **SFTP** from the sidebar. The left panel shows your local filesystem; the right panel shows the remote.

You can also open SFTP for a specific session from the session toolbar.

## Navigation

- Click a folder to open it.
- Click the breadcrumb trail to jump up.
- Press **Backspace** or the **←** button to go up one level.

## Transferring Files

| Action | How |
|---|---|
| **Upload** | Select local file(s) → click **Upload** (or drag to the remote panel) |
| **Download** | Select remote file(s) → click **Download** (or drag to the local panel) |
| **Progress** | A transfer dialog shows per-file progress and speed |

Transfers are chunked and show a real-time progress bar.

## File Operations

Right-click any file or folder for the context menu:

| Operation | Description |
|---|---|
| Rename | Rename in place |
| Delete | Permanently delete (no trash) |
| New folder | Create a directory |
| Permissions | Edit Unix permissions (remote only) |

## Tips

- Use **Cmd/Ctrl+Click** to select multiple files before transferring.
- The breadcrumb on both panels is clickable — click any segment to jump directly.
- Large transfers run in the background; you can switch to the terminal while waiting.

## Related Pages

- [SSH Connections](User-Guide-SSH-Connections) — SFTP uses the same auth as SSH
- [Port Forwarding](User-Guide-Port-Forwarding) — SFTP works through port-forwarded connections
```

- [ ] **Step 3: Verify and commit**

```bash
ls docs/wiki/User-Guide-Terminal.md docs/wiki/User-Guide-SFTP.md
git add docs/wiki/User-Guide-Terminal.md docs/wiki/User-Guide-SFTP.md
git commit -m "docs(wiki): add Terminal and SFTP pages"
```

---

## Task 4: User Guide — Port Forwarding + Recording + AI Chat

**Files:**
- Create: `docs/wiki/User-Guide-Port-Forwarding.md`
- Create: `docs/wiki/User-Guide-Recording.md`
- Create: `docs/wiki/User-Guide-AI-Chat.md`

- [ ] **Step 1: Create `docs/wiki/User-Guide-Port-Forwarding.md`**

```markdown
# Port Forwarding

Create SSH tunnels to expose remote ports locally, forward local ports to a remote, or set up a SOCKS5 proxy.

<!-- SCREENSHOT: Port Forwarding screen listing several active tunnels with status badges -->

## Tunnel Types

| Type | Use case |
|---|---|
| **Local** | Access a remote service on a local port (e.g., `localhost:5432` → `db:5432`) |
| **Remote** | Expose a local port on the remote server |
| **Dynamic** | SOCKS5 proxy — route arbitrary TCP traffic via the SSH host |

## Adding a Tunnel

1. Open **Port Forwarding** from the sidebar.
2. Click **+** and fill in:
   - **Type** — Local, Remote, or Dynamic
   - **Local port** — port on your machine
   - **Remote host / port** — destination (for Local/Remote; not needed for Dynamic)
   - **Host** — which SSH session to tunnel through
3. Click **Save**. The rule is persisted and can be started/stopped independently.

## Starting and Stopping

Toggle the **Active** switch on any tunnel rule. Active tunnels show a green indicator. You can have multiple tunnels active at the same time.

## Active Tunnels Panel

The **Tunnels** section in the sidebar shows runtime state (as opposed to Port Forwarding which shows persistent rules). Tunnels started from the DevOps tools (e.g., Cloudflare) also appear here.

## Example: Local PostgreSQL Tunnel

```
Type:         Local
Local port:   5432
Remote host:  localhost
Remote port:  5432
Via host:     my-db-server
```

After activating, connect your SQL client to `localhost:5432`.

## Related Pages

- [SSH Connections](User-Guide-SSH-Connections) — tunnels require a saved host
- [DevOps Plugin](User-Guide-DevOps-Plugin) — Cloudflare tunnels live in the DevOps hub
```

- [ ] **Step 2: Create `docs/wiki/User-Guide-Recording.md`**

```markdown
# Recording

Record your terminal sessions to Asciinema v2 (`.cast`) files and replay them later.

<!-- SCREENSHOT: Recording Library screen showing a list of recordings with host names and timestamps, one expanded with the player widget visible -->

## Starting a Recording

Click the **record** (●) button in the session toolbar. A red indicator appears in the tab while recording is active.

To stop, click the toolbar button again or close the session.

## Auto-Record

Enable **Auto-record** per host in the host detail panel. Every new session for that host starts recording automatically.

## Recording Library

Open **Recordings** from the sidebar to see all saved `.cast` files, organized by host. Click any entry to open the player.

### Player Controls

| Control | Action |
|---|---|
| Play / Pause | Space or the play button |
| Speed | 0.5× – 5× via the speed dropdown |
| Seek | Click anywhere on the progress bar |

## File Location

Recordings are saved to `~/.yourssh/recordings/<username>@<hostname>/session_YYYY-MM-DD_HH-mm-ss.cast`.

## Related Pages

- [Terminal](User-Guide-Terminal) — recording is started from the terminal toolbar
```

- [ ] **Step 3: Create `docs/wiki/User-Guide-AI-Chat.md`**

```markdown
# AI Chat

An AI assistant sidebar that you can open alongside any terminal session.

<!-- SCREENSHOT: Terminal with the AI Chat sidebar open on the right, showing a conversation with a command suggestion and a tool result -->

## Opening the Sidebar

Click the **AI** button in the session toolbar (or press the configured hotkey). The sidebar slides in without resizing the terminal pane.

## Supported Providers

| Provider | Models available |
|---|---|
| **Anthropic Claude** | claude-opus-4-8, claude-sonnet-4-6, claude-haiku-4-5, and others |
| **OpenAI** | gpt-4o, gpt-4o-mini, and others |
| **Google Gemini** | gemini-2.0-flash, gemini-1.5-pro, and others |

Configure API keys and default model in **Settings → AI**.

## Tool Calling

The AI can call tools to help you:

| Tool | What it does |
|---|---|
| `exec_command` | Runs a shell command on the active session and returns the output |
| `read_file` | Reads a remote file via SFTP |
| `list_directory` | Lists a remote directory |

Tool calls are shown inline in the conversation with the command and output. The AI never executes commands without showing you first.

## Tips

- Paste error output into the chat and ask "what does this mean?"
- Ask "how do I restart nginx on this system?" — the AI can exec the command for you.
- Use the model selector in the sidebar header to switch models mid-conversation.

## Related Pages

- [Settings](User-Guide-Settings) — configure API keys and default model
- [Terminal](User-Guide-Terminal) — the AI sidebar is opened from the terminal toolbar
```

- [ ] **Step 4: Verify and commit**

```bash
ls docs/wiki/User-Guide-Port-Forwarding.md docs/wiki/User-Guide-Recording.md docs/wiki/User-Guide-AI-Chat.md
git add docs/wiki/User-Guide-Port-Forwarding.md docs/wiki/User-Guide-Recording.md docs/wiki/User-Guide-AI-Chat.md
git commit -m "docs(wiki): add Port Forwarding, Recording, AI Chat pages"
```

---

## Task 5: User Guide — Sync + DevOps Plugin + Settings

**Files:**
- Create: `docs/wiki/User-Guide-Sync.md`
- Create: `docs/wiki/User-Guide-DevOps-Plugin.md`
- Create: `docs/wiki/User-Guide-Settings.md`

- [ ] **Step 1: Create `docs/wiki/User-Guide-Sync.md`**

```markdown
# Sync

Back up your host list and credentials across devices using **Cloud Sync** (Supabase) or transfer them in one shot via **P2P LAN**.

<!-- SCREENSHOT: Settings → Sync tab showing the Cloud Sync section with "Synced" status badge and the P2P Transfer QR code dialog -->

## Cloud Sync (Supabase)

All data is **AES-256-GCM encrypted on the client** before upload — Supabase only stores ciphertext.

### Setup

1. Create a free project at [supabase.com](https://supabase.com).
2. Copy the **Project URL** and **Anon key** from **Project Settings → API**.
3. In YourSSH: **Settings → Sync → Cloud Sync** — enter URL and key, click **Save & Test**.
4. If the `sync_data` table is missing, the app shows the SQL to run in the Supabase SQL Editor:

```sql
create table sync_data (
  id text primary key,
  payload text not null,
  updated_at timestamptz not null default now()
);
alter table sync_data enable row level security;
```

5. Optionally set an **Encryption passphrase** for stronger protection. The passphrase mixes into the key derivation — without it, anyone with your anon key could decrypt.

### How sync works

- **Push**: fires automatically on every host mutation; retries every 30 s on failure.
- **Pull**: runs on window focus when `remote.updated_at > last_push_at`.
- Sync is enabled as soon as URL and key are set — there is no separate toggle.

### Connecting additional devices

Enter the **same URL, key, and passphrase** on each device. They will sync automatically.

### Troubleshooting

| Error | Fix |
|---|---|
| `Table not found` | Run the SQL above in the Supabase SQL Editor |
| `Invalid API key` | Re-check **Project Settings → API** |
| Wrong passphrase | Ensure the same passphrase is set on all devices |

## P2P Transfer (LAN QR)

A one-shot transfer between two devices on the same network. No cloud account required.

### Steps

**Sender device:**
1. **Settings → Sync → P2P Transfer** → **Show QR Code**.
2. If multiple network interfaces are available, pick the one the receiver can reach.
3. QR code is valid for 2 minutes.

**Receiver device:**
1. **Settings → Sync → P2P Transfer** → **Scan QR** (or paste the code manually).
2. The app fetches the encrypted payload, decrypts it, and imports the hosts.

The sender's HTTP server closes automatically after one successful transfer.

## Related Pages

- [SSH Connections](User-Guide-SSH-Connections) — the host list that gets synced
```

- [ ] **Step 2: Create `docs/wiki/User-Guide-DevOps-Plugin.md`**

```markdown
# DevOps Plugin

The built-in DevOps hub adds infrastructure tooling on top of your SSH sessions. Open it from the sidebar → **DevOps** (wrench icon).

<!-- SCREENSHOT: DevOps hub showing the tool grid: Containers, Network Tools, Cloudflare Tunnel, MCP Server, Mail Catcher, S3 Browser tabs -->

## Containers (Docker / Kubernetes)

List and exec into running containers on the active SSH session.

### Docker

- Lists containers from `docker ps`
- Click **Exec** to open a shell in any container in a new terminal tab

### Kubernetes

- Lists pods from `kubectl get pods -n <namespace>`
- Namespace filter + **All namespaces** toggle
- Click **Exec** to shell into any container in a pod
- If Docker or kubectl is missing, the panel shows install/permission hints

## Network Tools

Run diagnostic commands on the remote host directly from the UI:

| Tool | Command |
|---|---|
| Ping | `ping -c 4 <host>` |
| cURL | HTTP request with headers and response |
| DNS Lookup | `dig <domain>` |
| Traceroute | `traceroute <host>` |
| Port Scan | `nc -zv <host> <port>` |
| Netstat | Open connections summary |
| Disk Usage | `df -h` |
| Memory Info | `free -h` |
| HTTP Headers | `curl -I <url>` |
| SSL Certificate | Certificate chain and expiry |

## Cloudflare Tunnel

Start a quick tunnel via `cloudflared` on the remote host. The public HTTPS URL appears instantly. Use it to expose a dev server without firewall changes.

Requires `cloudflared` installed on the remote host.

## MCP Server Gateway

Run an MCP (Model Context Protocol) server on a remote host and forward it locally. The forwarded port is usable by any MCP-compatible AI client.

## Mail Catcher

Connect to a remote MailCatcher SMTP instance via port forward. Inspect captured emails in a built-in two-panel viewer (list + body with HTML/text toggle).

## S3 Browser

Browse, upload, and delete objects in any S3-compatible bucket (AWS S3, MinIO, Cloudflare R2, etc.).

<!-- SCREENSHOT: S3 Browser showing a bucket listing with file names, sizes, and upload button -->

## Web Tools

The **Web Tools** plugin provides an in-app HTTP browser over a port-forwarded connection — useful for hitting internal APIs or admin UIs without opening a real browser.

## Related Pages

- [Port Forwarding](User-Guide-Port-Forwarding) — tunnels used by Cloudflare and MCP tools
- [Settings](User-Guide-Settings) — enable/disable DevOps plugin from Settings → Plugins
```

- [ ] **Step 3: Create `docs/wiki/User-Guide-Settings.md`**

```markdown
# Settings

Open **Settings** from the sidebar (gear icon).

<!-- SCREENSHOT: Settings screen open on the Terminal tab showing theme picker and font selector -->

## Terminal

| Setting | Description |
|---|---|
| **Color theme** | 35 built-in themes; visual picker grid |
| **Font** | 7 bundled fonts (DejaVu, Meslo LGS, Inconsolata, Source Code Pro, Ubuntu Mono, Roboto Mono, MesloLGS NF) |
| **Font size** | Adjust terminal font size |

## Connection

| Setting | Default | Description |
|---|---|---|
| **Keep-alive interval** | 10 s | Sends SSH keep-alive packets at this interval. Options: 10 s, 30 s, 60 s, 5 min, Disabled |
| **Auto-reconnect attempts** | Unlimited (0) | Number of reconnect attempts on disconnect. `0` = unlimited with linear back-off countdown |

### Auto-reconnect behavior

When the SSH connection drops, YourSSH automatically attempts to reconnect. With **Unlimited** selected, the countdown timer in the tab shows the back-off delay (increases linearly). To disable auto-reconnect, set the value to `1` (or a specific number).

## Hotkeys

All keyboard shortcuts are customizable. Click any shortcut row and press the new key combination. Changes take effect immediately.

| Action | Default |
|---|---|
| New session | Cmd/Ctrl+N |
| Close session | Cmd/Ctrl+W |
| Next session | Cmd/Ctrl+] |
| Previous session | Cmd/Ctrl+[ |
| Toggle input bar | Cmd/Ctrl+Shift+I |
| Split horizontal | Cmd/Ctrl+Shift+H |
| Split vertical | Cmd/Ctrl+Shift+V |

## AI

Enter API keys for AI providers:

| Provider | Key type |
|---|---|
| Anthropic Claude | `sk-ant-...` |
| OpenAI | `sk-...` |
| Google Gemini | AIza... |

Select the default model per provider. Keys are stored in the OS keychain.

## Sync

See [Sync](User-Guide-Sync) for full setup instructions.

## Plugins

Toggle Dart plugins (DevOps, Web Tools, Snippets) on or off. JS script plugins are managed via the Plugin Manager screen (sidebar → Plugins section).

## Related Pages

- [Terminal](User-Guide-Terminal) — themes and fonts apply to the terminal
- [AI Chat](User-Guide-AI-Chat) — configure API keys here
- [Sync](User-Guide-Sync) — cloud and P2P sync setup
```

- [ ] **Step 4: Verify and commit**

```bash
ls docs/wiki/User-Guide-Sync.md docs/wiki/User-Guide-DevOps-Plugin.md docs/wiki/User-Guide-Settings.md
git add docs/wiki/User-Guide-Sync.md docs/wiki/User-Guide-DevOps-Plugin.md docs/wiki/User-Guide-Settings.md
git commit -m "docs(wiki): add Sync, DevOps Plugin, Settings pages"
```

---

## Task 6: Developer Guide — Architecture + Build

**Files:**
- Create: `docs/wiki/Developer-Guide-Architecture.md`
- Create: `docs/wiki/Developer-Guide-Build.md`

- [ ] **Step 1: Create `docs/wiki/Developer-Guide-Architecture.md`**

```markdown
# Architecture

YourSSH is a Flutter desktop app targeting macOS, Windows, and Linux. The active codebase is `app/`; a Rust `core/` library exists for future `flutter_rust_bridge` integration but is not used at runtime.

## Monorepo Layout

```
yourssh/
├── app/                        # Flutter app (the active product)
│   ├── lib/
│   │   ├── main.dart           # Entry point; wires providers and callbacks
│   │   ├── models/             # Data models (Host, SshSession, PortForward, …)
│   │   ├── providers/          # ChangeNotifier state (HostProvider, SessionProvider, …)
│   │   ├── services/           # Business logic (SshService, StorageService, SyncService, …)
│   │   ├── screens/            # Top-level screen (MainScreen)
│   │   ├── widgets/            # All widget files (one per feature area)
│   │   └── theme/              # AppColors, AppTheme constants
│   └── pubspec.yaml
├── packages/
│   ├── dartssh2/               # Local fork of dartssh2 (SSH/SFTP/port-forward)
│   ├── yourssh_plugin_api/     # Abstract plugin interface (YourSSHPlugin)
│   ├── yourssh_devops/         # DevOps Dart plugin (containers, network tools, …)
│   ├── yourssh_web_tools/      # Web Tools Dart plugin
│   ├── yourssh_snippets/       # Snippets Dart plugin
│   └── yourssh_script_engine/  # JS plugin runtime (QuickJS FFI, HookBus, bridges)
└── core/                       # Rust library (inactive at runtime)
```

## Data Flow

```
Flutter UI (widgets/)
  └── Providers (ChangeNotifier, via provider package)
        ├── HostProvider        ─── CRUD hosts → StorageService → SharedPreferences
        ├── SessionProvider     ─── manages SshSession objects
        │     └── SshService    ─── SSHClient/SSHSession maps keyed by hostId
        │           └── dartssh2 (local fork) ──► Remote SSH host
        ├── SyncProvider        ─── SyncService ──► Supabase REST API
        ├── PortForwardProvider ─── persistent tunnel rules
        └── SettingsProvider    ─── app-wide prefs (SharedPreferences)
```

## Key Providers

| Provider | Responsibility |
|---|---|
| `HostProvider` | CRUD for saved hosts; fires `onMutation` → sync push |
| `SessionProvider` | Active `SshSession` objects; auto-reconnect, TOFU, key lookup |
| `KeyProvider` | SSH key entries (path + optional passphrase + cert path) |
| `PortForwardProvider` | Persistent tunnel rules |
| `TunnelProvider` | Runtime tunnel state (separate from rules) |
| `SyncProvider` | Supabase config; `enabled` derived from `isSupabaseConfigured` |
| `SettingsProvider` | App-wide prefs: reconnect, keep-alive, hotkeys, feature flags |
| `AiChatProvider` | AI chat state; multi-provider (Anthropic/OpenAI/Gemini) |
| `RecordingProvider` | Recording library; wired to SessionProvider via callback |

## Key Services

| Service | Responsibility |
|---|---|
| `SshService` | Owns `SSHClient` / `SSHSession` maps; connect, shell, exec, SFTP, disconnect |
| `StorageService` | Secure-first credential storage (Keychain → SharedPreferences fallback) |
| `SyncService` | AES-256-GCM encrypt → Supabase upsert; pull on window focus |
| `P2PSyncService` | One-shot LAN HTTP server + QR key exchange |
| `RecordingService` | Writes `.cast` (Asciinema v2) files per session |
| `HotkeyService` | Global hotkey registration via `hotkey_manager` |

## Credential Storage

```
StorageService.saveSecret(key, value)
  │
  ├── Try: FlutterSecureStorage (Keychain / Credential Manager)
  │     └── On success: purge stale SharedPreferences copy
  └── Fallback: SharedPreferences (plaintext)

Keys: pw_<hostId>, pp_<keyId>, sync_passphrase
```

## Navigation

`MainScreen` (`app/lib/screens/main_screen.dart`) renders:
- Top tab bar — pinned Home/SFTP + scrollable SSH session tabs
- Left sidebar — `NavSection` enum maps to feature screens

## Related Pages

- [Build](Developer-Guide-Build) — how to compile the app
- [Plugin System](Developer-Guide-Plugin-System) — how plugins integrate
```

- [ ] **Step 2: Create `docs/wiki/Developer-Guide-Build.md`**

```markdown
# Build

YourSSH targets macOS, Windows, and Linux via Flutter.

## Prerequisites

- **Flutter 3.x** — install via [flutter.dev](https://flutter.dev/docs/get-started/install)
- Run `flutter doctor` and resolve any issues before building
- Platform-specific tooling:
  - macOS: Xcode 15+
  - Windows: Visual Studio 2022 with "Desktop development with C++" workload
  - Linux: `clang cmake ninja-build pkg-config libgtk-3-dev`

## Run in Development

```bash
# macOS
cd app && flutter run -d macos

# Windows
cd app && flutter run -d windows

# Linux
cd app && flutter run -d linux
```

## Build Release

```bash
# macOS — outputs app/build/macos/Build/Products/Release/YourSSH.app
cd app && flutter build macos

# Windows — outputs app/build/windows/x64/runner/Release/
cd app && flutter build windows

# Linux — outputs app/build/linux/x64/release/bundle/
cd app && flutter build linux
```

## Lint & Tests

```bash
# Static analysis
cd app && flutter analyze

# All tests
cd app && flutter test

# Single test file
cd app && flutter test test/services/sync_service_test.dart

# Filter by test name pattern
cd app && flutter test --name "SyncService"
```

## Local Package Dependencies

`app/pubspec.yaml` uses `dependency_overrides` to pull the local fork of `dartssh2` and all `yourssh_*` packages:

```yaml
dependency_overrides:
  dartssh2:
    path: ../packages/dartssh2
  yourssh_plugin_api:
    path: ../packages/yourssh_plugin_api
  # … etc
```

If you modify a package in `packages/`, the app picks up the change immediately — no publish step needed.

## Rust Core (Inactive)

The `core/` Rust library is not linked into the app at runtime. If you want to build it:

```bash
make setup   # Install Rust targets + xcodegen
make core    # Build universal .a + Swift bindings
make clean   # Remove Rust artifacts
```

## CI / Release

GitHub Actions workflows live in `.github/workflows/`. The `release.yml` workflow builds for all three platforms and attaches artifacts to the GitHub Release on tag push.

## Related Pages

- [Architecture](Developer-Guide-Architecture) — understand the codebase before modifying
- [Contributing](Developer-Guide-Contributing) — PR and release workflow
```

- [ ] **Step 3: Verify and commit**

```bash
ls docs/wiki/Developer-Guide-Architecture.md docs/wiki/Developer-Guide-Build.md
git add docs/wiki/Developer-Guide-Architecture.md docs/wiki/Developer-Guide-Build.md
git commit -m "docs(wiki): add Architecture and Build developer guide pages"
```

---

## Task 7: Developer Guide — Plugin System + Plugin Authoring + Contributing

**Files:**
- Create: `docs/wiki/Developer-Guide-Plugin-System.md`
- Create: `docs/wiki/Developer-Guide-Plugin-Authoring.md`
- Create: `docs/wiki/Developer-Guide-Contributing.md`

- [ ] **Step 1: Create `docs/wiki/Developer-Guide-Plugin-System.md`**

```markdown
# Plugin System

YourSSH supports two types of plugins that coexist at runtime.

## Type 1: Dart Plugins (compile-time)

Compiled into the app binary. Registered in `app/lib/plugins/plugin_registry.dart` (`kRegisteredPlugins`).

### Adding a Dart Plugin

1. Add the package to `app/pubspec.yaml` dependencies and `dependency_overrides` (if local).
2. Import and instantiate in `plugin_registry.dart`.

### YourSSHPlugin Interface (`yourssh_plugin_api`)

```dart
abstract class YourSSHPlugin {
  Widget buildUI(BuildContext context, YourSSHPluginContext ctx);
  Future<void> onActivate(YourSSHPluginContext ctx);
  Future<void> onDeactivate();
  int get minApiVersion;
}
```

`YourSSHPluginContext` exposes:
- `activeSessions` — list of active SSH session IDs
- `execCommand(sessionId, cmd)` — run a command on a session
- `savePreference(key, value)` / `getPreference(key)` — namespaced storage

### Bundled Dart Plugins

| Package | Features |
|---|---|
| `yourssh_devops` | Containers, Network Tools, Cloudflare Tunnel, MCP Server, Mail Catcher, S3 Browser |
| `yourssh_web_tools` | In-app HTTP browser over port-forwarded connection |
| `yourssh_snippets` | Command snippet library |

## Type 2: JS Script Plugins (runtime)

Loaded at runtime from `~/.yourssh/plugins/`. No app rebuild required.

### Architecture

```
App (Dart/Flutter)
  └── PluginLoader — scans ~/.yourssh/plugins/, hot-reloads on file change
        └── QuickJsRuntime (FFI) — isolated JS context per plugin
              ├── JsRuntimeRegistrar — registers bridge APIs
              ├── HookBus — typed event routing
              └── PermissionGuard — enforces manifest permissions
```

### HookBus Event Types

| Hook type | Behavior |
|---|---|
| `transform` | Handler can modify the data (e.g., rewrite terminal output) |
| `intercept` | Handler can block the event entirely |
| `observe` | Side-effect only; cannot modify data |

### Events

| Event | Fires when |
|---|---|
| `terminal.output` | Data arrives from the SSH server |
| `terminal.input` | User types in the terminal |
| `session.connect` | Session is fully established |
| `session.disconnect` | Session closes |

### Bridges (Dart APIs callable from JS)

| Bridge | Available calls |
|---|---|
| `ssh` | `ssh.exec(sessionId, cmd)`, `ssh.write(sessionId, data)` |
| `sftp` | `sftp.list(sessionId, path)`, `sftp.readFile`, `sftp.writeFile` |
| `storage` | `storage.get(key)`, `storage.set(key, value)`, `storage.delete(key)` |
| `ui` | `ui.showNotification(msg)`, `ui.register(id, spec)` |

### Error Handling

`PluginErrorTracker` counts consecutive errors per plugin. If the threshold is exceeded, the plugin is automatically disabled. The user sees the error in the Plugin Console.

## Related Pages

- [Plugin Authoring](Developer-Guide-Plugin-Authoring) — write your first JS plugin
- [Architecture](Developer-Guide-Architecture) — where plugin loading fits in the app
```

- [ ] **Step 2: Create `docs/wiki/Developer-Guide-Plugin-Authoring.md`**

Content is the same as `docs/plugin-authoring-guide.md`. Copy it verbatim:

```bash
cp docs/plugin-authoring-guide.md docs/wiki/Developer-Guide-Plugin-Authoring.md
```

Then add this header link at the top of the copied file (insert before line 1):

```markdown
> Full guide also available at [`docs/plugin-authoring-guide.md`](../blob/master/docs/plugin-authoring-guide.md) in the repository.

```

- [ ] **Step 3: Create `docs/wiki/Developer-Guide-Contributing.md`**

```markdown
# Contributing

## Development Setup

1. Fork the repository and clone locally.
2. Follow the [Build](Developer-Guide-Build) guide to get the app running.
3. Create a feature branch from `develop`:

```bash
git checkout develop
git pull origin develop
git checkout -b feat/my-feature
```

## PR Checklist

Before opening a PR to `develop`:

- [ ] `flutter analyze` passes with no errors
- [ ] `flutter test` passes
- [ ] New features have tests in `app/test/`
- [ ] `CHANGELOG.md` updated — add an entry under `[Unreleased]`
- [ ] Relevant `docs/wiki/` page updated (or new page added)

## Wiki Updates

**Every PR that ships or modifies a user-visible feature must include a `docs/wiki/` update.**

- Existing feature changed → update the relevant `User-Guide-*.md` page
- New feature → create a new `User-Guide-*.md` page and add a row to `Home.md`
- New developer component → update or create a `Developer-Guide-*.md` page

Wiki pages are synced to GitHub Wiki automatically when the PR merges to `master`.

## Merging to master

PRs to `develop` are merged by the maintainer once CI passes. Periodic merges from `develop` → `master` cut a release. Before merging to `master`:

1. Move `[Unreleased]` → `[x.y.z]` in `CHANGELOG.md`
2. Add a fresh `[Unreleased]` block
3. Bump the version in `app/pubspec.yaml`
4. Update `docs/roadmap.md` via the `/yourssh-roadmap` skill
5. Confirm all `docs/wiki/` pages reflect the shipped state

The GitHub Action at `.github/workflows/wiki-sync.yml` syncs `docs/wiki/` to GitHub Wiki automatically on merge.

## Commit Style

```
feat(scope): add X
fix(scope): correct Y
docs(wiki): update Z page
refactor(scope): simplify W
test(scope): add tests for V
```

## Related Pages

- [Build](Developer-Guide-Build) — prerequisites and build commands
- [Architecture](Developer-Guide-Architecture) — understand the codebase
```

- [ ] **Step 4: Verify and commit**

```bash
ls docs/wiki/Developer-Guide-Plugin-System.md docs/wiki/Developer-Guide-Plugin-Authoring.md docs/wiki/Developer-Guide-Contributing.md
git add docs/wiki/
git commit -m "docs(wiki): add Plugin System, Plugin Authoring, Contributing pages"
```

---

## Task 8: GitHub Action — wiki-sync.yml

**Files:**
- Create: `.github/workflows/wiki-sync.yml`

- [ ] **Step 1: Verify `.github/workflows/` exists**

```bash
ls .github/workflows/
```

Expected: directory exists with at least one `.yml` file.

- [ ] **Step 2: Create `.github/workflows/wiki-sync.yml`**

```yaml
name: Sync Wiki

on:
  push:
    branches:
      - master
    paths:
      - 'docs/wiki/**'

jobs:
  sync:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Flatten wiki subdirectories
        run: |
          mkdir -p /tmp/wiki-flat
          # Copy flat .md files directly
          find docs/wiki -maxdepth 1 -name '*.md' -exec cp {} /tmp/wiki-flat/ \;
          # Copy subdirectory files with prefix (User-Guide- / Developer-Guide-)
          for subdir in docs/wiki/*/; do
            prefix=$(basename "$subdir" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print}' | sed 's/ /-/g')
            for f in "$subdir"*.md; do
              [ -f "$f" ] || continue
              fname=$(basename "$f")
              cp "$f" "/tmp/wiki-flat/${prefix}-${fname}"
            done
          done
          ls /tmp/wiki-flat/

      - name: Sync to GitHub Wiki
        uses: Andrew-Chen-Wang/github-wiki-action@v4
        with:
          path: /tmp/wiki-flat/
          token: ${{ secrets.GITHUB_TOKEN }}
          commit-message: "chore: sync wiki from docs/wiki/"
```

> **Note:** The flatten step handles the `user-guide/` and `developer-guide/` subdirectory structure from the spec. If using the flat layout (all files directly in `docs/wiki/`), remove the flatten step and point `path` directly at `docs/wiki/`.

- [ ] **Step 3: Verify YAML is valid**

```bash
python3 -c "import yaml, sys; yaml.safe_load(open('.github/workflows/wiki-sync.yml'))" && echo "YAML valid"
```

Expected: `YAML valid`

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/wiki-sync.yml
git commit -m "ci: add wiki-sync GitHub Action"
```

---

## Task 9: Update yourssh-roadmap skill

**Files:**
- Modify: `.claude/skills/yourssh-roadmap/SKILL.md`

- [ ] **Step 1: Add wiki update reminder after the "Common mistakes" section**

The skill file is at `.claude/skills/yourssh-roadmap/SKILL.md` (relative to the repo root). Open it and find the `## Common mistakes` section. After the last bullet (`- ❌ Changing section/table format structure…`), add:

```markdown
- ❌ Forgetting to update the wiki when shipping a feature. **Always update `docs/wiki/` alongside `docs/roadmap.md`:**
  - User-visible feature shipped → update or create `docs/wiki/User-Guide-*.md`
  - New developer component → update `docs/wiki/Developer-Guide-*.md`
  - New feature area → add a row to `docs/wiki/Home.md`
```

- [ ] **Step 2: Verify the edit**

```bash
grep -A5 "Forgetting to update the wiki" .claude/skills/yourssh-roadmap/SKILL.md
```

Expected: the new bullet appears.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/yourssh-roadmap/SKILL.md
git commit -m "docs(skill): remind wiki update in yourssh-roadmap skill"
```

---

## Task 10: Final verification

- [ ] **Step 1: Count wiki pages**

```bash
ls docs/wiki/*.md | wc -l
```

Expected: 16 (Home + 10 User Guide + 5 Developer Guide).

- [ ] **Step 2: Verify no broken internal links**

```bash
grep -rh '\[.*\](.*-Guide-' docs/wiki/ | grep -v 'http' | sort -u
```

Review output — all linked page names should match a file in `docs/wiki/`.

- [ ] **Step 3: Verify GitHub Action file**

```bash
cat .github/workflows/wiki-sync.yml
```

- [ ] **Step 4: Final commit if anything was missed**

```bash
git status
# If clean: nothing to do.
# If files unstaged: git add docs/wiki/ .github/ && git commit -m "docs(wiki): finalize wiki pages"
```

- [ ] **Step 5: Push develop branch**

```bash
git push origin develop
```

---

## Prerequisites (before Task 8 Action runs)

1. **Enable GitHub Wiki** on the repo: Settings → Features → Wiki ✓
2. **Create the first wiki page** manually on GitHub (the wiki repo must exist before the Action can push to it). Go to `<repo>/wiki` → click "Create the first page" → save anything. The Action will overwrite it.
