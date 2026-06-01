# Settings

Open **Settings** from the sidebar (gear icon).

<!-- SCREENSHOT: Settings screen open on the Terminal tab showing theme picker and font selector -->

## Terminal

| Setting | Description |
|---|---|
| **Color theme** | 35 built-in themes; visual picker grid |
| **Font** | 7 bundled fonts (DejaVu, Meslo LGS, Inconsolata, Source Code Pro, Ubuntu Mono, Roboto Mono, MesloLGS NF) |
| **Font size** | Adjust terminal font size |

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

## Plugins

Toggle Dart plugins (DevOps, Web Tools, Snippets) on or off. JS script plugins are managed via the Plugin Manager screen (sidebar → Plugins section).

## Related Pages

- [Terminal](User-Guide-Terminal) — themes and fonts apply to the terminal
- [AI Chat](User-Guide-AI-Chat) — configure API keys here
- [Sync](User-Guide-Sync) — cloud and P2P sync setup
