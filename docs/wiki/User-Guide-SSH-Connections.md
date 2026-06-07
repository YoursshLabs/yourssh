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

### Generating SSH Keys

The **Keychain** screen can generate key pairs in-app — no terminal needed:

- **Ed25519** (recommended) — generated in pure Dart, works everywhere
- **RSA-4096 / ECDSA-P256** — uses the system `ssh-keygen`; these options are
  hidden if the binary isn't installed

Keys are written to `Documents/YourSSH/keys` with `600` permissions; an
optional passphrase encrypts the private key (OpenSSH format) and is stored in
the OS keychain so connections stay one-click. After generating you can **copy
the public key** or **deploy it to a host** straight from the panel — the
deploy dialog appends it to `~/.ssh/authorized_keys` over an existing
connection (idempotent: deploying twice never duplicates the line).

### Connection Chain (Jump Hosts / Bastions)

In the host detail panel, the **Connection Chain** section shows the route to
your host as connected cards. Click **Add a Host** and pick any saved host as
a bastion — and keep adding: the chain supports multiple hops
(bastion → bastion → … → destination) for layered networks. **Add a Host**
stays visible to append another hop, each hop card has a remove (×) button,
and **Clear** drops the whole chain to connect directly. A key icon appears
on the last hop when agent forwarding is enabled. Hosts already in the chain
are excluded from the picker, so you can't build a loop. Terminal sessions,
SFTP, exec, and port forwarding all tunnel through the full chain
transparently — each hop's host key is verified just like a direct
connection.

### Agent Forwarding

Enable **Agent forwarding** in the host detail panel (SESSION section) to hop
between servers with the keys on your local machine — like `ssh -A` — without
copying private keys to the intermediate server.

- Works with any auth method; applies on the next connect. Off by default.
- Keys come from your local SSH agent (`SSH_AUTH_SOCK` on macOS/Linux, the
  OpenSSH Authentication Agent pipe on Windows). If no agent is running, keys
  stored in the app Keychain (unencrypted or with a saved passphrase) are
  served instead.
- Private keys never leave your machine — only signatures cross the wire.
- If the server disallows forwarding (`AllowAgentForwarding no`), a yellow
  warning appears in the terminal and the session continues normally.
- Only enable it for hosts you trust: root on the remote can use (not read)
  your keys while the session is open.

**How to tell it's working**

- When you switch the toggle on, a status line appears and checks your local
  agent automatically: ✓ "System agent connected — N identities" means
  forwarding will serve your `ssh-agent` keys; ⚠ "No system agent — N app
  Keychain keys will be offered instead" means the app falls back to keys
  stored in its Keychain; ✗ "No agent and no usable Keychain keys" means
  forwarding would offer nothing — run `ssh-add <key>` or add a key in
  Keychain.
- While connected, the session tab shows a small key icon: grey = enabled but
  no key requests yet, green = a request was just served by your system
  agent, orange = served from app Keychain keys, red = the server refused
  forwarding (`AllowAgentForwarding no`). Hover the icon for details.
- If the server refuses forwarding you also get a notification in the bell;
  clicking it jumps to that session.

### Session Template (per-host preset)

The **SESSION TEMPLATE** section in the host detail panel pre-configures every
new session on that host. All fields are optional — anything left empty
follows your global settings.

- **Working directory** — `cd` into this path on connect. Delivered
  invisibly (no echo in the terminal, nothing in recordings); if the
  directory doesn't exist you get a one-line warning. bash/zsh only.
- **Env vars** — `NAME=value` pairs exported on connect, also invisible.
  Names must be valid POSIX identifiers; duplicates are rejected on save.
  bash/zsh only.
- **Startup snippet** — command text typed *visibly* into the shell after
  the setup completes, exactly as if you typed it (it appears in recordings
  and the audit log). Skipped when tmux is on — a tmux re-attach would run
  it again into your existing session.
- **Terminal theme / font / size** — per-host appearance override. Handy for
  making production hosts visually unmistakable (e.g. a red theme). Applies
  live to open sessions when you edit the host.
- **TERM type** and **tmux** — per-host overrides of the global Settings →
  Terminal values; applies on the next connect.

If you start typing before the setup is delivered, the app backs off and
skips the template entirely — you always own the session.

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

## Dashboard Views & Sorting

The hosts dashboard can show hosts as a card grid or a compact one-line list — toggle with the grid/list button in the toolbar. A sort dropdown orders hosts by name, creation date, or hostname, ascending or descending. Both choices persist across restarts; the default is Name A–Z.

To act on several hosts at once (connect all, run a command in parallel, push files), see [Bulk Actions](User-Guide-Bulk-Actions).

## Importing Hosts

**Settings → Import** accepts:

- OpenSSH `~/.ssh/config` format (paste or file)
- YourSSH JSON export
- CSV (hostname, port, username columns)

Each import shows a per-host include/exclude toggle before committing.

## Related Pages

- [Port Forwarding](User-Guide-Port-Forwarding) — attach tunnels to a host
- [Sync](User-Guide-Sync) — back up and migrate your host list
