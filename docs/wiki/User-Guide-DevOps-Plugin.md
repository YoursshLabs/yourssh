# DevOps Plugin

The built-in DevOps hub adds infrastructure tooling on top of your SSH sessions. Open it from the sidebar → **DevOps** (wrench icon).

<!-- SCREENSHOT: DevOps hub showing the tool grid: Containers, Network Tools, Cloudflare Tunnel, MCP Server, Mail Catcher, S3 Browser tabs -->

## Containers (Docker / Compose / Kubernetes)

Manage containers and Compose stacks on the active SSH session. Pick a session, tap **Scan** to detect runtimes, then switch between the **Docker**, **Compose**, and **Kubernetes** tabs. If a runtime is missing the panel shows an install/permission hint with a copyable command.

### Docker

- Lists all containers (`docker ps -a`), running and stopped
- Per-container lifecycle: **Stop** / **Restart** (running) or **Start** (stopped)
- **Exec** opens a shell in the container in a new terminal tab
- **Logs** opens an inline follow-mode viewer (`docker logs -f`) below the list — auto-scrolls while you stay at the bottom, detaches when you scroll up, **Clear** to reset, capped at 2000 lines

### Compose

- Discovers Compose v2 stacks by combining `docker compose ls` (active projects) with a `find` sweep of `~ /opt /srv /home`; active-project status wins when a stack appears in both
- **+** adds a Compose file by path manually (validated with `docker compose -f … config`)
- Per-stack **Up** (`up -d`) / **Down**; select a stack to list its services
- Per-service **Start** / **Stop**, replica count, and an inline follow-mode log viewer (`docker compose logs -f <service>`)
- Docker Compose **v1** (`docker-compose`) is not supported — discovery degrades to find-only

### Kubernetes

- Lists pods from `kubectl get pods -n <namespace>`
- Namespace filter + **All namespaces** toggle
- Click **Exec** to shell into any container in a pod
- `kubectl logs -f` and 1-click port-forward

All container commands are recorded in the [Audit Log](User-Guide-Audit-Log) with source `devops`.

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
