---
name: yourssh-screenshots
description: Use when the user wants to update, refresh, or add screenshots for the YourSSH app — e.g. "chụp screenshot", "cập nhật screenshots", "refresh screenshots", "add screenshots for new feature", or after a UI change.
---

# yourssh-screenshots

Captures screenshots of every YourSSH feature screen using Flutter integration tests (render tree — no macOS Screen Recording permission needed). Saves PNGs to `screenshots/<group>/`, then updates README.

## Quick Reference

```bash
# Capture all general feature screenshots
cd app && flutter test integration_test/feature_screenshots_test.dart -d macos

# Capture RDP-specific screenshots (requires Docker)
cd app && flutter test integration_test/rdp_screenshots_test.dart -d macos
```

## Folder Structure

```
screenshots/
  01-terminal-ssh/      # Dashboard, host editor, SSH terminal
  02-sftp/              # Dual-panel SFTP
  03-port-forwarding/   # Port forward rules
  04-credentials-security/  # Keychain, known hosts
  05-settings/          # Settings sections
  06-plugins/           # Plugin manager
  07-rdp/               # RDP workspace (populated by rdp test)
  08-devops/            # DevOps hub
  10-audit-recording/   # Audit log, recording library
  *.png                 # Legacy flat screenshots (keep for features needing live connections)
```

## How It Works

`integration_test/feature_screenshots_test.dart`:
1. Backs up user's real host data
2. Seeds demo hosts + port forward rules into SharedPreferences
3. Launches `app.main()` via Flutter integration test harness
4. Navigates each sidebar section by tapping the nav label text
5. Captures frames via `RendererBinding.instance.renderViews.first`
6. Restores user data in `finally`

`integration_test/rdp_screenshots_test.dart`:
- Requires `docker run -d --name yourssh-rdp-demo -p 3389:3389 scottyhardy/docker-remote-desktop:latest`
- Connects to a real xrdp container; captures fullscreen + TOFU dialog screenshots

## Adding a New Screen

1. Open `app/integration_test/feature_screenshots_test.dart`
2. Navigate to the screen with `_navTo(tester, 'Label')` or tap the relevant widget
3. Call `await _snap(tester, '$_gN/filename.png')` where `_gN` is the group constant
4. Add a new group constant if needed: `const _gN = '$_outDir/NN-group-name';`
5. Run the test to verify
6. Add the `<img src="screenshots/NN-group-name/filename.png"/>` entry to README under the correct section

## Updating README

The `## Screenshots` section in `README.md` is organized by feature groups matching the folder structure. Each group uses an HTML `<table>` with 2-column rows:

```html
### Group Name
<table>
  <tr>
    <td align="center"><b>Screen Title</b><br/><img src="screenshots/NN-group/filename.png"/></td>
    <td align="center"><b>Screen Title</b><br/><img src="screenshots/NN-group/filename.png"/></td>
  </tr>
</table>
```

After updating, verify all paths exist:
```bash
grep -o 'screenshots/[^"]*\.png' README.md | while read p; do
  [ -f "$p" ] && echo "OK: $p" || echo "MISSING: $p"
done
```

## Key Implementation Details

- **Storage keys**: `yourssh.hosts`, `yourssh.known_hosts`, `yourssh.port_forwards` (not bare `hosts`)
- **Nav tap**: `find.text('Port Forwarding')`, `find.text('Known Hosts')`, etc. — matches sidebar label text
- **`_snap` helper**: pumps 200ms before capture to let animations settle
- **Debounce update check**: set `last_update_check` to `DateTime.now().millisecondsSinceEpoch` to prevent update banner polluting shots
- **PortForward JSON**: stored as a flat list, `type` is the enum name (`local`, `remote`, `dynamic`)

## Common Mistakes

| Problem | Fix |
|---|---|
| `screencapture` fails | Use integration test — no Screen Recording permission needed |
| Wrong prefs key | Use `yourssh.hosts` not `hosts`; `yourssh.port_forwards` not `port_forwards` |
| Screenshot is blank/clipped | Increase pump delay in `_snap` or add explicit `_waitFor` before snap |
| Update banner appears | Set `last_update_check` to now in test setup |
| User data not restored | Wrap all test steps in `try { ... } finally { restore }` |
