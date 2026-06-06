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

### Connection Chain (Jump Host / Bastion)

In the host detail panel, the **Connection Chain** section shows the route to
your host as connected cards. Click **Add a Host** and pick any saved host as
the bastion — the chain then reads bastion → destination, with a key icon on
the bastion card when agent forwarding is enabled. Click the bastion card to
swap it, or **Clear** to connect directly. Terminal sessions, SFTP, exec, and
port forwarding all tunnel through the bastion transparently.

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
