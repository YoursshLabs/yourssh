---
name: yourssh-screenshots
description: Use when the user wants to update, refresh, or add screenshots for the YourSSH app — e.g. "chụp screenshot", "cập nhật screenshots", "refresh screenshots", "add screenshots for new feature", or after a UI change.
---

# yourssh-screenshots

Default path: the **isolated docs journey** (`tool/docs_journey.sh`). It drives the real macOS app through every feature against demo Docker containers and captures ~209 PNGs (render tree, so no Screen Recording permission). The app runs with a temp `HOME`, in-memory prefs, fake secure storage and temp path_provider dirs, so the owner's real data is never touched; the script checks the real prefs plist mtime and `~/.yourssh` hash before/after (`ISOLATION OK`).

## Default workflow

```bash
tool/docs_journey.sh setup      # client key + image + network + 5 demo containers (idempotent)
tool/docs_journey.sh all        # build the integration app, then run desktop + mobile launches (~30 min, needs a GUI session)
# review screenshots/docs/INDEX.md (one line per shot) and screenshots/docs/BUGS.md (anomalies found)
tool/docs_journey.sh teardown   # remove ONLY the containers/network/image that setup created
```

- Output: `screenshots/docs/<NN-section>/<NN-step>.png` + `INDEX.md` + `BUGS.md` (untracked; `DOCS_OUT` overrides).
- Subcommands: `setup | build | run | all | teardown`. `run` skips the build; `build` only builds.
- Re-run a subset: `SECTIONS="07,08" MODES=desktop tool/docs_journey.sh run` (section numbers are the `NN-` prefixes of `app/integration_test/docs/sNN_*.dart`; `MODES` is `desktop`, `mobile`, or both). Use `run` after one full `build`; rebuild (`build`) after any Dart change.
- Demo servers (loopback only; the harness expects these defaults): `yourssh-docs-ssh` 2222 (hostname `yourssh-demo`, user `demo`/`demo1234` + key auth), `yourssh-docs-bastion` 2223, `yourssh-docs-db` (network only, `db-internal:22`), `yourssh-docs-rdp` 3389 (`demo`/`demo12345`), `yourssh-docs-vnc` 5900 (`demo12345`). Image files: `tool/docs_journey/Dockerfile`.
- The generated ed25519 client key lives in `~/.local/state/yourssh-docs-journey` (`DOCS_KEY_DIR` overrides), never in the repo. Never commit keys.
- `DOCS_PREFIX` and `SSH_PORT/BASTION_PORT/RDP_PORT/VNC_PORT` let `setup`/`teardown` run side by side with another set of containers (only for testing setup; the journey itself needs the default ports).
- Timestamps/progress go to `$TMPDIR/yourssh-docs-run.*/run-*.log`; a hung mobile launch is retried once automatically.

## Refreshing the README images from a run

README images are copies of journey shots, resized: `sips -Z 1440 <src> --out <README path>` (writes a copy; never edit the source). Mapping (README path <- journey shot; confirm each against `screenshots/docs/INDEX.md` because shot numbers shift when sections change):

| README path (under `screenshots/`) | Journey shot |
|---|---|
| `01-terminal-ssh/01-hosts-dashboard.png` | `06-dashboard/01-grid.png` |
| `01-terminal-ssh/02-new-host-panel-ssh.png` | `02-add-host/01-new-host-panel.png` |
| `02-ssh-terminal-ai.png` | `16-ai-chat/04-chat-open.png` |
| `01-terminal-ssh/04-dashboard-with-rdp-badge.png` | `12-rdp/04-dashboard-rdp-badge.png` |
| `02-sftp/01-sftp-browser.png` | `07-sftp/03-dual-panel.png` |
| `03-port-forwarding/01-port-forward-rules.png` | `08-port-forwarding/05-rule-list.png` |
| `04-credentials-security/01-keychain.png` | `04-keychain/05-key-list.png` |
| `04-credentials-security/02-known-hosts.png` | `09-known-hosts/01-list.png` |
| `05-settings/01-settings-general.png` | `14-settings/01-settings-top.png` |
| `05-settings/02-settings-terminal.png` | `14-settings/03-terminal.png` |
| `05-settings/03-settings-sync.png` | `14-settings/09-sync.png` |
| `10-settings-sync-qr-code.png` | `14-settings/17-sync-qr-dialog.png` (see gaps) |
| `05-settings/04-settings-updates.png` | `14-settings/12-updates.png` |
| `05-settings/05-terminal-theme-picker.png` | `03-first-connect/19-theme-picker.png` |
| `06-plugins/01-plugins.png` | `15-plugins/01-manager.png` |
| `05-devops-hub-network-tools.png` | `17-devops/04-network-tools.png` |
| `08-web-tools-http-client.png` | `18-web-tools/03-get-response.png` |
| `09-snippets.png` | `15-plugins/03-snippets-screen.png` |
| `02-host-editor-rdp-form.png` | `12-rdp/03-editor-filled.png` |
| `03-tofu-certificate-dialog.png` | `12-rdp/05-cert-trust-dialog.png` |
| `04-rdp-workspace-connected.png` | `12-rdp/06-session-connected.png` |
| `05-fullscreen-with-pill.png` | `12-rdp/08-fullscreen-pill.png` |
| `06-fullscreen-clean.png` | `12-rdp/09-fullscreen-clean.png` |
| `07-fullscreen-hover-reveal.png` | `12-rdp/10-fullscreen-hover-pill.png` |
| `08-back-to-windowed.png` | `12-rdp/11-back-windowed.png` |
| `10-audit-recording/01-audit-log.png` | `11-audit-log/01-rows.png` |
| `10-audit-recording/02-recording-library.png` | `10-recordings/02-library.png` |
| `11-recording.png` | `10-recordings/03b-player-playing.png` |
| `12-multiple-player.png` | no journey shot (needs two clients; keep the existing image) |

