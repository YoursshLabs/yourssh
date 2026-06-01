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
