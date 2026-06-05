# Settings

Open **Settings** from the sidebar (gear icon).

<!-- SCREENSHOT: Settings screen open on the Terminal tab showing theme picker and font selector -->

## Terminal

| Setting | Description |
|---|---|
| **Color theme** | 44 built-in themes; visual picker grid |
| **Font** | 7 bundled fonts (DejaVu, Meslo LGS, Inconsolata, Source Code Pro, Ubuntu Mono, Roboto Mono, MesloLGS NF) |
| **Font size** | Adjust terminal font size |

These three controls are also available without leaving the terminal: the **tune icon** in the terminal toolbar opens a right-side appearance panel with the same settings (changes apply live to all terminals).

## Connection

| Setting | Default | Description |
|---|---|---|
| **Keep-alive interval** | 10 s | Sends SSH keep-alive packets at this interval. Options: 10 s, 30 s, 60 s, 5 min, Disabled |
| **Auto-reconnect attempts** | Unlimited (0) | Number of reconnect attempts on disconnect. `0` = unlimited with linear back-off countdown |

### Auto-reconnect behavior

When the SSH connection drops, YourSSH automatically attempts to reconnect. With **Unlimited** selected, the countdown timer in the tab shows the back-off delay (increases linearly). To disable auto-reconnect, set the value to `1` or a specific number.

## Hotkeys

All keyboard shortcuts are customizable. Click any shortcut row and press the new key combination. Changes take effect immediately.

| Action | Default |
|---|---|
| New session | Cmd/Ctrl+N |
| Close session | Cmd/Ctrl+W |
| Next session | Cmd/Ctrl+] |
| Previous session | Cmd/Ctrl+[ |
| Toggle input bar | Cmd/Ctrl+Shift+I |
| Split horizontal | Cmd/Ctrl+Shift+H |
| Split vertical | Cmd/Ctrl+Shift+V |

## AI

Enter API keys for AI providers:

| Provider | Key format |
|---|---|
| Anthropic Claude | `sk-ant-...` |
| OpenAI | `sk-...` |
| Google Gemini | `AIza...` |

Select the default model per provider. Keys are stored in the OS keychain.

## Sync

See [Sync](User-Guide-Sync) for full setup instructions.

## Updates

YourSSH automatically checks GitHub for a newer stable release once per 24 hours on launch, and you can trigger a manual check at any time via **Settings → Updates → Check for updates**.

- When a newer version is found, a **dismissible banner** appears at the top of the app. You can dismiss it for the current version and it will not reappear until the next release.
- The release also lands in the **notification bell** in the top tab bar (one item per version, with an inline **Update** button), so a dismissed banner doesn't mean a missed update. The bell additionally collects sessions that drop unexpectedly — opening the panel marks items read, and you can dismiss them individually or clear all.
- Clicking **Update** (or **Download & install**) downloads the correct build for your OS and architecture and hands it off to your OS installer:
  - **macOS** — removes the `com.apple.quarantine` flag and opens the DMG. Complete the drag-to-Applications step yourself.
  - **Windows** — launches the installer `.exe`. Follow the setup wizard to complete the upgrade.
  - **Linux** — opens the `.deb` or `.tar.gz` with the default desktop file handler.
- Because YourSSH is not code-signed, the final install step is always manual — the app never silently replaces itself.
- If no build matches your platform (e.g. Intel Mac, where only Apple Silicon builds are published), the Releases page opens in your browser instead.

## Plugins

Toggle Dart plugins (DevOps, Web Tools, Snippets) on or off. JS script plugins are managed via the Plugin Manager screen (sidebar → Plugins section).

## Related Pages

- [Terminal](User-Guide-Terminal) — themes and fonts apply to the terminal
- [AI Chat](User-Guide-AI-Chat) — configure API keys here
- [Sync](User-Guide-Sync) — cloud and P2P sync setup