After copying, check every README path exists:
```bash
grep -o 'screenshots/[^"]*\.png' README.md | while read p; do [ -f "$p" ] && echo "OK: $p" || echo "MISSING: $p"; done
```
New feature screens: add the step to the matching `app/integration_test/docs/sNN_*.dart`, rebuild, re-run that section, then add the README `<td>` (2-column `<table>` rows per feature group).

## Known gaps

- WebViews are blank in render-tree capture (embedded browser, Monaco code editor, web tools browser): only the surrounding chrome is real.
- Mobile pair / LAN-sync QR dialogs show the machine's real LAN IP. Before publishing, re-encode the QR with a placeholder address or crop it out; otherwise note it in the PR.
- Terminal sharing (multiplayer) and anything needing a second client are not covered.
- Real AI providers are never called (no key); RDP/VNC need the containers running and a window that stays awake (the script runs `caffeinate`).

## Do not use the legacy path by default

`app/integration_test/feature_screenshots_test.dart` and `rdp_screenshots_test.dart` back up and seed the user's REAL SharedPreferences (hosts, known hosts, port forwards) and restore them afterwards. A crash mid-run can leave demo data in the real profile. Use them only if the user explicitly asks; the journey above replaces them.

```bash
# legacy, only on request
cd app && flutter test integration_test/feature_screenshots_test.dart -d macos
cd app && flutter test integration_test/rdp_screenshots_test.dart -d macos   # needs the RDP container
```

## Mobile (Android) capture

`integration_test/mobile_screenshots_test.dart` differs from the desktop tests in
three ways that matter:

1. **It must run under `flutter drive`, not `flutter test`.** `flutter test`
   uninstalls the app when the run ends, deleting anything the test wrote inside
   the app's own directories. Frames therefore travel back over the driver
   connection and `test_driver/integration_test.dart` writes them on the host —
   screenshot names are paths relative to the repo root.
2. **The Android surface has to be converted first.** `await
   _binding.convertFlutterSurfaceToImage()` right after `app.main()`; without it
   `takeScreenshot` cannot read a SurfaceView.
3. **The terminal / SFTP shots need a real SSH server.** A `linuxserver/openssh-server`
   container on port 2222 is reachable from the emulator as `10.0.2.2:2222`; the
   test seeds that host plus a password in secure storage. Without the container
   those shots fall back to the failure state and the run still passes.

Emulator gotchas: a full debug APK is ~185 MB, so `INSTALL_FAILED_INSUFFICIENT_STORAGE`
means the AVD's `/data` is full — reboot the emulator to reclaim cache. Biometric
app-lock is force-disabled in setup because an emulator has no enrolled fingerprint.

## Adding a screen (legacy test only)

1. Open `app/integration_test/feature_screenshots_test.dart`
2. Navigate to the screen with `_navTo(tester, 'Label')` or tap the relevant widget
3. Call `await _snap(tester, '$_gN/filename.png')` where `_gN` is the group constant
4. Add a new group constant if needed: `const _gN = '$_outDir/NN-group-name';`
5. Run the test to verify
6. Add the `<img src="screenshots/NN-group-name/filename.png"/>` entry to README under the correct section

## Legacy test implementation details

- **Storage keys**: `yourssh.hosts`, `yourssh.known_hosts`, `yourssh.port_forwards` (not bare `hosts`)
- **Nav tap**: `find.text('Port Forwarding')`, `find.text('Known Hosts')`, etc. — matches sidebar label text
- **`_snap` helper**: pumps 200ms before capture to let animations settle
- **Debounce update check**: set `last_update_check` to `DateTime.now().millisecondsSinceEpoch` to prevent update banner polluting shots
- **PortForward JSON**: stored as a flat list, `type` is the enum name (`local`, `remote`, `dynamic`)

## Common mistakes (legacy test)

| Problem | Fix |
|---|---|
| `screencapture` fails | Use integration test — no Screen Recording permission needed |
| Wrong prefs key | Use `yourssh.hosts` not `hosts`; `yourssh.port_forwards` not `port_forwards` |
| Screenshot is blank/clipped | Increase pump delay in `_snap` or add explicit `_waitFor` before snap |
| Update banner appears | Set `last_update_check` to now in test setup |
| User data not restored | Wrap all test steps in `try { ... } finally { restore }` |
