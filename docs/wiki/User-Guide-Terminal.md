# Terminal

YourSSH wraps xterm-256color terminal emulation with productivity features built on top.

<!-- SCREENSHOT: Split terminal view with two panes side-by-side, search bar visible -->

## Opening a Session

Click any host card on the Hosts screen. A new tab opens and the connection starts automatically.

## Tabs

Each SSH session opens in its own tab in the top bar. The tab shows the host name and a colored status indicator.

| Indicator | Meaning |
|---|---|
| Green dot | Connected |
| Yellow spinner | Connecting / reconnecting |
| Red dot | Disconnected / error |

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

## Themes & Fonts

35 built-in terminal color themes (Dracula, Solarized, Gruvbox, Nord, One Dark, and more) plus 7 monospace fonts including Nerd Font support. Configure in **Settings → Terminal**.

<!-- SCREENSHOT: Theme picker showing the grid of color previews -->

## Network Stats Overlay

Click the **signal bars** icon in the session toolbar to show a real-time traffic widget for the active session.

## Local Terminal

The sidebar also has a **Local Terminal** section that opens a native shell (zsh/bash/PowerShell) alongside SSH sessions.

## Related Pages

- [Recording](User-Guide-Recording) — record the current session to an Asciinema file
- [Settings](User-Guide-Settings) — customize hotkeys and themes
