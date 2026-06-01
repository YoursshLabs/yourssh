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
