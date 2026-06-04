# In-App RDP Client (IronRDP) — Design

GitHub issue: [#44](https://github.com/YoursshLabs/yourssh/issues/44)

## Problem

Sysadmins managing mixed fleets want one app for both SSH and remote desktop.
Today yourssh covers SSH/SFTP only; reaching a Windows server (or a Linux
desktop via xrdp) requires an external RDP client, and servers that don't
expose port 3389 force users to set up tunnels by hand.

Goal: control a remote desktop (screen + mouse/keyboard + clipboard) inside
the app, connecting directly or through an SSH tunnel. Audio, drive/printer
redirection, and RemoteApp are explicitly **not** v1 priorities.

## Constraints

- Cross-platform parity: macOS (arm64), Windows (x64), Linux (x64) — same
  feature set, no per-OS rendering code in v1.
- App size: keep the footprint increase small (~3–8 MB). FreeRDP (+20–40 MB,
  bundled C dylibs + codecs) was evaluated and rejected.
- Server support: Windows RDP (NLA/CredSSP) and xrdp on Linux (TLS,
  RemoteFX). No H.264/EGFX in v1 — IronRDP decodes raw/RLE/RDP6/RemoteFX.
- First Rust component in the repo: the old `core/` crate was removed, so
  toolchain + CI integration is greenfield.

## Approach: IronRDP + flutter_rust_bridge v2, pure-Dart rendering

Chosen over (a) hand-written C-ABI FFI à la `quickjs_ffi.dart` — async frame
delivery over raw FFI is the riskiest part and FRB generates exactly that
glue — and (b) FreeRDP FFI — oversized for "control only".

### 1. New package `packages/yourssh_rdp`

```
packages/yourssh_rdp/
├── pubspec.yaml          # Dart package; flutter_rust_bridge runtime dep
├── lib/                  # Dart API: RdpClient, RdpEvent, input senders
│   └── src/generated/    # FRB codegen output (checked in)
├── rust/
│   ├── Cargo.toml        # ironrdp (client/connector/session/graphics/cliprdr), frb
│   └── src/api.rs        # FRB-exposed API
├── assets/native/        # built cdylib per platform (same pattern as QuickJS)
│   ├── macos/libyourssh_rdp.dylib    # aarch64
│   ├── linux/libyourssh_rdp.so      # x64
│   └── windows/yourssh_rdp.dll      # x64
└── build.sh / build.ps1  # cargo build --release + copy into assets/native/
```

**Rust side.** One tokio runtime hosts all IronRDP session event loops. Per
session: connect (TCP → TLS → CredSSP when NLA), run the active session
stage, decode bitmap updates (raw, RLE, RDP 6.0, RemoteFX) into a full RGBA
framebuffer held in Rust, and emit only **dirty regions** to Dart. Panics are
caught at the FRB boundary and surfaced as `RdpEvent.error` — never an app
crash.

**API surface (FRB):**

- `connect(RdpConfig) -> Stream<RdpEvent>` — config: `targetHost`, `targetPort`
  (the loopback proxy when tunneled), `username`, `password`, `domain?`,
  `width`, `height`, `security` (`auto` | `nla` | `tls`).
- `RdpEvent` = `connected(certInfo)` | `frameUpdate(x, y, w, h, rgbaBytes)`
  | `clipboardText(text)` | `disconnected(reason)` | `error(message)`.
  `certInfo` carries the server certificate SHA-256 fingerprint + subject.
- `sendMouse(sessionId, x, y, button, action)`, `sendWheel(sessionId, delta)`,
  `sendKey(sessionId, scancode, isDown)`, `sendClipboardText(sessionId, text)`,
  `disconnect(sessionId)`.

### 2. Connection + tunnel data flow

```
HostProvider (Host.protocol == rdp) → SessionProvider.connect(host)
  ├── host.jumpHostId == null → IronRDP connects host:port directly
  └── host.jumpHostId != null →
        SshService: connect jump host → forwardLocal(host.host, host.port)
        → Dart loopback proxy: ServerSocket(127.0.0.1, port 0)
          pipes accepted socket ↔ SSHSocket (one-shot, closes with session)
        → IronRDP connects 127.0.0.1:<proxyPort>
```

The loopback proxy keeps the Rust side identical for direct and tunneled
connections and reuses the existing dartssh2 `forwardLocal` jump-host
pattern. The proxy binds loopback only, random port, accepts exactly one
connection, and dies with the session.

**Resolution:** fixed at connect time = workspace area size × devicePixelRatio,
clamped to a minimum of 800×600 and rounded down to a multiple of 4. Window
resizes scale the rendered image
(aspect-fit); dynamic resize (DisplayControl) is out of scope for v1.

### 3. Rendering and input

- `frameUpdate` events patch a Dart-side `ui.Image` via `ui.ImmutableBuffer`;
  a `CustomPaint` draws it scale-to-fit. No Texture/Metal/D3D code in v1 —
  admin screens are mostly static so dirty-region updates keep CPU acceptable.
  The event-stream architecture allows swapping in a `Texture`-based renderer
  later without API changes.
- Mouse: `Listener` (down/move/up/scroll); coordinates divided by the render
  scale back into session-resolution space.
- Keyboard: `Focus` + `KeyEvent`; a static `PhysicalKeyboardKey` (USB HID) →
  RDP scancode (set 1) table, pure Dart, unit-tested. Extended keys (arrows,
  Home/End, right Ctrl/Alt, Win) carry the E0 flag.
- Clipboard (text-only v1): remote copy → `clipboardText` event →
  `Clipboard.setData`; local → remote pushed when the RDP view gains focus
  and via an explicit toolbar button.

### 4. Host model changes

- `HostProtocol` enum: `ssh` | `rdp`; `Host.protocol` defaults to `ssh`.
  JSON is additive — existing hosts without the field parse as `ssh`, and
  the Supabase sync payload carries it transparently.
- RDP hosts reuse: `host`, `port` (default 3389), `username`, password in
  secure storage under `pw_<hostId>`, `jumpHostId` (SSH host to tunnel
  through), `group`, `tags`.
- New optional fields: `domain` (NLA domain), `rdpSecurity`
  (`auto` | `nla` | `tls`, default `auto`).
- Host form: protocol selector first; for RDP only the relevant fields show.
  Hidden/ignored for RDP: authType key/cert/agent, shell integration, SFTP
  mode, auto-record. `AuthType` stays `password` for RDP hosts.

### 5. Session/tab integration

The top tab bar must host RDP sessions, but `TerminalSession` requires an
xterm `Terminal`. Split the interface (the doc comment in
`terminal_session.dart` already describes this seam):

- `AppSession` — tab behavior only: `id`, `tabLabel`, `customLabel`,
  `colorTag`, `isPinned`.
- `TerminalSession extends AppSession` — adds `terminal`, `isLocal`,
  `recordingFolder`, `recordingTitle`. `SshSession` / `LocalSession`
  unchanged otherwise.
- `RdpSession implements AppSession` — holds the `RdpEvent` stream
  subscription, `RdpSessionStatus` (connecting / connected / disconnected /
  error), the framebuffer image, and the last error message.
- `SessionProvider._sessions` becomes `List<AppSession>`; `connect(host)`
  branches on `host.protocol`; `sshSessions` / `activeSshSession` keep their
  behavior. Tab-only consumers (tab bar, rename, pin, color, next/prev
  hotkeys) use `AppSession`; terminal consumers (SplitTerminalView,
  recording, snippets `sendInput`, input bar) guard `is TerminalSession`.
- Explicitly disabled for RDP tabs: session recording (asciicast is a
  terminal format), split view, input bar, snippets panel.

### 6. UI: `RdpWorkspace`

- `MainScreen._buildForeground` branches:
  `active is RdpSession ? RdpWorkspace : SplitTerminalView`.
- `RdpWorkspace` = rendered screen (CustomPaint) + input capture + a slim
  toolbar: **Ctrl+Alt+Del** button (cannot be typed locally), push-clipboard
  button, disconnect/reconnect. Status overlay while connecting; error
  overlay with message + Retry on failure.
- Hosts screen shows an "RDP" badge on RDP host cards; connect opens a tab
  exactly like SSH.
- App hotkeys (next/prev tab, command palette…) keep working via
  `HotkeyService` (in-app scope); all other keys go to the remote session.

### 7. Server certificate verification (TOFU)

RDP servers commonly present self-signed certificates. Mirror the SSH known
-hosts flow: on `connected(certInfo)`, if no pin exists for the host, show a
fingerprint confirmation dialog (reuse the `KnownHostsProvider`
`pendingChallenge` pattern); store the SHA-256 pin per host. A changed
fingerprint raises a red warning dialog. Pinned RDP certs appear in the
Known Hosts screen with an RDP badge.

## Error handling

- NLA auth failure → status `error` with a clear message; Retry re-prompts
  for the password.
- Connection drop → status `disconnected` + Reconnect button. **No
  auto-reconnect in v1** (unlike SSH): RDP reconnect requires full
  re-authentication; revisit later.
- SSH tunnel collapse → proxy closes → IronRDP reports disconnect; message
  states "SSH tunnel closed".
- Rust panics → `RdpEvent.error` via the FRB catch boundary.

## Testing

- **Unit (pure Dart):** scancode mapping table; mouse coordinate scaling;
  loopback proxy piping (in-memory socket pair); `Host` JSON round-trip with
  `protocol` / `domain` / `rdpSecurity`; `SessionProvider` filtering with
  mixed `AppSession` types.
- **Rust:** `cargo test` for config building and framebuffer dirty-region
  patching.
- **Manual verification matrix:** Windows 11 VM (NLA) and an xrdp container
  (TLS) from each desktop platform; checklist lives in the implementation
  plan.

## Build / CI

- `packages/yourssh_rdp/build.sh|ps1` runs `cargo build --release` and copies
  the cdylib into `assets/native/<os>/` (same bundling pattern as the QuickJS
  `libqjsbridge` library).
- Release workflow gains a Rust toolchain setup + crate build step before
  `flutter build` on each OS runner. Targets match the existing release
  matrix: `aarch64-apple-darwin`, `x86_64-pc-windows-msvc`,
  `aarch64-pc-windows-msvc`, `x86_64-unknown-linux-gnu`,
  `aarch64-unknown-linux-gnu` (the crate builds with the runner's native
  toolchain on each matrix job).
- FRB codegen output is checked in; regeneration is a dev-time step, not a
  CI dependency.

## Out of scope (v1)

- Audio output (`ironrdp-rdpsnd` exists; "nice to have" later), microphone
- Drive / printer / smartcard redirection, RemoteApp, RD Gateway
- H.264/EGFX codecs, multi-monitor, dynamic resize (DisplayControl)
- Auto-reconnect, session recording for RDP tabs
- Image/file clipboard formats (text only in v1)
