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
3. Optionally tick **Auto-start on launch** to bring the tunnel up every time the app starts.
4. Click **Add Rule**. The rule is persisted and can be started/stopped independently. Click any rule later to edit it.

## Starting and Stopping

Press the **play** button on a rule to start it and the **stop** button to stop it. You can have multiple tunnels active at the same time, and tunnels don't need an open terminal tab — the app dials the SSH host with your stored credentials.

Status colors: grey = idle, amber = connecting / reconnecting, green = active, red = error (the message, e.g. "Port 8080 already in use", is shown under the rule). Active rules show a live connection counter.

## Auto-Reconnect

If the SSH link drops while a tunnel is running, the rule switches to **reconnecting** and the app re-dials with exponential backoff (2 s doubling up to 30 s) until the tunnel is back, keeping the local port bound the whole time. Stopping the rule cancels the retry.

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
