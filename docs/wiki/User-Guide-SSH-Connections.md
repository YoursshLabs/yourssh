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
