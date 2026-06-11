# SFTP

The dual-panel SFTP screen lets you browse and transfer files between local and remote filesystems side-by-side.

<!-- SCREENSHOT: Dual-panel SFTP view with local panel on left, remote panel on right, a transfer in progress shown at the bottom -->

## Opening SFTP

Click the **SFTP** tab in the top bar or select **SFTP** from the sidebar. Each panel has a **source chip** in its header — click it to switch that panel between your **Local** filesystem and any saved host, so you can go local ↔ remote or even remote ↔ remote. Connections, paths and in-flight transfers survive switching to other tabs; coming back to SFTP resumes where you left off.

You can also open SFTP for a specific session from the session toolbar.

## Navigation

- Click a folder to open it.
- Click the breadcrumb trail to jump up.
- **Go to path**: click the edit icon next to the breadcrumb (or its tooltip "Go to path"), type or paste any path, and press **Enter** to jump straight there — **Esc** cancels. Works on both the remote and local panels.
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

Right-click any file or folder for the context menu (shared by the remote and local panels):

| Operation | Description |
|---|---|
| Open | Open the file (built-in editor / OS default app) or enter the folder |
| View | Read-only preview (lock icon in the title bar, no save) — safe for logs and configs |
| Edit | Open in the built-in editor (Monaco; plain-text fallback where the webview is unavailable) |
| Open with ▶ | Hover submenu listing every installed app that can open the file's type, plus **Choose…** for any app. While the file is open externally, YourSSH watches the local copy and re-uploads it on every save |
| Copy to target directory | Send the entry to the folder shown in the other panel. Disabled with a reason when it can't run (no target panel, folders between two remote hosts, or both panels showing the same folder) |
| Refresh | Re-list the current directory |
| New folder | Create a directory |
| Permissions | Edit Unix permissions — see below (local panel: macOS/Linux only) |
| Rename | Rename in place |
| Delete | Permanently delete (no trash) |

## Permissions (chmod)

**Permissions** opens a chmod dialog with a 9-checkbox **rwx grid** (owner / group / others) kept in sync with an **octal field** (`644`, `0755`, `4755` — special bits survive checkbox-only edits). The field only accepts 3–4 octal digits; **Apply stays disabled** while the value is incomplete or invalid, so a half-typed mode can never be submitted.

- **Directories** get an **Apply recursively** option (`chmod -R`). The walk never follows symlinks (so a link can't change files outside the tree) and applies a directory's own mode after its contents.
- If the server doesn't report the current permissions, YourSSH stats the entry; when that also fails, the dialog warns **"Current permissions unknown"** and keeps Apply disabled until you set a mode explicitly.
- On the local panel, chmod uses the system `chmod` and is hidden on Windows.

## Sudo SFTP (root file transfers)

Each host has an **SFTP Mode** setting (host detail panel): **Default**, **Sudo (root)**, or **Custom command**. In Sudo mode the whole SFTP session — browse, upload, download, rename, delete — runs as root: YourSSH starts the remote `sftp-server` through `sudo` (WinSCP-style), auto-detecting its path across distros. `NOPASSWD` sudoers entries work silently; otherwise you are prompted for the sudo password (optionally remembered in the system keychain). Elevated panels show a **root** badge. Failures explain exactly what to fix, including a ready-to-paste `NOPASSWD` line.

## Tips

- Use **Cmd/Ctrl+Click** to select multiple files before transferring.
- The breadcrumb on both panels is clickable — click any segment to jump directly.
- Large transfers run in the background; you can switch to the terminal while waiting.

## Related Pages

- [SSH Connections](User-Guide-SSH-Connections) — SFTP uses the same auth as SSH
- [Port Forwarding](User-Guide-Port-Forwarding) — SFTP works through port-forwarded connections
