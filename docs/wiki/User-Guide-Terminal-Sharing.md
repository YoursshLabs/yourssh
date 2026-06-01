# Terminal Sharing

YourSSH lets you share a live SSH session with teammates in real time. The host streams terminal output via Supabase Realtime; guests join with a session code and can watch or type alongside you.

## Requirements

- Both host and guest must have the app open
- A Supabase project configured in **Settings → Sync** (the same project used for host sync)

## Sharing a Session (Host)

1. Open an active SSH session tab
2. Click the **Share** button in the terminal toolbar (or press **Cmd/Ctrl+K** and search "Share Session")
3. A dialog shows your **session code** — copy or share it with your teammate
4. While the session is shared, a banner in the toolbar indicates sharing is active
5. Click **Stop Sharing** to end the session

## Joining a Session (Guest)

1. Press **Cmd/Ctrl+K** to open the Command Palette
2. Search for **Join Shared Session**
3. Enter the session code provided by the host
4. A new tab opens in **watch mode** — a banner at the top confirms you are watching a shared session

## Watch Mode

Guests join in watch mode by default. The watch banner shows the host's username and the session code.

- Guest keystrokes are forwarded to the host terminal
- The guest tab mirrors the host's terminal output in real time
- Closing the tab disconnects from the shared session without affecting the host

## Limitations

- Sharing requires an active Supabase Realtime connection
- Session codes are single-use per share session
- If the host disconnects, the guest session ends automatically

## Related Pages

- [Terminal](User-Guide-Terminal) — split view, broadcast, search, hotkeys
- [Sync](User-Guide-Sync) — configure Supabase for sync and sharing
