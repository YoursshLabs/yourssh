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
