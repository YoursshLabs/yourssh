# Terminal

YourSSH wraps xterm-256color terminal emulation with productivity features built on top.

<!-- SCREENSHOT: Split terminal view with two panes side-by-side, search bar visible -->

## Opening a Session

Click any host card on the Hosts screen. A new tab opens and the connection starts automatically.

## Tabs

Each SSH session opens in its own tab in the top bar. The tab shows the host name and a **connection health badge** (a colored dot on the left).

### Connection health badge

The badge is driven by a live latency ping sent over the SSH connection on the keep-alive interval (configurable in **Settings**). Its color reflects the current round-trip latency, or the session lifecycle when not connected:

| Dot | Meaning |
|---|---|
| 🟢 Green | Healthy — latency under 150 ms |
| 🟡 Amber | Degraded — latency 150–500 ms |
| 🔴 Red | Unreachable — latency over 500 ms, ping timed out, or error |
| ⚪ Grey | Disconnected, or no reading yet |
| ✨ Pulsing amber | Connecting / reconnecting |

Because the ping rides the live channel (rather than opening a new connection), a 5-second ping timeout also catches **half-open** drops — where the network is gone but the shell has not closed yet — and turns the dot red.

Hover the dot for a tooltip showing latency, uptime, time since the last ping, and how many times the session has reconnected.

### Notification bell

A bell at the right end of the top tab bar collects in-app notifications behind an unread badge: sessions that **drop unexpectedly** (the shell closed without a pending auto-reconnect, or reconnect attempts ran out — closing a tab yourself never notifies) and **new releases** (with an inline Update button). Opening the panel marks everything read; dismiss items individually or use **Clear all**. Notifications are in-memory only and reset on app restart.

### Managing tabs

| Action | How |
|---|---|
| Rename | Double-click the tab, or right-click → **Rename** |
| Color tag | Right-click → pick one of 8 colors (shown as a dot on the tab) |
| Pin | Right-click → **Pin** — pinned tabs move to the front and hide their close button |
| Reorder | Drag a tab left/right; pinned and unpinned tabs stay within their own zones |
| Close | Hover and click ✕ (hidden while a tab is pinned) |

Tab names, colors, and pin state persist per host across reconnects and app restarts.

## Split View

Split the active session into two panes:

| Action | Shortcut |
|---|---|
| Split horizontally | **Cmd/Ctrl+Shift+H** |
| Split vertically | **Cmd/Ctrl+Shift+V** |
| Close split | Close one of the panes |

Both panes share the same SSH session. Splitting is useful for running commands in parallel on the same host.

## Broadcast Mode

Send the same keystrokes to **all open sessions** simultaneously. Click the **Broadcast** toolbar button to toggle. A red banner indicates broadcast is active. Use with caution.

## Search in Scrollback

Press **Cmd/Ctrl+F** to open the search bar. Type a regex or plain string; all matches highlight in the buffer. Navigate with **Enter** (next) / **Shift+Enter** (previous). Press **Esc** to close.

## Copy & Paste

Select text by dragging (double-click selects a word). Then:

| Action | macOS | Windows / Linux |
|---|---|---|
| Copy selection | **Cmd+C** | **Ctrl+C** (with a selection) or **Ctrl+Shift+C** |
| Paste | **Cmd+V** | **Ctrl+V** or **Ctrl+Shift+V** |
| Context menu | right-click | right-click |
| Paste (mouse) | middle-click | middle-click |

On Windows/Linux, **Ctrl+C** copies only while text is selected — the selection is cleared after copying, so pressing it again interrupts the running program (SIGINT) as usual. Right-click opens a **Copy / Paste / Select All** menu; Copy is disabled when nothing is selected. Apps that capture the mouse (vim, htop) keep receiving mouse clicks instead of triggering selection or paste.

## Shell Integration

On **bash/zsh** hosts, YourSSH injects a small, guarded prompt hook on connect so it can follow what the remote shell is doing via OSC 7 (working directory) and OSC 133 (command boundaries + exit status). It only touches the live session — it never edits your `.bashrc`/`.zshrc`.

The setup is **invisible**: YourSSH waits until the shell is actually at a prompt reading input, then delivers the hook script through a silent handshake — nothing is echoed into your terminal or recordings. Connecting just looks like an extra Enter press. If readiness can't be confirmed (exotic shells, a full-screen app, or you start typing right away) the injection is skipped for that session.

This powers:

- **Working directory on the tab** — the tab shows the current directory's name (e.g. `web-prod · app`); the full path also drives path completion.
- **Per-command status gutter** — a thin strip down the left edge draws a dot next to each command's prompt: 🟢 green = exit 0, 🔴 red = non-zero, ⚪ grey = running/unknown. Click a dot to jump to that command.
- **Jump-to-prompt** — **Cmd/Ctrl+↑ / ↓** scrolls to the previous / next command prompt.
- **cwd-aware path completion** — when you type a path in the input bar (after `cd`, `cat`, `ls`, …), the suggestion popup lists matching entries in the resolved remote directory (read over SFTP), merged with command history.

Shell integration is **on by default**. Turn it off globally in **Settings → Terminal → Shell Integration**, or per host via the **Shell integration** switch in the host detail panel. Other shells (and sessions where a multiplexer strips the markers, e.g. some tmux setups) simply run without it.

## Command Palette

Press **Cmd/Ctrl+K** to open the Command Palette. Fuzzy-search across:

- Saved hosts (connect directly)
- Navigation sections
- Saved snippets
- App actions (new tab, toggle split, etc.)

## Command History

YourSSH stores a per-session command history. Press **↑ / ↓** in the input bar to navigate. History is also searchable via the suggestion popup.

## Snippets

Open the **Snippets** panel from the sidebar to inject saved commands. Snippets support variables (e.g., `{{hostname}}`).

You can also use snippets **without leaving the terminal**: toggle the collapsible snippets panel from the terminal toolbar to browse, search, and copy snippets, or run one directly against the currently active pane (in split layouts, the focused pane). The Snippets screen can likewise type a snippet straight into the focused session.

## Themes & Fonts

44 built-in terminal color themes (Dracula, Solarized, Gruvbox, Nord, Kanagawa, Tokyo Night, Flexoki, and more — dark and light variants) plus 7 monospace fonts including Nerd Font support. Configure in **Settings → Terminal**, or without leaving the workspace: the **tune icon** in the terminal toolbar opens a right-side panel with the same theme, font size (live preview while dragging), and font controls.

<!-- SCREENSHOT: Theme picker showing the grid of color previews -->

## Network Stats Overlay

Click the **signal bars** icon in the session toolbar to show a real-time traffic widget for the active session.

## Local Terminal

The sidebar also has a **Local Terminal** section that opens a native shell (zsh/bash/PowerShell) alongside SSH sessions. The terminal is focused as soon as it opens — just start typing. On Windows the shell is PowerShell (fully working since 0.1.22).

Since 0.1.24 local shells are **first-class tabs**: they appear in the global top tab bar next to SSH sessions, can be split into panes alongside SSH panes, and can be recorded to asciicast just like SSH sessions. If the shell exits, the pane shows a status overlay with a **Restart shell** button.

## Related Pages

- [Terminal Sharing](User-Guide-Terminal-Sharing) — share a live session with teammates in real time
- [Recording](User-Guide-Recording) — record the current session to an Asciinema file
- [Settings](User-Guide-Settings) — customize hotkeys and themes
