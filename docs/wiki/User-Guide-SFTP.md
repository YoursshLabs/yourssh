# SFTP

The dual-panel SFTP screen lets you browse and transfer files between local and remote filesystems side-by-side.

<!-- SCREENSHOT: Dual-panel SFTP view with local panel on left, remote panel on right, a transfer in progress shown at the bottom -->

## Opening SFTP

Click the **SFTP** tab in the top bar or select **SFTP** from the sidebar. Each panel has a **source chip** in its header — click it to switch that panel between your **Local** filesystem and any saved host, so you can go local ↔ remote or even remote ↔ remote. Connections, paths and in-flight transfers survive switching to other tabs; coming back to SFTP resumes where you left off.

You can also open SFTP for a specific session from the session toolbar.

## Navigation

- Click a folder to open it.
- Click the breadcrumb trail to jump up.
- Press **Backspace** or the **←** button to go up one level.

## Transferring Files

| Action | How |
|---|---|
| **Select** | Per-row checkboxes on both panels, or click / cmd-click rows; the header checkbox selects everything matching the current filter |
| **Upload** | Select local file(s) → click **→** (or drag to the remote panel) |
| **Download** | Select remote file(s) → click **←** (or drag to the local panel) |
| **Progress** | A panel docked at the bottom shows per-file progress |

Transfers run **in the background** — the panels stay fully usable while a
batch runs, and starting another transfer queues it onto the same panel. Use
the **—** button to minimize the panel to a slim progress strip (and **˄** to
expand it back). Successful batches dismiss themselves after a few seconds;
batches with errors stay until you close them. **Cancel** stops everything
still pending.

## File Operations

Right-click any file or folder for the context menu:

| Operation | Description |
|---|---|
| View | Read-only preview (lock icon in the title bar, no save) — safe for logs and configs |
| Edit | Open in the built-in editor (Monaco; plain-text fallback where the webview is unavailable) |
| Open with ▶ | Hover submenu listing every installed app that can open the file's type, plus **Choose…** for any app. While the file is open externally, YourSSH watches the local copy and re-uploads it on every save |
| Rename | Rename in place |
| Delete | Permanently delete (no trash) |
| New folder | Create a directory |
| Permissions | Edit Unix permissions (remote only) |

## Sudo SFTP (root file transfers)

Each host has an **SFTP Mode** setting (host detail panel): **Default**, **Sudo (root)**, or **Custom command**. In Sudo mode the whole SFTP session — browse, upload, download, rename, delete — runs as root: YourSSH starts the remote `sftp-server` through `sudo` (WinSCP-style), auto-detecting its path across distros. `NOPASSWD` sudoers entries work silently; otherwise you are prompted for the sudo password (optionally remembered in the system keychain). Elevated panels show a **root** badge. Failures explain exactly what to fix, including a ready-to-paste `NOPASSWD` line.

## Tips

- Use **Cmd/Ctrl+Click** to select multiple files before transferring.
- The breadcrumb on both panels is clickable — click any segment to jump directly.
- Large transfers run in the background; you can switch to the terminal while waiting.

## Related Pages

- [SSH Connections](User-Guide-SSH-Connections) — SFTP uses the same auth as SSH
- [Port Forwarding](User-Guide-Port-Forwarding) — SFTP works through port-forwarded connections
