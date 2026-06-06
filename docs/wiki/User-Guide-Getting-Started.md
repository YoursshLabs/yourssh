# Getting Started

YourSSH is a dark-theme SSH client for macOS, Windows, and Linux. Install it, add a host, and connect in under a minute.

<!-- SCREENSHOT: App home screen showing the host list (empty state or with 1-2 hosts) -->

## Installation

### macOS

1. Download `YourSSH-x.x.x-macOS-arm64.dmg` from the [Releases page](https://github.com/thangnm93/yourssh/releases).
2. Open the `.dmg` and drag **YourSSH** to `/Applications`.
3. **First launch only:** macOS may block the app because it is not yet notarized. Right-click → **Open** → **Open** in the dialog. You only need to do this once.

Alternatively, remove the quarantine flag from Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/YourSSH.app
```

### Windows

1. Download `YourSSH.Setup.x.x.x-Windows-x64.exe` (or `arm64` for Surface/Snapdragon).
2. Run the installer and follow the setup wizard. YourSSH is added to the Start menu.
3. **Windows SmartScreen** may warn on first run. Click **More info → Run anyway**.

Prefer no installer? Download `YourSSH-x.x.x-Windows-<arch>-portable.zip`, extract it anywhere, and run `yourssh.exe`.

### Linux (Debian / Ubuntu)

```bash
# x86_64
sudo dpkg -i yourssh_x.x.x_amd64.deb

# ARM64 (Raspberry Pi 4/5, Apple Silicon Linux)
sudo dpkg -i yourssh_x.x.x_arm64.deb
```

> Requires Ubuntu 22.04+ / Debian 12+ (glibc ≥ 2.35).

Requires GTK3 (pre-installed on Ubuntu 20.04+, Debian 11+). After install, run `yourssh` or launch from the application menu.

## Your First Connection

1. Click **+** (or press **Cmd/Ctrl+N**) to add a new host.
2. Fill in **Hostname / IP**, **Port** (default 22), and **Username**.
3. Choose an **Auth method**: password, private key, certificate, or SSH agent.
4. Click **Save**, then click the host card to connect.

<!-- SCREENSHOT: Add host dialog filled in with example values -->

## What's Next

- [SSH Connections](User-Guide-SSH-Connections) — organize hosts with groups and tags
- [Terminal](User-Guide-Terminal) — learn the keyboard shortcuts
- [Settings](User-Guide-Settings) — set up auto-reconnect and keep-alive
