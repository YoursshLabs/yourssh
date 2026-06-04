# In-App RDP Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Control remote desktops (screen + mouse/keyboard + clipboard) inside yourssh, connecting directly or through an SSH tunnel, per `docs/superpowers/specs/2026-06-04-in-app-rdp-client-design.md` (issue #44).

**Architecture:** New `packages/yourssh_rdp` package wraps IronRDP (Rust) behind flutter_rust_bridge v2; frames stream to Dart as dirty-region RGBA updates rendered by a `CustomPaint`. App side adds `Host.protocol`, splits `TerminalSession` into `AppSession` + `TerminalSession`, and adds `RdpSession` + `RdpWorkspace`. SSH tunneling reuses dartssh2 `forwardLocal` behind a one-shot loopback proxy.

**Tech Stack:** Rust (ironrdp, tokio, flutter_rust_bridge v2), Dart/Flutter, dartssh2 (local fork).

**Reference reading for the executor (do this before Task 3):**
- Clone https://github.com/Devolutions/IronRDP and read `crates/ironrdp-client/src/rdp.rs` (connection + active session loop, `build_config`) and `crates/ironrdp/examples/screenshot.rs` (minimal blocking client). The Rust code in Tasks 4–8 is modeled on these; the ironrdp API drifts between releases, so when a name differs, the pinned version's example is the source of truth.
- flutter_rust_bridge v2 docs: https://cjycode.com/flutter_rust_bridge/ (codegen config, `StreamSink`, `RustLib.init` with `ExternalLibrary`).
- Known FRB limitation (drives the design): a function taking a `StreamSink<T>` parameter is generated as a Dart function returning `Stream<T>`; **its Rust return value is discarded** (FRB issue #2233). The session id therefore travels as the first stream event (`RdpEvent::Started`), never as a return value.

---

## Phase 0 — Package scaffolding + FRB pipeline

### Task 1: Scaffold `packages/yourssh_rdp`

**Files:**
- Create: `packages/yourssh_rdp/pubspec.yaml`
- Create: `packages/yourssh_rdp/lib/yourssh_rdp.dart`
- Create: `packages/yourssh_rdp/rust/Cargo.toml`
- Create: `packages/yourssh_rdp/rust/src/lib.rs`
- Create: `packages/yourssh_rdp/rust/src/api.rs`
- Modify: `app/pubspec.yaml` (dependency)

- [ ] **Step 1: Create the Dart package skeleton**

`packages/yourssh_rdp/pubspec.yaml`:

```yaml
name: yourssh_rdp
description: In-app RDP client for yourssh (IronRDP via flutter_rust_bridge).
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.12.0
  flutter: ">=3.24.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_rust_bridge: ^2.7.0
  ffi: ^2.1.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
```

`packages/yourssh_rdp/lib/yourssh_rdp.dart`:

```dart
library yourssh_rdp;

export 'src/rdp_client.dart';
```

(`src/rdp_client.dart` is created in Task 9; for now create an empty `lib/src/` directory with a `.gitkeep`.)

- [ ] **Step 2: Create the Rust crate**

`packages/yourssh_rdp/rust/Cargo.toml`. **Version pinning rule:** all `ironrdp-*` crates ship together from one workspace — take the exact, mutually compatible versions from the IronRDP repo's latest release tag (`Cargo.toml` of `crates/ironrdp-client` lists the full set). The numbers below are current as of writing (meta-crate 0.15 line) and exist only so `cargo` has a starting point:

```toml
[package]
name = "yourssh_rdp"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "staticlib"]

[dependencies]
flutter_rust_bridge = "=2.7.0"
ironrdp = { version = "0.15", features = ["connector", "session", "input", "graphics", "cliprdr"] }
ironrdp-tokio = "0.9"
ironrdp-tls = { version = "0.3", features = ["rustls"] }
ironrdp-cliprdr = "0.4"
# NetworkClient impl required by connect_finalize for CredSSP/NLA —
# copy the exact dependency the ironrdp-client example uses
# (sspi with its reqwest network-client feature).
sspi = { version = "0.16", features = ["network_client"] }
tokio = { version = "1", features = ["rt-multi-thread", "net", "sync", "macros", "time"] }
anyhow = "1"
futures = "0.3"
sha2 = "0.10"

[dev-dependencies]
tokio = { version = "1", features = ["test-util"] }
```

`packages/yourssh_rdp/rust/src/lib.rs`:

```rust
pub mod api;
mod frb_generated; /* created by codegen in Task 2 */
```

`packages/yourssh_rdp/rust/src/api.rs` (placeholder API proven in Task 2):

```rust
pub fn rdp_lib_version() -> String {
    format!("yourssh_rdp {}", env!("CARGO_PKG_VERSION"))
}
```

- [ ] **Step 3: Verify the crate compiles (without frb_generated yet, comment that line out)**

Run: `cd packages/yourssh_rdp/rust && cargo check`
Expected: `Finished` with no errors. If version numbers don't co-resolve, fix them from the IronRDP release workspace before proceeding — do not mix versions across ironrdp crates.

- [ ] **Step 4: Wire the package into the app**

In `app/pubspec.yaml` add under `dependencies`:

```yaml
  yourssh_rdp:
    path: ../packages/yourssh_rdp
```

Run: `cd app && flutter pub get`
Expected: resolves without error.

- [ ] **Step 5: Commit**

```bash
git add packages/yourssh_rdp app/pubspec.yaml app/pubspec.lock
git commit -m "feat(rdp): scaffold yourssh_rdp package with ironrdp crate (#44)"
```

### Task 2: FRB codegen pipeline + native library loader + build scripts

**Files:**
- Create: `packages/yourssh_rdp/flutter_rust_bridge.yaml`
- Create: `packages/yourssh_rdp/lib/src/native_loader.dart`
- Create: `packages/yourssh_rdp/build.sh`, `packages/yourssh_rdp/build.ps1`
- Create: `packages/yourssh_rdp/test/frb_roundtrip_test.dart`
- Generated: `packages/yourssh_rdp/lib/src/generated/**`, `rust/src/frb_generated.rs`

- [ ] **Step 1: Add codegen config**

`packages/yourssh_rdp/flutter_rust_bridge.yaml`:

```yaml
rust_input: crate::api
rust_root: rust
dart_output: lib/src/generated
```

- [ ] **Step 2: Install codegen and generate**

Run:
```bash
cargo install flutter_rust_bridge_codegen --version 2.7.0 --locked
cd packages/yourssh_rdp && flutter_rust_bridge_codegen generate
```
Expected: `lib/src/generated/` and `rust/src/frb_generated.rs` created. Re-enable the `mod frb_generated;` line in `lib.rs`. Run `cargo check` again — passes. Generated output is **checked in** (CI never runs codegen).

- [ ] **Step 3: Write the native loader**

Candidate order matters: release-bundle locations (relative to the executable) first, then dev locations. `packages/yourssh_rdp/lib/src/native_loader.dart`:

```dart
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

/// Locates the yourssh_rdp dynamic library. Search order: bundled release
/// locations (relative to the running executable), plain name (rpath /
/// system lookup), then repo-relative dev paths.
ExternalLibrary loadYoursshRdpLibrary() {
  Object? lastError;
  for (final path in _candidates()) {
    try {
      return ExternalLibrary.open(path);
    } catch (e) {
      lastError = e;
    }
  }
  throw StateError('yourssh_rdp native library not found: $lastError');
}

List<String> _candidates() {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  if (Platform.isMacOS) {
    return [
      // Release: YourSSH.app/Contents/Frameworks/ (bundled by CI, Task 19)
      '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks/libyourssh_rdp.dylib',
      'libyourssh_rdp.dylib',
      // Dev: flutter run from app/ or repo root
      '${Directory.current.path}/packages/yourssh_rdp/assets/native/macos/libyourssh_rdp.dylib',
      '${Directory.current.path}/../packages/yourssh_rdp/assets/native/macos/libyourssh_rdp.dylib',
    ];
  }
  if (Platform.isLinux) {
    return [
      '$exeDir/lib/libyourssh_rdp.so',
      'libyourssh_rdp.so',
      '${Directory.current.path}/packages/yourssh_rdp/assets/native/linux/libyourssh_rdp.so',
      '${Directory.current.path}/../packages/yourssh_rdp/assets/native/linux/libyourssh_rdp.so',
    ];
  }
  return [
    '$exeDir\\yourssh_rdp.dll',
    'yourssh_rdp.dll',
    '${Directory.current.path}\\packages\\yourssh_rdp\\assets\\native\\windows\\yourssh_rdp.dll',
    '${Directory.current.path}\\..\\packages\\yourssh_rdp\\assets\\native\\windows\\yourssh_rdp.dll',
  ];
}
```

- [ ] **Step 4: Write build scripts**

The scripts build for the **host's native architecture** (no `--target` flag) — CI runners are native per matrix job (x64 and arm64), so the produced binary always matches the bundle being built.

`packages/yourssh_rdp/build.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/rust"
cargo build --release
cd ..
case "$(uname -s)" in
  Darwin)
    mkdir -p assets/native/macos
    cp rust/target/release/libyourssh_rdp.dylib assets/native/macos/ ;;
  Linux)
    mkdir -p assets/native/linux
    cp rust/target/release/libyourssh_rdp.so assets/native/linux/ ;;
esac
echo "yourssh_rdp native library built"
```

`packages/yourssh_rdp/build.ps1`:

```powershell
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "rust")
cargo build --release
Set-Location $PSScriptRoot
New-Item -ItemType Directory -Force -Path "assets/native/windows" | Out-Null
Copy-Item "rust/target/release/yourssh_rdp.dll" "assets/native/windows/"
Write-Host "yourssh_rdp native library built"
```

Run: `chmod +x packages/yourssh_rdp/build.sh && packages/yourssh_rdp/build.sh`
Expected: dylib copied into `assets/native/macos/`.

- [ ] **Step 5: Write the failing roundtrip test**

`packages/yourssh_rdp/test/frb_roundtrip_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_rdp/src/generated/frb_generated.dart';
import 'package:yourssh_rdp/src/generated/api.dart';
import 'package:yourssh_rdp/src/native_loader.dart';

void main() {
  setUpAll(() async {
    await RustLib.init(externalLibrary: loadYoursshRdpLibrary());
  });

  test('rdpLibVersion returns crate version', () async {
    expect(await rdpLibVersion(), startsWith('yourssh_rdp 0.1.0'));
  });
}
```

Run: `cd packages/yourssh_rdp && flutter test`
Expected: PASS (the dylib was built in Step 4). This test requires the built dylib — CI must run `build.sh`/`build.ps1` before it (Task 19).

- [ ] **Step 6: Commit**

```bash
git add packages/yourssh_rdp
git commit -m "feat(rdp): FRB codegen pipeline, native loader, build scripts (#44)"
```

---

## Phase 1 — Rust core

### Task 3: API types + session registry

**Files:**
- Modify: `packages/yourssh_rdp/rust/src/api.rs`
- Create: `packages/yourssh_rdp/rust/src/session.rs`

- [ ] **Step 1: Define the FRB-visible types in `api.rs`**

```rust
#[derive(Clone)]
pub struct RdpConfig {
    pub target_host: String,
    pub target_port: u16,
    pub username: String,
    pub password: String,
    pub domain: Option<String>,
    pub width: u16,
    pub height: u16,
    /// "auto" | "nla" | "tls"
    pub security: String,
}

pub struct RdpCertInfo {
    pub sha256_fingerprint: String, // lowercase hex
    pub subject: String,
}

pub enum RdpEvent {
    /// Always the first event on the stream. Carries the session id used by
    /// every sender function — FRB discards the Rust return value of a
    /// StreamSink-taking function (issue #2233), so the id travels here.
    Started { session_id: u32 },
    Connected { cert: RdpCertInfo },
    FrameUpdate { x: u16, y: u16, width: u16, height: u16, rgba: Vec<u8> },
    ClipboardText { text: String },
    Disconnected { reason: String },
    Error { message: String },
}

pub fn rdp_lib_version() -> String {
    format!("yourssh_rdp {}", env!("CARGO_PKG_VERSION"))
}
```

- [ ] **Step 2: Write the failing registry test in `session.rs`**

```rust
use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Mutex;

use tokio::sync::mpsc::UnboundedSender;

/// Commands Dart can push into a running session loop.
pub enum SessionCmd {
    Mouse { x: u16, y: u16, button: u8, action: u8 },
    Wheel { delta: i16 },
    Key { scancode: u16, extended: bool, down: bool },
    ClipboardText(String),
    Disconnect,
}

static NEXT_ID: AtomicU32 = AtomicU32::new(1);
static SESSIONS: Mutex<Option<HashMap<u32, UnboundedSender<SessionCmd>>>> = Mutex::new(None);

pub mod registry {
    use super::*;

    pub fn insert(tx: UnboundedSender<SessionCmd>) -> u32 {
        let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
        SESSIONS.lock().unwrap().get_or_insert_with(HashMap::new).insert(id, tx);
        id
    }

    pub fn send(id: u32, cmd: SessionCmd) -> bool {
        let guard = SESSIONS.lock().unwrap();
        match guard.as_ref().and_then(|m| m.get(&id)) {
            Some(tx) => tx.send(cmd).is_ok(),
            None => false,
        }
    }

    pub fn remove(id: u32) {
        if let Some(m) = SESSIONS.lock().unwrap().as_mut() {
            m.remove(&id);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn registry_insert_send_remove() {
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        let id = registry::insert(tx);
        assert!(registry::send(id, SessionCmd::Disconnect));
        assert!(matches!(rx.try_recv().unwrap(), SessionCmd::Disconnect));
        registry::remove(id);
        assert!(!registry::send(id, SessionCmd::Disconnect));
    }
}
```

Add `mod session;` to `lib.rs`.

- [ ] **Step 3: Run the test**

Run: `cd packages/yourssh_rdp/rust && cargo test`
Expected: `registry_insert_send_remove ... ok`

- [ ] **Step 4: Regenerate bindings and verify**

Run: `cd packages/yourssh_rdp && flutter_rust_bridge_codegen generate && cd rust && cargo check`
Expected: clean. Open `lib/src/generated/api.dart` and **record the exact generated names** for the `RdpEvent` variants (FRB emits a sealed base with subclasses named like `RdpEvent_Started` and matching factory constructors). Tasks 9/12 use these names — fix them there if codegen differs.

- [ ] **Step 5: Commit**

```bash
git add packages/yourssh_rdp
git commit -m "feat(rdp): API types and session command registry (#44)"
```

### Task 4: Connection stage (TCP → TLS → optional NLA) + Connected event

**Files:**
- Create: `packages/yourssh_rdp/rust/src/connect.rs`
- Modify: `packages/yourssh_rdp/rust/src/lib.rs` (add `mod connect;`)

This task is modeled directly on `ironrdp-client/src/rdp.rs` (`build_config` + connect). The `connector::Config` field set drifts between releases — populate **every** field, copying defaults from the example's `build_config`; the literal below shows the semantic choices this feature needs.

- [ ] **Step 1: Implement `connect.rs`**

```rust
use anyhow::Context;
use ironrdp::connector::{self, ClientConnector, Credentials};
use ironrdp::pdu::rdp::capability_sets::MajorPlatformType;
use sha2::{Digest, Sha256};
use tokio::net::TcpStream;

use crate::api::{RdpCertInfo, RdpConfig};

pub struct Connected {
    pub framed: ironrdp_tokio::TokioFramed<ironrdp_tls::TlsStream<TcpStream>>,
    pub connection_result: connector::ConnectionResult,
    pub cert: RdpCertInfo,
}

pub fn build_connector_config(cfg: &RdpConfig) -> connector::Config {
    connector::Config {
        credentials: Credentials::UsernamePassword {
            username: cfg.username.clone(),
            password: cfg.password.clone(),
        },
        domain: cfg.domain.clone(),
        enable_tls: true,
        enable_credssp: cfg.security != "tls",
        desktop_size: connector::DesktopSize { width: cfg.width, height: cfg.height },
        desktop_scale_factor: 0,
        bitmap: None,
        client_build: 0,
        client_name: "yourssh".to_owned(),
        client_dir: "C:\\Windows\\System32\\mstscax.dll".to_owned(),
        platform: MajorPlatformType::UNSPECIFIED,
        enable_server_pointer: false,      // we render our own cursor
        autologon: true,
        pointer_software_rendering: true,
        performance_flags: Default::default(),
        // ---- remaining required fields: copy values verbatim from the
        // ironrdp-client example's build_config (keyboard_type,
        // keyboard_subtype, keyboard_functional_keys_count, keyboard_layout,
        // ime_file_name, dig_product_id, request_data, and any audio /
        // license / timezone fields the pinned version requires). Struct
        // literals must be exhaustive — the compiler enforces completeness.
        ..todo_copy_from_example()
    }
}

pub async fn rdp_connect_stage(cfg: &RdpConfig) -> anyhow::Result<Connected> {
    let addr = format!("{}:{}", cfg.target_host, cfg.target_port);
    let stream = TcpStream::connect(&addr).await.context("TCP connect")?;

    let mut framed = ironrdp_tokio::TokioFramed::new(stream);
    let mut connector = ClientConnector::new(build_connector_config(cfg));

    let should_upgrade = ironrdp_tokio::connect_begin(&mut framed, &mut connector).await?;

    // TLS upgrade
    let initial_stream = framed.into_inner_no_leftover();
    let (upgraded_stream, server_public_key) =
        ironrdp_tls::upgrade(initial_stream, &cfg.target_host).await?;
    let upgraded = ironrdp_tokio::mark_as_upgraded(should_upgrade, &mut connector);

    let cert = RdpCertInfo {
        sha256_fingerprint: hex(&Sha256::digest(&server_public_key)),
        subject: cfg.target_host.clone(),
    };

    let mut framed = ironrdp_tokio::TokioFramed::new(upgraded_stream);

    // connect_finalize signature (verify against pinned ironrdp-tokio):
    //   connect_finalize(upgraded, connector, &mut framed,
    //                    &mut network_client, server_name,
    //                    server_public_key, kerberos_config)
    // The NetworkClient is REQUIRED for CredSSP — use the same impl the
    // ironrdp-client example uses (sspi's reqwest network client).
    let mut network_client =
        sspi::network_client::reqwest_network_client::ReqwestNetworkClient::new();
    let connection_result = ironrdp_tokio::connect_finalize(
        upgraded,
        connector,
        &mut framed,
        &mut network_client,
        (&cfg.target_host).into(),
        server_public_key,
        None,
    )
    .await?;

    Ok(Connected { framed, connection_result, cert })
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg(security: &str) -> RdpConfig {
        RdpConfig {
            target_host: "h".into(), target_port: 3389, username: "u".into(),
            password: "p".into(), domain: None, width: 1280, height: 800,
            security: security.into(),
        }
    }

    #[test]
    fn tls_mode_disables_credssp() {
        assert!(!build_connector_config(&cfg("tls")).enable_credssp);
        assert!(build_connector_config(&cfg("auto")).enable_credssp);
        assert!(build_connector_config(&cfg("nla")).enable_credssp);
    }

    #[test]
    fn hex_lowercase() {
        assert_eq!(hex(&[0xAB, 0x01]), "ab01");
    }
}
```

(`..todo_copy_from_example()` is pseudocode shorthand: there is no real spread default — write out all remaining fields explicitly.)

Add `mod connect;` to `lib.rs` **in this task** so the module compiles at this commit.

- [ ] **Step 2: Run tests**

Run: `cargo test` in `rust/`
Expected: both unit tests pass; full build compiles against pinned ironrdp.

- [ ] **Step 3: Commit**

```bash
git add packages/yourssh_rdp/rust
git commit -m "feat(rdp): connection stage with TLS/NLA and cert fingerprint (#44)"
```

### Task 5: Active session loop — framebuffer + dirty-region FrameUpdate

**Files:**
- Create: `packages/yourssh_rdp/rust/src/run_loop.rs`
- Create: `packages/yourssh_rdp/rust/src/input.rs` (stub, completed in Task 6)
- Modify: `packages/yourssh_rdp/rust/src/api.rs`, `rust/src/lib.rs`

- [ ] **Step 1: Write the failing dirty-rect extraction test**

In `run_loop.rs`:

```rust
/// Copies the `region` rect out of the full RGBA framebuffer into a tight buffer.
pub fn extract_region(fb: &[u8], fb_width: u16, x: u16, y: u16, w: u16, h: u16) -> Vec<u8> {
    let stride = fb_width as usize * 4;
    let mut out = Vec::with_capacity(w as usize * h as usize * 4);
    for row in y as usize..(y as usize + h as usize) {
        let start = row * stride + x as usize * 4;
        out.extend_from_slice(&fb[start..start + w as usize * 4]);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extract_region_copies_tight_rect() {
        // 4x2 framebuffer, pixel value = its index
        let fb: Vec<u8> = (0..4 * 2 * 4).map(|i| i as u8).collect();
        let out = extract_region(&fb, 4, 1, 0, 2, 2);
        assert_eq!(out.len(), 2 * 2 * 4);
        assert_eq!(&out[0..4], &fb[4..8]);       // (1,0)
        assert_eq!(&out[8..12], &fb[20..24]);    // (1,1)
    }
}
```

- [ ] **Step 2: Run it**

Run: `cargo test extract_region`
Expected: PASS.

- [ ] **Step 3: Create the input stub** (completed in Task 6, needed now so this task commits green)

`input.rs`:

```rust
use ironrdp::session::{ActiveStage, ActiveStageOutput};
use ironrdp::session::image::DecodedImage;

use crate::session::SessionCmd;

pub struct InputState;

impl InputState {
    pub fn new() -> Self { Self }

    pub fn handle(
        &mut self,
        _stage: &mut ActiveStage,
        _image: &mut DecodedImage,
        _cmd: SessionCmd,
    ) -> anyhow::Result<Vec<ActiveStageOutput>> {
        Ok(vec![])
    }
}
```

- [ ] **Step 4: Implement the session loop**

Append to `run_loop.rs` (modeled on `ironrdp-client/src/rdp.rs::active_session`). Both the read path and the input path produce `ActiveStageOutput`s, routed through one helper:

```rust
use ironrdp::session::{ActiveStage, ActiveStageOutput};
use ironrdp::session::image::DecodedImage;
use tokio::sync::mpsc::UnboundedReceiver;

use crate::api::{RdpConfig, RdpEvent};
use crate::connect::{rdp_connect_stage, Connected};
use crate::input::InputState;
use crate::session::SessionCmd;

pub async fn run_session(
    cfg: RdpConfig,
    mut cmd_rx: UnboundedReceiver<SessionCmd>,
    sink: impl Fn(RdpEvent) + Send + Sync + 'static,
) {
    match run_session_inner(cfg, &mut cmd_rx, &sink).await {
        Ok(reason) => sink(RdpEvent::Disconnected { reason }),
        Err(e) => sink(RdpEvent::Error { message: format!("{e:#}") }),
    }
}

async fn run_session_inner(
    cfg: RdpConfig,
    cmd_rx: &mut UnboundedReceiver<SessionCmd>,
    sink: &(impl Fn(RdpEvent) + Send + Sync),
) -> anyhow::Result<String> {
    let Connected { mut framed, connection_result, cert } = rdp_connect_stage(&cfg).await?;
    sink(RdpEvent::Connected { cert });

    let mut image = DecodedImage::new(
        ironrdp::graphics::image_processing::PixelFormat::RgbA32,
        connection_result.desktop_size.width,
        connection_result.desktop_size.height,
    );
    let mut active_stage = ActiveStage::new(connection_result);
    let mut input = InputState::new();

    loop {
        let outputs = tokio::select! {
            frame = framed.read_pdu() => {
                let (action, payload) = frame?;
                active_stage.process(&mut image, action, &payload)?
            }
            cmd = cmd_rx.recv() => {
                match cmd {
                    None | Some(SessionCmd::Disconnect) => {
                        let frames = active_stage.graceful_shutdown()?;
                        for f in frames { framed.write_all(&f).await?; }
                        return Ok("disconnected by user".into());
                    }
                    Some(cmd) => input.handle(&mut active_stage, &mut image, cmd)?,
                }
            }
        };
        for out in outputs {
            match out {
                ActiveStageOutput::GraphicsUpdate(region) => {
                    // NOTE: verify against the pinned version whether the
                    // region carries exclusive width()/height() accessors or
                    // inclusive right/bottom (width = right - left + 1).
                    let (x, y) = (region.left, region.top);
                    let (w, h) = (region.width(), region.height());
                    sink(RdpEvent::FrameUpdate {
                        x, y, width: w, height: h,
                        rgba: extract_region(image.data(), image.width(), x, y, w, h),
                    });
                }
                ActiveStageOutput::ResponseFrame(frame) => framed.write_all(&frame).await?,
                ActiveStageOutput::Terminate(reason) => return Ok(format!("{reason:?}")),
                _ => {}
            }
        }
    }
}
```

And expose `rdp_connect` in `api.rs`. Because FRB discards the Rust return value of a StreamSink-taking function, the id is emitted as the first event:

```rust
use std::sync::Arc;

use tokio::sync::mpsc;

use crate::frb_generated::StreamSink;
use crate::session::{registry, SessionCmd};

static RUNTIME: std::sync::OnceLock<tokio::runtime::Runtime> = std::sync::OnceLock::new();

fn runtime() -> &'static tokio::runtime::Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2).enable_all().build().expect("tokio runtime")
    })
}

pub fn rdp_connect(config: RdpConfig, sink: StreamSink<RdpEvent>) {
    let (tx, rx) = mpsc::unbounded_channel::<SessionCmd>();
    let id = registry::insert(tx);
    let sink = Arc::new(sink);
    let _ = sink.add(RdpEvent::Started { session_id: id });
    let emit = {
        let sink = Arc::clone(&sink);
        move |ev: RdpEvent| { let _ = sink.add(ev); }
    };
    runtime().spawn(async move {
        crate::run_loop::run_session(config, rx, emit).await;
        registry::remove(id);
    });
}

pub fn rdp_disconnect(session_id: u32) {
    registry::send(session_id, SessionCmd::Disconnect);
}
```

Add `mod run_loop;` and `mod input;` to `lib.rs`.

- [ ] **Step 5: Regenerate bindings, build, test**

Run: `flutter_rust_bridge_codegen generate && cd rust && cargo test && cargo build --release`
Expected: all tests pass, release build OK, no unused-import warnings.

- [ ] **Step 6: Commit**

```bash
git add packages/yourssh_rdp
git commit -m "feat(rdp): active session loop with dirty-region frame events (#44)"
```

### Task 6: Input — mouse, wheel, keyboard scancodes

**Files:**
- Modify: `packages/yourssh_rdp/rust/src/input.rs`, `rust/src/api.rs`

- [ ] **Step 1: Implement `InputState` over `ironrdp::input::Database`**

`ActiveStage::process_fastpath_input(&mut self, image: &mut DecodedImage, events: &[FastPathInputEvent])` returns `Vec<ActiveStageOutput>` — the run loop (Task 5) already routes those through the shared output handler:

```rust
use ironrdp::input::{Database, MouseButton, MousePosition, Operation, Scancode, WheelRotations};
use ironrdp::session::{ActiveStage, ActiveStageOutput};
use ironrdp::session::image::DecodedImage;

use crate::session::SessionCmd;

pub struct InputState {
    db: Database,
}

impl InputState {
    pub fn new() -> Self {
        Self { db: Database::new() }
    }

    pub fn handle(
        &mut self,
        stage: &mut ActiveStage,
        image: &mut DecodedImage,
        cmd: SessionCmd,
    ) -> anyhow::Result<Vec<ActiveStageOutput>> {
        let ops = match cmd {
            SessionCmd::Mouse { x, y, button, action } => {
                let mut ops = vec![Operation::MouseMove(MousePosition { x, y })];
                if let Some(btn) = mouse_button(button) {
                    match action {
                        1 => ops.push(Operation::MouseButtonPressed(btn)),
                        2 => ops.push(Operation::MouseButtonReleased(btn)),
                        _ => {} // 0 = move only
                    }
                }
                ops
            }
            SessionCmd::Wheel { delta } => vec![Operation::WheelRotations(WheelRotations {
                is_vertical: true,
                rotation_units: delta,
            })],
            SessionCmd::Key { scancode, extended, down } => {
                let sc = Scancode::from_u16(if extended { 0xE000 | scancode } else { scancode });
                vec![if down { Operation::KeyPressed(sc) } else { Operation::KeyReleased(sc) }]
            }
            SessionCmd::ClipboardText(_) | SessionCmd::Disconnect => vec![],
        };
        if ops.is_empty() {
            return Ok(vec![]);
        }
        let events = self.db.apply(ops);
        Ok(stage.process_fastpath_input(image, &events)?)
    }
}

fn mouse_button(code: u8) -> Option<MouseButton> {
    match code {
        1 => Some(MouseButton::Left),
        2 => Some(MouseButton::Right),
        3 => Some(MouseButton::Middle),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::mouse_button;
    use ironrdp::input::MouseButton;

    #[test]
    fn mouse_button_mapping() {
        assert_eq!(mouse_button(1), Some(MouseButton::Left));
        assert_eq!(mouse_button(2), Some(MouseButton::Right));
        assert_eq!(mouse_button(3), Some(MouseButton::Middle));
        assert_eq!(mouse_button(9), None);
    }
}
```

- [ ] **Step 2: Expose senders in `api.rs`**

```rust
pub fn rdp_send_mouse(session_id: u32, x: u16, y: u16, button: u8, action: u8) {
    registry::send(session_id, SessionCmd::Mouse { x, y, button, action });
}

pub fn rdp_send_wheel(session_id: u32, delta: i16) {
    registry::send(session_id, SessionCmd::Wheel { delta });
}

pub fn rdp_send_key(session_id: u32, scancode: u16, extended: bool, down: bool) {
    registry::send(session_id, SessionCmd::Key { scancode, extended, down });
}
```

- [ ] **Step 3: Regenerate, test, commit**

Run: `flutter_rust_bridge_codegen generate && cd rust && cargo test`
Expected: PASS.

```bash
git add packages/yourssh_rdp
git commit -m "feat(rdp): mouse/wheel/keyboard input senders (#44)"
```

### Task 7: Clipboard text (cliprdr, both directions)

**Files:**
- Create: `packages/yourssh_rdp/rust/src/clipboard.rs`
- Modify: `rust/src/run_loop.rs`, `rust/src/api.rs`, `rust/src/lib.rs`

- [ ] **Step 1: Implement a text-only `CliprdrBackend`**

The `CliprdrBackend` trait has **12 required methods with no defaults** (verify the exact list on the pinned version): `temporary_directory`, `client_capabilities`, `on_ready`, `on_request_format_list`, `on_process_negotiated_capabilities`, `on_remote_copy`, `on_format_data_request`, `on_format_data_response`, `on_file_contents_request`, `on_file_contents_response`, `on_lock`, `on_unlock`. Implement **all of them**; everything except the four below is a no-op:

```rust
use std::sync::{Arc, Mutex};

use ironrdp_cliprdr::backend::CliprdrBackend;
use ironrdp_cliprdr::pdu::{
    ClipboardFormat, ClipboardFormatId, ClipboardGeneralCapabilityFlags,
    FormatDataRequest, FormatDataResponse,
};

/// Shared state: latest local clipboard text (set from Dart) and a callback
/// invoked when remote text arrives (delivered to Dart as an event).
pub struct ClipboardState {
    pub local_text: Mutex<String>,
    pub on_remote_text: Box<dyn Fn(String) + Send + Sync>,
}

pub struct TextClipboardBackend {
    pub state: Arc<ClipboardState>,
}

impl CliprdrBackend for TextClipboardBackend {
    fn temporary_directory(&self) -> &str { ".cliprdr" }

    fn client_capabilities(&self) -> ClipboardGeneralCapabilityFlags {
        ClipboardGeneralCapabilityFlags::USE_LONG_FORMAT_NAMES
    }

    /// Remote announced new clipboard content. Request unicode text if offered.
    fn on_remote_copy(&mut self, formats: &[ClipboardFormat]) {
        if formats.iter().any(|f| f.id() == ClipboardFormatId::CF_UNICODETEXT) {
            // The Cliprdr channel handle (held by run_loop) issues the
            // FormatDataRequest for CF_UNICODETEXT — see run_loop wiring.
        }
    }

    /// Remote wants OUR clipboard — serve the latest local text.
    /// RDP unicode text is UTF-16LE with a trailing NUL; check whether the
    /// pinned ironrdp-cliprdr exposes a helper, otherwise encode manually.
    fn on_format_data_request(&mut self, _req: FormatDataRequest) -> Option<FormatDataResponse<'static>> {
        let text = self.state.local_text.lock().unwrap().clone();
        Some(FormatDataResponse::new_unicode_string(&text))
    }

    /// Remote answered our FormatDataRequest with text → push to Dart.
    fn on_format_data_response(&mut self, resp: FormatDataResponse<'_>) {
        if let Ok(text) = resp.to_unicode_string() {
            (self.state.on_remote_text)(text);
        }
    }

    // ... the remaining 8 trait methods: explicit no-op bodies.
}
```

Wire the Cliprdr static channel into the connector in `run_loop.rs` exactly the way `ironrdp-client` does (it attaches the cliprdr machine before `connect_begin` and processes cliprdr SVC messages in the output loop). On `SessionCmd::ClipboardText(t)`: store into `local_text`, then send the cliprdr format-list announcement (copy ownership of the clipboard) through the channel handle. Emit `RdpEvent::ClipboardText` from `on_remote_text`.

- [ ] **Step 2: Expose the sender in `api.rs`**

```rust
pub fn rdp_send_clipboard_text(session_id: u32, text: String) {
    registry::send(session_id, SessionCmd::ClipboardText(text));
}
```

- [ ] **Step 3: Build, regenerate, commit**

Run: `flutter_rust_bridge_codegen generate && cd rust && cargo build --release && cargo test`
Expected: compiles, tests pass. Functional clipboard verification happens in the Task 20 manual matrix (needs a live server).

```bash
git add packages/yourssh_rdp
git commit -m "feat(rdp): text clipboard via cliprdr (#44)"
```

### Task 8: Panic guard

**Files:**
- Modify: `packages/yourssh_rdp/rust/src/api.rs`

- [ ] **Step 1: Wrap the spawned session in `catch_unwind`**

The `emit` closure from Task 5 already holds an `Arc<StreamSink>`, so cloning it is cheap. In `rdp_connect`'s spawn:

```rust
runtime().spawn(async move {
    let emit_for_panic = emit.clone();
    let fut = std::panic::AssertUnwindSafe(crate::run_loop::run_session(config, rx, emit));
    if let Err(panic) = futures::FutureExt::catch_unwind(fut).await {
        let msg = panic.downcast_ref::<&str>().map(|s| s.to_string())
            .or_else(|| panic.downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "internal error".into());
        emit_for_panic(RdpEvent::Error { message: format!("RDP engine panic: {msg}") });
    }
    registry::remove(id);
});
```

Make the `emit` closure `Clone` by deriving it from the `Arc<StreamSink>` (already the case in Task 5 — just add `#[derive(Clone)]`-equivalent by capturing the Arc in a cloneable closure or wrapping in a small struct). Verify FRB 2.7's `StreamSink` is `Send + Sync` (it is designed for cross-thread use); if `Sync` is missing, keep one `Arc<Mutex<StreamSink>>`.

- [ ] **Step 2: Build + commit**

Run: `cargo build --release && cargo test`
Expected: clean.

```bash
git add packages/yourssh_rdp/rust
git commit -m "feat(rdp): catch panics at FRB boundary as Error events (#44)"
```

---

## Phase 2 — Dart package API

### Task 9: `RdpClient` Dart wrapper

**Files:**
- Create: `packages/yourssh_rdp/lib/src/rdp_client.dart`
- Test: `packages/yourssh_rdp/test/rdp_client_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_rdp/yourssh_rdp.dart';

void main() {
  test('RdpSecurity.wire maps enum to FRB strings', () {
    expect(RdpSecurity.auto.wire, 'auto');
    expect(RdpSecurity.nla.wire, 'nla');
    expect(RdpSecurity.tls.wire, 'tls');
  });

  test('RdpConnectionSpec clamps and aligns resolution', () {
    final spec = RdpConnectionSpec(
      host: 'h', port: 3389, username: 'u', password: 'p',
      width: 1283, height: 719,
    );
    expect(spec.width, 1280); // rounded down to multiple of 4
    expect(spec.height, 716);
    final tiny = RdpConnectionSpec(
      host: 'h', port: 3389, username: 'u', password: 'p',
      width: 100, height: 50,
    );
    expect(tiny.width, 800); // clamped to minimum 800x600 (spec)
    expect(tiny.height, 600);
  });
}
```

- [ ] **Step 2: Run it — fails (class missing)**

Run: `cd packages/yourssh_rdp && flutter test test/rdp_client_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `rdp_client.dart`**

The session id arrives as the first stream event (`RdpEvent_Started`) — `connect` captures it transparently:

```dart
import 'generated/api.dart' as frb;
import 'generated/frb_generated.dart';
import 'native_loader.dart';

enum RdpSecurity {
  auto('auto'), nla('nla'), tls('tls');
  const RdpSecurity(this.wire);
  final String wire;
}

/// Validated connection parameters (resolution clamped to >=800x600 and
/// rounded down to a multiple of 4, per the design spec).
class RdpConnectionSpec {
  RdpConnectionSpec({
    required this.host, required this.port, required this.username,
    required this.password, this.domain, this.security = RdpSecurity.auto,
    required int width, required int height,
  })  : width = _align(width.clamp(800, 8192)),
        height = _align(height.clamp(600, 8192));

  final String host;
  final int port;
  final String username;
  final String password;
  final String? domain;
  final RdpSecurity security;
  final int width;
  final int height;

  static int _align(int v) => v - (v % 4);
}

/// Thin typed facade over the FRB bindings.
class RdpClient {
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    await RustLib.init(externalLibrary: loadYoursshRdpLibrary());
    _initialized = true;
  }

  int? _sessionId;
  int? get sessionId => _sessionId;

  Stream<frb.RdpEvent> connect(RdpConnectionSpec spec) {
    final raw = frb.rdpConnect(
      config: frb.RdpConfig(
        targetHost: spec.host, targetPort: spec.port,
        username: spec.username, password: spec.password,
        domain: spec.domain, width: spec.width, height: spec.height,
        security: spec.security.wire,
      ),
    );
    return raw.map((ev) {
      // First event carries the session id (FRB cannot return it directly).
      if (ev case frb.RdpEvent_Started(:final sessionId)) {
        _sessionId = sessionId;
      }
      return ev;
    });
  }

  void sendMouse(int x, int y, {int button = 0, int action = 0}) {
    final id = _sessionId; if (id == null) return;
    frb.rdpSendMouse(sessionId: id, x: x, y: y, button: button, action: action);
  }

  void sendWheel(int delta) {
    final id = _sessionId; if (id == null) return;
    frb.rdpSendWheel(sessionId: id, delta: delta);
  }

  void sendKey(int scancode, {required bool extended, required bool down}) {
    final id = _sessionId; if (id == null) return;
    frb.rdpSendKey(sessionId: id, scancode: scancode, extended: extended, down: down);
  }

  void sendClipboardText(String text) {
    final id = _sessionId; if (id == null) return;
    frb.rdpSendClipboardText(sessionId: id, text: text);
  }

  void disconnect() {
    final id = _sessionId; if (id == null) return;
    frb.rdpDisconnect(sessionId: id);
    _sessionId = null;
  }
}
```

(`RdpEvent_Started` and field casing: use the exact generated names recorded in Task 3 Step 4.)

- [ ] **Step 4: Run tests — pass**

Run: `flutter test`
Expected: PASS (pure-Dart tests don't load the dylib; keep `ensureInitialized` out of these tests).

- [ ] **Step 5: Commit**

```bash
git add packages/yourssh_rdp
git commit -m "feat(rdp): typed Dart RdpClient facade (#44)"
```

---

## Phase 3 — App integration

### Task 10: `Host.protocol` + RDP fields

**Files:**
- Modify: `app/lib/models/host.dart`
- Test: `app/test/models/host_rdp_test.dart` (create)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

void main() {
  test('Host JSON round-trips protocol, domain, rdpSecurity', () {
    final h = Host(
      id: 'x', label: 'win', host: '10.0.0.5', port: 3389,
      username: 'admin', authType: AuthType.password,
      protocol: HostProtocol.rdp, domain: 'CORP', rdpSecurity: RdpSecurityMode.nla,
    );
    final back = Host.fromJson(h.toJson());
    expect(back.protocol, HostProtocol.rdp);
    expect(back.domain, 'CORP');
    expect(back.rdpSecurity, RdpSecurityMode.nla);
  });

  test('legacy JSON without protocol parses as ssh', () {
    final back = Host.fromJson({
      'id': 'y', 'label': 'l', 'host': 'h', 'port': 22,
      'username': 'u', 'authType': 'password',
    });
    expect(back.protocol, HostProtocol.ssh);
    expect(back.domain, isNull);
    expect(back.rdpSecurity, RdpSecurityMode.auto);
  });
}
```

(Match constructor-arg style to the real `Host` constructor when writing the test.)

- [ ] **Step 2: Run — fails**

Run: `cd app && flutter test test/models/host_rdp_test.dart`
Expected: FAIL (enums missing).

- [ ] **Step 3: Implement in `host.dart`**

```dart
enum HostProtocol { ssh, rdp }

enum RdpSecurityMode { auto, nla, tls }
```

Add to `Host`: `HostProtocol protocol` (default `.ssh`), `String? domain`, `RdpSecurityMode rdpSecurity` (default `.auto`) — constructor params, `toJson` (`'protocol': protocol.name`, like neighbors), `fromJson` (`HostProtocol.values.byName(json['protocol'] as String? ?? 'ssh')`, etc.), and `copyWith` if `Host` has one. Follow the exact serialization style already used for `sftpMode`.

- [ ] **Step 4: Run tests — pass; run full suite + analyze**

Run: `flutter test test/models/ && flutter analyze`
Expected: PASS, no new analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/host.dart app/test/models/host_rdp_test.dart
git commit -m "feat(rdp): Host protocol/domain/rdpSecurity fields (#44)"
```

### Task 11: `AppSession` interface split + `SessionProvider` refactor

**Files:**
- Create: `app/lib/models/app_session.dart`
- Modify: `app/lib/models/terminal_session.dart`, `app/lib/providers/session_provider.dart`, `app/lib/screens/main_screen.dart`
- Test: `app/test/providers/session_provider_app_session_test.dart` (create)

- [ ] **Step 1: Create `app_session.dart`**

```dart
/// Tab-bar behavior shared by every session type (SSH, local PTY, RDP).
/// Terminal-specific members live in [TerminalSession].
abstract class AppSession {
  String get id;

  /// Label shown on the session tab.
  String get tabLabel;

  /// User rename — null means "use the default label".
  String? get customLabel;
  set customLabel(String? value);

  /// Tab color tag as #RRGGBB hex, null = none.
  String? get colorTag;
  set colorTag(String? value);

  bool get isPinned;
  set isPinned(bool value);
}
```

- [ ] **Step 2: Shrink `terminal_session.dart`**

```dart
import 'package:xterm/xterm.dart';

import 'app_session.dart';

/// A tab that hosts an xterm terminal: remote SSH sessions and local PTY
/// shells. RDP sessions implement [AppSession] directly.
abstract class TerminalSession extends AppSession {
  Terminal get terminal;
  bool get isLocal;

  /// Folder name recordings of this session are grouped under
  /// (`{recordingsPath}/{recordingFolder}/session_*.cast`).
  String get recordingFolder;

  /// Title written into the asciicast header.
  String get recordingTitle;
}
```

`SshSession` and `LocalSession` keep `implements TerminalSession` — they already provide the `customLabel`/`colorTag`/`isPinned` fields the new `AppSession` setters require; verify both still satisfy the contract.

- [ ] **Step 3: Write the failing provider test**

Construct the provider exactly as `app/test/providers/session_provider_test.dart:40` does (`SessionProvider(SshService(StorageService()), TabMetadataService())`), including its secure-storage method-channel mock from lines 22–34 — copy that `setUp` boilerplate:

```dart
test('sessions list is typed AppSession; sshSessions filters terminals', () {
  final p = SessionProvider(SshService(StorageService()), TabMetadataService());
  expect(p.sessions, isA<List<AppSession>>());
  expect(p.sshSessions, isEmpty);
});
```

- [ ] **Step 4: Refactor `SessionProvider` and `MainScreen` typing**

- `List<TerminalSession> _sessions` → `List<AppSession> _sessions`
- `List<AppSession> get sessions`
- `sshSessions` / `activeSshSession` keep `whereType<SshSession>()` filtering
- `activeSession` returns `AppSession?`
- **`main_screen.dart` must be retyped explicitly** (an `is RdpSession` branch added later is dead code otherwise): `_buildForeground(TerminalSession? active)` → `_buildForeground(AppSession? active)`, the `active` local in `_buildContent` (~line 677) and any `TerminalSession?` locals in the build chain (~line 501) → `AppSession?`.

Run `flutter analyze` and fix every type error it reports. The fix pattern at each call site is one of:
- consumer only uses tab behavior (label/pin/color/id) → change its parameter type to `AppSession`
- consumer needs `terminal`/recording → add `if (session is! TerminalSession) return;` (or `whereType<TerminalSession>()`) guard

Known call sites from exploration: `main_screen.dart` (tab bar + `_buildForeground` chain), `app/lib/widgets/split_terminal_view.dart`, `app/lib/main.dart` (recording wiring), snippets `sendInput` path in the plugin context impl, `app/lib/services/workspace_service.dart`, `app/lib/services/tab_metadata_service.dart`. The analyzer is the source of truth — fix all of them.

- [ ] **Step 5: Run full test suite + analyze — green**

Run: `cd app && flutter test && flutter analyze`
Expected: all existing tests still pass, zero analyzer errors.

- [ ] **Step 6: Commit**

```bash
git add -A app/lib app/test
git commit -m "refactor(session): split AppSession tab interface from TerminalSession (#44)"
```

### Task 12: `RdpSession` model

**Files:**
- Create: `app/lib/models/rdp_session.dart`
- Test: `app/test/models/rdp_session_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/rdp_session.dart';
import 'package:yourssh_rdp/yourssh_rdp.dart' show RdpClient;
import 'package:yourssh_rdp/src/generated/api.dart' as frb;

Host _host() => Host(
    id: 'h1', label: 'win', host: '1.2.3.4', port: 3389,
    username: 'u', authType: AuthType.password, protocol: HostProtocol.rdp);

void main() {
  test('status transitions on events', () async {
    final events = StreamController<frb.RdpEvent>();
    final s = RdpSession(host: _host(), client: RdpClient(), width: 800, height: 600);
    s.attach(events.stream);
    expect(s.status, RdpSessionStatus.connecting);

    events.add(const frb.RdpEvent.started(sessionId: 1));
    events.add(frb.RdpEvent.connected(
        cert: frb.RdpCertInfo(sha256Fingerprint: 'ab', subject: 's')));
    await Future<void>.delayed(Duration.zero);
    expect(s.status, RdpSessionStatus.connected);

    events.add(const frb.RdpEvent.disconnected(reason: 'bye'));
    await Future<void>.delayed(Duration.zero);
    expect(s.status, RdpSessionStatus.disconnected);
    expect(s.lastMessage, 'bye');
  });

  test('frame updates patch the framebuffer', () async {
    final events = StreamController<frb.RdpEvent>();
    final s = RdpSession(host: _host(), client: RdpClient(), width: 8, height: 8);
    s.attach(events.stream);
    final red = List<int>.filled(4 * 4 * 4, 0);
    for (var i = 0; i < red.length; i += 4) { red[i] = 255; red[i + 3] = 255; }
    events.add(frb.RdpEvent.frameUpdate(
        x: 2, y: 2, width: 4, height: 4, rgba: Uint8List.fromList(red)));
    await Future<void>.delayed(Duration.zero);
    // pixel (2,2) is red in the full framebuffer
    final offset = (2 * 8 + 2) * 4;
    expect(s.framebuffer[offset], 255);
    expect(s.framebuffer[offset + 3], 255);
  });

  test('tab label uses host label', () {
    final s = RdpSession(host: _host(), client: RdpClient(), width: 800, height: 600);
    expect(s.tabLabel, 'win');
    s.customLabel = 'prod';
    expect(s.tabLabel, 'prod');
  });
}
```

(Factory-constructor names: use the generated names recorded in Task 3 Step 4.)

- [ ] **Step 2: Run — fails**

Run: `flutter test test/models/rdp_session_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `rdp_session.dart`**

```dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:yourssh_rdp/yourssh_rdp.dart';
import 'package:yourssh_rdp/src/generated/api.dart' as frb;

import '../services/rdp_tunnel_proxy.dart';
import 'app_session.dart';
import 'host.dart';

enum RdpSessionStatus { connecting, connected, disconnected, error }

/// One RDP tab. Holds the event subscription, framebuffer, and status.
/// Pure model: no widget imports; UI listens via [ChangeNotifier].
class RdpSession extends ChangeNotifier implements AppSession {
  RdpSession({
    required this.host,
    required this.client,
    required this.width,
    required this.height,
    this.tunnelProxy,
  }) : framebuffer = Uint8List(width * height * 4);

  final Host host;
  final RdpClient client;
  final int width;
  final int height;
  final Uint8List framebuffer;

  /// Non-null when this session runs through an SSH tunnel; owned by the
  /// session and stopped on [close].
  final RdpTunnelProxy? tunnelProxy;

  @override
  String get id => _id;
  final String _id = 'rdp_${DateTime.now().microsecondsSinceEpoch}';

  RdpSessionStatus status = RdpSessionStatus.connecting;
  String? lastMessage;
  String? certFingerprint;
  bool _tunnelClosed = false;

  /// Latest decoded frame for painting; rebuilt lazily after patches.
  ui.Image? image;
  bool _decodeScheduled = false;
  StreamSubscription<frb.RdpEvent>? _sub;

  void Function(String text)? onRemoteClipboardText;

  @override
  String? customLabel;
  @override
  String? colorTag;
  @override
  bool isPinned = false;
  @override
  String get tabLabel => customLabel ?? host.label;

  void attach(Stream<frb.RdpEvent> events) {
    _sub = events.listen(_onEvent, onError: (Object e) {
      status = RdpSessionStatus.error;
      lastMessage = '$e';
      notifyListeners();
    });
  }

  /// Called by the tunnel proxy when the SSH side collapsed, so the
  /// disconnect message names the real cause (spec: "SSH tunnel closed").
  void markTunnelClosed() => _tunnelClosed = true;

  void _onEvent(frb.RdpEvent ev) {
    switch (ev) {
      case frb.RdpEvent_Started():
        return; // id captured inside RdpClient.connect
      case frb.RdpEvent_Connected(:final cert):
        status = RdpSessionStatus.connected;
        certFingerprint = cert.sha256Fingerprint;
      case frb.RdpEvent_FrameUpdate(:final x, :final y, :final width, :final height, :final rgba):
        _patch(x, y, width, height, rgba);
      case frb.RdpEvent_ClipboardText(:final text):
        onRemoteClipboardText?.call(text);
        return; // no repaint needed
      case frb.RdpEvent_Disconnected(:final reason):
        status = RdpSessionStatus.disconnected;
        lastMessage = _tunnelClosed ? 'SSH tunnel closed' : reason;
      case frb.RdpEvent_Error(:final message):
        status = RdpSessionStatus.error;
        lastMessage = _tunnelClosed ? 'SSH tunnel closed' : message;
    }
    notifyListeners();
  }

  void _patch(int x, int y, int w, int h, Uint8List rgba) {
    final fbStride = width * 4;
    for (var row = 0; row < h; row++) {
      final dst = (y + row) * fbStride + x * 4;
      final src = row * w * 4;
      framebuffer.setRange(dst, dst + w * 4, rgba, src);
    }
    _scheduleDecode();
  }

  void _scheduleDecode() {
    if (_decodeScheduled) return; // coalesce bursts into one decode
    _decodeScheduled = true;
    scheduleMicrotask(() async {
      _decodeScheduled = false;
      // fromUint8List snapshots synchronously, so the decoded image is
      // internally consistent even if a patch lands during the await.
      final buf = await ui.ImmutableBuffer.fromUint8List(framebuffer);
      final desc = ui.ImageDescriptor.raw(buf,
          width: width, height: height, pixelFormat: ui.PixelFormat.rgba8888);
      final codec = await desc.instantiateCodec();
      image = (await codec.getNextFrame()).image;
      notifyListeners();
    });
  }

  Future<void> close() async {
    await _sub?.cancel();
    client.disconnect();
    await tunnelProxy?.stop();
  }
}
```

(Subclass pattern names `frb.RdpEvent_*`: use the generated names recorded in Task 3 Step 4. `RdpTunnelProxy` is created in Task 13 — to keep this task green, create the file with the class skeleton from Task 13 Step 3 now, or reorder Tasks 12/13's commit so the proxy lands first; the test above does not exercise the proxy.)

- [ ] **Step 4: Run — pass**

Run: `flutter test test/models/rdp_session_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/rdp_session.dart app/test/models/rdp_session_test.dart app/lib/services/rdp_tunnel_proxy.dart
git commit -m "feat(rdp): RdpSession model with framebuffer patching (#44)"
```

### Task 13: Loopback tunnel proxy + `SessionProvider.connect` branch

**Files:**
- Create: `app/lib/services/rdp_tunnel_proxy.dart`
- Modify: `app/lib/providers/session_provider.dart`, `app/lib/services/ssh_service.dart`, `app/lib/main.dart`
- Modify: connect call sites — `app/lib/widgets/hosts_dashboard.dart` (~lines 572, 695), `app/lib/widgets/host_list.dart` (~line 49), command palette connect action (verify it exists in `app/lib/widgets/command_palette.dart`)
- Test: `app/test/services/rdp_tunnel_proxy_test.dart`

- [ ] **Step 1: Write the failing proxy test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/rdp_tunnel_proxy.dart';

void main() {
  test('pipes bytes both ways through one accepted connection', () async {
    // Fake "remote" echo server stands in for the SSH-forwarded end.
    final echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    echo.listen((s) => s.listen(s.add));

    final proxy = RdpTunnelProxy();
    final port = await proxy.start(() async {
      final socket = await Socket.connect('127.0.0.1', echo.port);
      return TunnelEnd(stream: socket, sink: socket, close: socket.destroy);
    });

    final client = await Socket.connect('127.0.0.1', port);
    client.add([1, 2, 3]);
    final received = await client.first;
    expect(received, [1, 2, 3]);

    client.destroy();
    await proxy.stop();
    await echo.close();
  });
}
```

- [ ] **Step 2: Run — fails**

Run: `flutter test test/services/rdp_tunnel_proxy_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `rdp_tunnel_proxy.dart`**

`sink` is typed `StreamSink<List<int>>` — that's what dartssh2's `SSHSocket.sink` is, and a `dart:io` `Socket` satisfies it too (which is what the test exploits):

```dart
import 'dart:async';
import 'dart:io';

/// Generic byte-pipe endpoint so the proxy can be tested without dartssh2:
/// for real tunnels, stream/sink come from an SSHSocket (forwardLocal),
/// whose sink is a StreamSink<List<int>> (NOT an IOSink).
class TunnelEnd {
  TunnelEnd({required this.stream, required this.sink, required this.close});
  final Stream<List<int>> stream;
  final StreamSink<List<int>> sink;
  final void Function() close;
}

/// One-shot loopback proxy: binds 127.0.0.1 on a random port, accepts exactly
/// one connection, pipes it to a freshly opened tunnel end, then refuses
/// further connections. Dies with the session ([stop]).
class RdpTunnelProxy {
  RdpTunnelProxy({this.onClosed});

  /// Fired when the tunnel side ends before [stop] — lets the session report
  /// "SSH tunnel closed" instead of a generic disconnect.
  final void Function()? onClosed;

  ServerSocket? _server;
  Socket? _client;
  TunnelEnd? _tunnel;
  bool _stopped = false;

  Future<int> start(Future<TunnelEnd> Function() openTunnel) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((client) async {
      if (_client != null) {
        client.destroy(); // one-shot: refuse extra connections
        return;
      }
      _client = client;
      try {
        final tunnel = await openTunnel();
        _tunnel = tunnel;
        client.listen(tunnel.sink.add,
            onDone: tunnel.close, onError: (_) => tunnel.close());
        tunnel.stream.listen(client.add,
            onDone: () => _tunnelEnded(client),
            onError: (_) => _tunnelEnded(client));
      } catch (_) {
        client.destroy();
        _tunnelEnded(client);
      }
    });
    return server.port;
  }

  void _tunnelEnded(Socket client) {
    client.destroy();
    if (!_stopped) onClosed?.call();
  }

  Future<void> stop() async {
    _stopped = true;
    await _server?.close();
    _client?.destroy();
    _tunnel?.close();
  }
}
```

- [ ] **Step 4: Run — pass**

Run: `flutter test test/services/rdp_tunnel_proxy_test.dart`
Expected: PASS.

- [ ] **Step 5: Add `openTunnelSocket` to `SshService`**

This is **not** a one-liner: `forwardLocal` needs a live jump client. Reuse the existing jump-host machinery (`_ensureJumpClient` at the `ssh_service.dart:154` call path), which requires resolving the jump `Host`, its key entry, and the host-key verifier — all available through the same lookup callbacks the jump-host feature already uses:

```dart
/// Opens a forwarded socket to [targetHost]:[targetPort] through the SSH
/// host identified by [jumpHostId]. Reuses _ensureJumpClient (jump-host
/// resolution via jumpHostLookup, key lookup, hostKeyVerifier) and registers
/// the consumer host id for teardown, exactly like the jump-host connect
/// path at ssh_service.dart:154.
Future<SSHSocket> openTunnelSocket(
    String jumpHostId, String targetHost, int targetPort, String forHostId) async {
  final jumpHost = jumpHostLookup?.call(jumpHostId);
  if (jumpHost == null) throw StateError('Jump host $jumpHostId not found');
  final jc = await _ensureJumpClient(jumpHost /*, keyEntry:, verifyHostKey: —
      mirror the exact arguments used in the existing jump path */);
  _hostToJump[forHostId] = jumpHostId; // teardown bookkeeping, as SSH does
  return jc.forwardLocal(targetHost, targetPort);
}
```

(Adapt names — `jumpHostLookup`, `_hostToJump`, `_ensureJumpClient` parameters — to the real code; the existing jump-host connect block is the template.)

- [ ] **Step 6: Add the connect branch in `SessionProvider`**

```dart
/// Branches on protocol. Call sites that connect hosts use this instead of
/// connect(): hosts_dashboard (~572, ~695), host_list (~49), command palette.
Future<AppSession?> connectAny(Host host) =>
    host.protocol == HostProtocol.rdp ? connectRdp(host) : connect(host);

Future<RdpSession?> connectRdp(Host host) async {
  await RdpClient.ensureInitialized();
  final password = await storage.loadPassword(host.id) ?? '';
  final size = rdpDesktopSize?.call() ?? const Size(1280, 800);

  var targetHost = host.host;
  var targetPort = host.port;
  RdpTunnelProxy? proxy;
  RdpSession? session; // captured by the proxy callback below
  if (host.jumpHostId != null) {
    proxy = RdpTunnelProxy(onClosed: () => session?.markTunnelClosed());
    final port = await proxy.start(() async {
      final sshSocket = await sshService.openTunnelSocket(
          host.jumpHostId!, host.host, host.port, host.id);
      return TunnelEnd(
          stream: sshSocket.stream, sink: sshSocket.sink, close: sshSocket.destroy);
    });
    targetHost = '127.0.0.1';
    targetPort = port;
  }

  final client = RdpClient();
  final spec = RdpConnectionSpec(
    host: targetHost, port: targetPort,
    username: host.username, password: password, domain: host.domain,
    security: RdpSecurity.values.byName(host.rdpSecurity.name),
    width: size.width.round(), height: size.height.round(),
  );
  session = RdpSession(
      host: host, client: client,
      width: spec.width, height: spec.height, tunnelProxy: proxy);
  session.onRemoteClipboardText =
      (t) => Clipboard.setData(ClipboardData(text: t));
  // Tab metadata (rename/pin/color) — same flow the SSH connect path runs
  // at session_provider.dart:97-108: load persisted metadata for this host
  // and apply to the session before adding it.
  applyTabMetadata(session); // adapt to the real method/inline code
  session.attach(client.connect(spec));
  session.addListener(notifyListeners);
  _sessions.add(session);
  _activeIndex = _sessions.length - 1;
  notifyListeners();
  return session;
}
```

Wire-up notes for the executor:
- `rdpDesktopSize` is a new injectable callback **set in `main.dart`** (like the existing key-lookup callbacks): returns the terminal workspace's `RenderBox` size × `MediaQuery.devicePixelRatioOf(context)`. Concretely: expose the workspace size from `MainScreen` via a `GlobalKey` or a size-reporting callback, and register `sessionProvider.rdpDesktopSize = () => lastKnownWorkspaceSize * dpr` during app wiring.
- `SSHSocket.destroy()` is `void` (matching `TunnelEnd.close`); do not use `close()` (it returns a `Future`).
- Adapt field/method names (`storage.loadPassword`, `_activeIndex`, tab-metadata application) to the real ones in `session_provider.dart` / `storage_service.dart` / `tab_metadata_service.dart`.
- Closing an RDP tab: the existing close-tab path must call `session.close()` (which stops the proxy via `tunnelProxy`).
- Update **all** connect call sites to `connectAny`: `hosts_dashboard.dart` (~572, ~695), `host_list.dart` (~49), and the command palette connect action if present.

- [ ] **Step 7: Test + analyze + commit**

Run: `flutter test && flutter analyze`
Expected: green.

```bash
git add -A app/lib app/test
git commit -m "feat(rdp): SSH tunnel loopback proxy and RDP connect flow (#44)"
```

### Task 14: Scancode map + mouse coordinate scaling

**Files:**
- Create: `app/lib/util/rdp_input_mapping.dart`
- Test: `app/test/util/rdp_input_mapping_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/util/rdp_input_mapping.dart';

void main() {
  test('letters, digits, modifiers map to set-1 scancodes', () {
    expect(rdpScancodeFor(PhysicalKeyboardKey.keyA), (0x1E, false));
    expect(rdpScancodeFor(PhysicalKeyboardKey.digit1), (0x02, false));
    expect(rdpScancodeFor(PhysicalKeyboardKey.enter), (0x1C, false));
    expect(rdpScancodeFor(PhysicalKeyboardKey.controlLeft), (0x1D, false));
    expect(rdpScancodeFor(PhysicalKeyboardKey.altRight), (0x38, true)); // E0
    expect(rdpScancodeFor(PhysicalKeyboardKey.arrowUp), (0x48, true));
    expect(rdpScancodeFor(PhysicalKeyboardKey.delete), (0x53, true));
    expect(rdpScancodeFor(PhysicalKeyboardKey.pause), isNull); // E1 sequence — unsupported v1
    expect(rdpScancodeFor(PhysicalKeyboardKey.f24), isNull); // unmapped
  });

  test('mouse coordinates scale back to session space', () {
    // session 1920x1080 rendered into a 960x540 box at offset (10, 20)
    final p = sessionPointFor(
      localX: 490, localY: 290,
      renderOffsetX: 10, renderOffsetY: 20, renderScale: 0.5,
      sessionWidth: 1920, sessionHeight: 1080,
    );
    expect(p, (960, 540));
    // out of the rendered image → clamped
    final q = sessionPointFor(
      localX: 0, localY: 0,
      renderOffsetX: 10, renderOffsetY: 20, renderScale: 0.5,
      sessionWidth: 1920, sessionHeight: 1080,
    );
    expect(q, (0, 0));
  });
}
```

- [ ] **Step 2: Run — fails**

Run: `flutter test test/util/rdp_input_mapping_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `rdp_input_mapping.dart`**

```dart
import 'package:flutter/services.dart';

/// (scancode, isExtended) for the RDP set-1 keyboard layer, or null if the
/// key has no single-scancode RDP equivalent.
///
/// Deliberately unmapped: Pause (real make code is the E1-prefixed sequence
/// E1 1D 45, which (scancode, extended) cannot express — special-case it in
/// Rust if ever needed). PrintScreen is mapped to the pragmatic single
/// E0 0x37 most servers accept, not the full E0 2A E0 37 sequence.
(int, bool)? rdpScancodeFor(PhysicalKeyboardKey key) => _table[key.usbHidUsage];

(int, int) sessionPointFor({
  required double localX, required double localY,
  required double renderOffsetX, required double renderOffsetY,
  required double renderScale,
  required int sessionWidth, required int sessionHeight,
}) {
  final x = ((localX - renderOffsetX) / renderScale)
      .clamp(0, sessionWidth - 1).round();
  final y = ((localY - renderOffsetY) / renderScale)
      .clamp(0, sessionHeight - 1).round();
  return (x, y);
}

// USB HID usage → (set-1 scancode, extended). Source: USB HID-to-PS/2
// scan code translation table (Microsoft) — keys present on common layouts.
final Map<int, (int, bool)> _table = {
  0x00070004: (0x1E, false), 0x00070005: (0x30, false), 0x00070006: (0x2E, false), // A B C
  0x00070007: (0x20, false), 0x00070008: (0x12, false), 0x00070009: (0x21, false), // D E F
  0x0007000A: (0x22, false), 0x0007000B: (0x23, false), 0x0007000C: (0x17, false), // G H I
  0x0007000D: (0x24, false), 0x0007000E: (0x25, false), 0x0007000F: (0x26, false), // J K L
  0x00070010: (0x32, false), 0x00070011: (0x31, false), 0x00070012: (0x18, false), // M N O
  0x00070013: (0x19, false), 0x00070014: (0x10, false), 0x00070015: (0x13, false), // P Q R
  0x00070016: (0x1F, false), 0x00070017: (0x14, false), 0x00070018: (0x16, false), // S T U
  0x00070019: (0x2F, false), 0x0007001A: (0x11, false), 0x0007001B: (0x2D, false), // V W X
  0x0007001C: (0x15, false), 0x0007001D: (0x2C, false),                            // Y Z
  0x0007001E: (0x02, false), 0x0007001F: (0x03, false), 0x00070020: (0x04, false), // 1 2 3
  0x00070021: (0x05, false), 0x00070022: (0x06, false), 0x00070023: (0x07, false), // 4 5 6
  0x00070024: (0x08, false), 0x00070025: (0x09, false), 0x00070026: (0x0A, false), // 7 8 9
  0x00070027: (0x0B, false),                                                       // 0
  0x00070028: (0x1C, false), 0x00070029: (0x01, false), 0x0007002A: (0x0E, false), // Enter Esc Bksp
  0x0007002B: (0x0F, false), 0x0007002C: (0x39, false),                            // Tab Space
  0x0007002D: (0x0C, false), 0x0007002E: (0x0D, false),                            // - =
  0x0007002F: (0x1A, false), 0x00070030: (0x1B, false), 0x00070031: (0x2B, false), // [ ] \
  0x00070033: (0x27, false), 0x00070034: (0x28, false), 0x00070035: (0x29, false), // ; ' `
  0x00070036: (0x33, false), 0x00070037: (0x34, false), 0x00070038: (0x35, false), // , . /
  0x00070039: (0x3A, false),                                                       // CapsLock
  0x0007003A: (0x3B, false), 0x0007003B: (0x3C, false), 0x0007003C: (0x3D, false), // F1-F3
  0x0007003D: (0x3E, false), 0x0007003E: (0x3F, false), 0x0007003F: (0x40, false), // F4-F6
  0x00070040: (0x41, false), 0x00070041: (0x42, false), 0x00070042: (0x43, false), // F7-F9
  0x00070043: (0x44, false), 0x00070044: (0x57, false), 0x00070045: (0x58, false), // F10-F12
  0x00070046: (0x37, true),  0x00070047: (0x46, false),                            // PrtSc(approx) ScrLk
  // 0x00070048 Pause: intentionally unmapped (E1 sequence)
  0x00070049: (0x52, true),  0x0007004A: (0x47, true),  0x0007004B: (0x49, true),  // Ins Home PgUp
  0x0007004C: (0x53, true),  0x0007004D: (0x4F, true),  0x0007004E: (0x51, true),  // Del End PgDn
  0x0007004F: (0x4D, true),  0x00070050: (0x4B, true),  0x00070051: (0x50, true),  // → ← ↓
  0x00070052: (0x48, true),                                                        // ↑
  0x00070053: (0x45, false),                                                       // NumLock
  0x00070054: (0x35, true),  0x00070055: (0x37, false), 0x00070056: (0x4A, false), // KP/ KP* KP-
  0x00070057: (0x4E, false), 0x00070058: (0x1C, true),                             // KP+ KPEnter
  0x00070059: (0x4F, false), 0x0007005A: (0x50, false), 0x0007005B: (0x51, false), // KP1-3
  0x0007005C: (0x4B, false), 0x0007005D: (0x4C, false), 0x0007005E: (0x4D, false), // KP4-6
  0x0007005F: (0x47, false), 0x00070060: (0x48, false), 0x00070061: (0x49, false), // KP7-9
  0x00070062: (0x52, false), 0x00070063: (0x53, false),                            // KP0 KP.
  0x000700E0: (0x1D, false), 0x000700E1: (0x2A, false), 0x000700E2: (0x38, false), // LCtrl LShift LAlt
  0x000700E3: (0x5B, true),                                                        // LWin/Cmd
  0x000700E4: (0x1D, true),  0x000700E5: (0x36, false), 0x000700E6: (0x38, true),  // RCtrl RShift RAlt
  0x000700E7: (0x5C, true),                                                        // RWin/Cmd
};
```

- [ ] **Step 4: Run — pass; commit**

Run: `flutter test test/util/rdp_input_mapping_test.dart`
Expected: PASS.

```bash
git add app/lib/util/rdp_input_mapping.dart app/test/util/rdp_input_mapping_test.dart
git commit -m "feat(rdp): scancode table and mouse coordinate mapping (#44)"
```

### Task 15: `RdpWorkspace` widget + `MainScreen` branch

**Files:**
- Create: `app/lib/widgets/rdp_workspace.dart`
- Modify: `app/lib/screens/main_screen.dart` (`_buildForeground`), `app/lib/providers/session_provider.dart` (`reconnectRdp`)
- Test: `app/test/widgets/rdp_workspace_test.dart`

- [ ] **Step 1: Write the failing widget test**

State is driven through the event stream (no `notifyListeners` from outside — it's `@protected` and would trip the analyzer gate):

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/rdp_session.dart';
import 'package:yourssh/widgets/rdp_workspace.dart';
import 'package:yourssh_rdp/yourssh_rdp.dart' show RdpClient;
import 'package:yourssh_rdp/src/generated/api.dart' as frb;

void main() {
  testWidgets('shows connecting overlay, then error overlay with retry',
      (tester) async {
    final events = StreamController<frb.RdpEvent>();
    final session = RdpSession(
        host: Host(id: 'h', label: 'w', host: 'x', port: 3389,
            username: 'u', authType: AuthType.password,
            protocol: HostProtocol.rdp),
        client: RdpClient(), width: 800, height: 600);
    session.attach(events.stream);

    await tester.pumpWidget(MaterialApp(home: RdpWorkspace(session: session)));
    expect(find.textContaining('Connecting'), findsOneWidget);

    events.add(const frb.RdpEvent.error(message: 'auth failed'));
    await tester.pump();
    expect(find.textContaining('auth failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — fails**

Run: `flutter test test/widgets/rdp_workspace_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `rdp_workspace.dart`**

```dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/rdp_session.dart';
import '../theme/app_theme.dart';
import '../util/rdp_input_mapping.dart';

/// Full workspace for an active RDP tab: rendered remote screen,
/// input capture, slim toolbar, and status overlays.
class RdpWorkspace extends StatefulWidget {
  const RdpWorkspace({super.key, required this.session, this.onReconnect});

  final RdpSession session;
  final VoidCallback? onReconnect;

  @override
  State<RdpWorkspace> createState() => _RdpWorkspaceState();
}

class _RdpWorkspaceState extends State<RdpWorkspace> {
  final _focusNode = FocusNode();
  int _lastButton = 1;

  RdpSession get session => widget.session;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Column(children: [
        _Toolbar(session: session),
        Expanded(child: _buildBody()),
      ]),
    );
  }

  Widget _buildBody() {
    switch (session.status) {
      case RdpSessionStatus.connecting:
        return const Center(child: Text('Connecting…'));
      case RdpSessionStatus.error:
      case RdpSessionStatus.disconnected:
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(session.lastMessage ?? 'Disconnected'),
            const SizedBox(height: 12),
            FilledButton(onPressed: widget.onReconnect, child: const Text('Retry')),
          ]),
        );
      case RdpSessionStatus.connected:
        return LayoutBuilder(builder: (context, constraints) {
          final scale = math.min(constraints.maxWidth / session.width,
              constraints.maxHeight / session.height);
          final renderW = session.width * scale;
          final renderH = session.height * scale;
          final offX = (constraints.maxWidth - renderW) / 2;
          final offY = (constraints.maxHeight - renderH) / 2;

          (int, int) toSession(Offset local) => sessionPointFor(
              localX: local.dx, localY: local.dy,
              renderOffsetX: offX, renderOffsetY: offY, renderScale: scale,
              sessionWidth: session.width, sessionHeight: session.height);

          return Focus(
            focusNode: _focusNode,
            autofocus: true,
            onFocusChange: (gained) async {
              if (!gained) return;
              // Spec: push local clipboard to remote when the view gains focus.
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              final text = data?.text;
              if (text != null && text.isNotEmpty) {
                session.client.sendClipboardText(text);
              }
            },
            onKeyEvent: (node, event) {
              final mapped = rdpScancodeFor(event.physicalKey);
              if (mapped == null) return KeyEventResult.ignored;
              final (code, extended) = mapped;
              if (event is KeyDownEvent || event is KeyRepeatEvent) {
                session.client.sendKey(code, extended: extended, down: true);
              } else if (event is KeyUpEvent) {
                session.client.sendKey(code, extended: extended, down: false);
              }
              return KeyEventResult.handled;
            },
            child: Listener(
              onPointerHover: (e) {
                final (x, y) = toSession(e.localPosition);
                session.client.sendMouse(x, y);
              },
              onPointerMove: (e) {
                final (x, y) = toSession(e.localPosition);
                session.client.sendMouse(x, y);
              },
              onPointerDown: (e) {
                _focusNode.requestFocus();
                final (x, y) = toSession(e.localPosition);
                // e.buttons includes the new button on down; cache it because
                // PointerUpEvent.buttons no longer contains it. (Single-field
                // cache — chorded multi-button presses release as the last
                // pressed button; acceptable v1.)
                session.client.sendMouse(x, y,
                    button: _button(e.buttons), action: 1);
              },
              onPointerUp: (e) {
                final (x, y) = toSession(e.localPosition);
                session.client.sendMouse(x, y, button: _lastButton, action: 2);
              },
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) {
                  session.client
                      .sendWheel((-e.scrollDelta.dy).round().clamp(-256, 255));
                }
              },
              child: CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _FramePainter(session.image, offX, offY, scale),
              ),
            ),
          );
        });
    }
  }

  int _button(int buttons) {
    _lastButton = switch (buttons) {
      kSecondaryMouseButton => 2,
      kMiddleMouseButton => 3,
      _ => 1, // includes chorded bitmasks — treated as left, acceptable v1
    };
    return _lastButton;
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.session});
  final RdpSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      color: AppColors.surface,
      child: Row(children: [
        const SizedBox(width: 8),
        Text(session.tabLabel, style: Theme.of(context).textTheme.labelMedium),
        const Spacer(),
        IconButton(
          tooltip: 'Send Ctrl+Alt+Del',
          icon: const Icon(Icons.keyboard_command_key, size: 16),
          onPressed: () {
            final c = session.client;
            c.sendKey(0x1D, extended: false, down: true);  // Ctrl
            c.sendKey(0x38, extended: false, down: true);  // Alt
            c.sendKey(0x53, extended: true, down: true);   // Del (E0)
            c.sendKey(0x53, extended: true, down: false);
            c.sendKey(0x38, extended: false, down: false);
            c.sendKey(0x1D, extended: false, down: false);
          },
        ),
        IconButton(
          tooltip: 'Push clipboard to remote',
          icon: const Icon(Icons.content_paste_go, size: 16),
          onPressed: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            if (data?.text != null) session.client.sendClipboardText(data!.text!);
          },
        ),
        IconButton(
          tooltip: 'Disconnect',
          icon: const Icon(Icons.power_settings_new, size: 16),
          onPressed: () => session.client.disconnect(),
        ),
        const SizedBox(width: 4),
      ]),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.image, this.offX, this.offY, this.scale);
  final ui.Image? image;
  final double offX, offY, scale;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null) return;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(offX, offY, img.width * scale, img.height * scale),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.image != image || old.scale != scale;
}
```

- [ ] **Step 4: Branch in `main_screen.dart` + reconnect with password re-prompt**

In `_buildForeground` (now typed `AppSession?` from Task 11), before the existing terminal path:

```dart
if (active is RdpSession) {
  return RdpWorkspace(
    session: active,
    onReconnect: () => _retryRdp(active),
  );
}
```

`_retryRdp` in `MainScreen` implements the spec's "Retry re-prompts for the password" on auth failure:

```dart
Future<void> _retryRdp(RdpSession old) async {
  final provider = context.read<SessionProvider>();
  if (old.status == RdpSessionStatus.error) {
    // Likely auth failure — re-prompt and persist before reconnecting.
    final newPassword = await showDialog<String>(
      context: context,
      builder: (_) => _RdpPasswordDialog(host: old.host), // small TextField
                       // dialog; follow sudo_password_dialog.dart's style
    );
    if (newPassword == null) return; // cancelled
    await context.read<StorageService>().savePassword(old.host.id, newPassword);
  }
  await provider.reconnectRdp(old);
}
```

`SessionProvider.reconnectRdp(RdpSession old)`: carry over tab metadata, then reuse `connectRdp`:

```dart
Future<void> reconnectRdp(RdpSession old) async {
  final (label, color, pinned) = (old.customLabel, old.colorTag, old.isPinned);
  await closeSession(old.id); // existing close path → old.close()
  final fresh = await connectRdp(old.host);
  if (fresh != null) {
    fresh.customLabel = label;
    fresh.colorTag = color;
    fresh.isPinned = pinned;
    notifyListeners();
  }
}
```

(Adapt `closeSession`/`StorageService.savePassword` to real names.)

- [ ] **Step 5: Run tests + analyze; commit**

Run: `flutter test && flutter analyze`
Expected: green, including the new widget test, zero analyzer warnings.

```bash
git add -A app/lib app/test
git commit -m "feat(rdp): RdpWorkspace screen rendering and input capture (#44)"
```

### Task 16: Host form protocol selector + RDP badge

**Files:**
- Modify: `app/lib/widgets/add_host_dialog.dart`, `app/lib/widgets/host_list.dart`, `app/lib/widgets/hosts_dashboard.dart`, `app/lib/widgets/host_detail_panel.dart`
- Test: `app/test/widgets/add_host_dialog_rdp_test.dart`

- [ ] **Step 0: Read the real dialog first**

`add_host_dialog.dart` pops a record `(host: host, password: _password.text)` (~line 66) and **must keep that return shape** — the existing `add_host_dialog_sftp_test.dart` destructures `({Host host, String password})`. Also note: the dialog has **no jump-host picker today** (`jumpHostId` is edited elsewhere — check `host_detail_panel.dart`); for RDP an "SSH tunnel via" dropdown must be **added**, not "kept".

- [ ] **Step 1: Write the failing test**

Mirror the pump/build setup of the existing `add_host_dialog_sftp_test.dart`:

```dart
testWidgets('selecting RDP hides SSH-only fields and shows domain', (tester) async {
  // pump AddHostDialog exactly like add_host_dialog_sftp_test.dart does,
  // tap the protocol segmented control "RDP", then:
  // expect: auth-type dropdown gone (password field stays),
  //         "Domain (optional)" field visible,
  //         port field text == '3389' (when untouched),
  //         shell-integration / SFTP-mode controls absent,
  //         "SSH tunnel via" dropdown visible.
  // Submit and destructure the popped ({Host host, String password}) record;
  // expect host.protocol == HostProtocol.rdp and host.domain to round-trip.
});
```

- [ ] **Step 2: Implement the form changes**

In `add_host_dialog.dart`:
- Add a `SegmentedButton<HostProtocol>` at the top (`SSH` / `RDP`), state-held like neighbors.
- When `HostProtocol.rdp`: default port field to 3389 (only if untouched), force `AuthType.password` and hide the auth-type selector, key/cert/agent pickers, shell-integration toggle, SFTP mode, auto-record; show a `Domain (optional)` text field and an `RDP security` dropdown (`auto`/`nla`/`tls`); add an "SSH tunnel via" dropdown listing saved SSH hosts (writes `jumpHostId`).
- Thread `protocol`/`domain`/`rdpSecurity`/`jumpHostId` into the `Host(...)` constructed in `_submit`, preserving the popped record shape.

In `host_list.dart` / `hosts_dashboard.dart` / `host_detail_panel.dart`: where the host card/row renders the OS icon or port info, add a small "RDP" chip when `host.protocol == HostProtocol.rdp` (follow the existing badge/chip styling, e.g. the connection-health badge pattern). In `host_detail_panel.dart`, hide SSH-only sections for RDP hosts.

- [ ] **Step 3: Run tests + analyze; commit**

Run: `flutter test && flutter analyze`
Expected: green.

```bash
git add -A app/lib app/test
git commit -m "feat(rdp): host form protocol selector, RDP fields and badges (#44)"
```

### Task 17: Server certificate TOFU

**Files:**
- Modify: `app/lib/models/known_host.dart`, `app/lib/providers/known_hosts_provider.dart`, `app/lib/widgets/known_hosts_screen.dart`
- Modify: `app/lib/providers/session_provider.dart` (gate Connected on pin check)
- Test: `app/test/providers/known_hosts_rdp_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/providers/known_hosts_provider.dart';

void main() {
  test('rdp pin: first sight pends, accept stores, mismatch challenges', () async {
    final p = KnownHostsProvider(/* construct as existing tests do */);
    final v1 = p.verifyRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'aa');
    expect(v1, RdpCertVerdict.unknown);
    await p.acceptRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'aa');
    expect(p.verifyRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'aa'),
        RdpCertVerdict.trusted);
    expect(p.verifyRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'bb'),
        RdpCertVerdict.mismatch);
  });
}
```

- [ ] **Step 2: Implement**

- `KnownHost` model: add `protocol` field (`'ssh'` default, `'rdp'`), serialized additively. **Careful:** `KnownHost.fromJson` currently uses strict `as String` casts — the new field needs `json['protocol'] as String? ?? 'ssh'`. RDP entries store the cert fingerprint in the existing fingerprint field and use an empty-string sentinel for `keyType`; the SSH `verifyHostKey`/`_matches` path must filter `protocol == 'ssh'` so RDP rows never collide with SSH lookups.
- `KnownHostsProvider`:

```dart
enum RdpCertVerdict { trusted, unknown, mismatch }

RdpCertVerdict verifyRdpCert({required String host, required int port, required String fingerprint}) {
  final entry = entries.where((e) =>
      e.protocol == 'rdp' && e.host == host && e.port == port).firstOrNull;
  if (entry == null) return RdpCertVerdict.unknown;
  return entry.fingerprint == fingerprint
      ? RdpCertVerdict.trusted : RdpCertVerdict.mismatch;
}

Future<void> acceptRdpCert({required String host, required int port, required String fingerprint}) async {
  // upsert an entry with protocol 'rdp' and persist via the existing save
  // path (adapt entries/save names to the real provider)
}
```

- Flow in `connectRdp` (Task 13): on `RdpEvent.Connected`, call `verifyRdpCert`. `trusted` → continue. `unknown` → show a TOFU dialog (fingerprint + subject + Accept/Reject; mirror the SSH `pendingChallenge` dialog style); Accept stores the pin, Reject disconnects. `mismatch` → red warning dialog ("certificate changed"), default action disconnect.

Note the v1 trade-off in a code comment: verification happens after the TLS handshake on first connect; the pin protects subsequent connects.

- `known_hosts_screen.dart`: render RDP entries with an "RDP" chip (same chip style as Task 16).

- [ ] **Step 3: Run + commit**

Run: `flutter test && flutter analyze`
Expected: green.

```bash
git add -A app/lib app/test
git commit -m "feat(rdp): TOFU certificate pinning in known hosts (#44)"
```

### Task 18: Feature exclusions for RDP tabs

**Files:**
- Modify: `app/lib/screens/main_screen.dart` (hotkey handlers for `split_horizontal` / `split_vertical` / `toggle_input_bar`), `app/lib/widgets/record_button.dart` wiring, `TerminalLayoutProvider.toggleSnippetsPanel()` trigger sites, and any split-layout toolbar/menu entry points (grep for `setSplitLayout` / `TerminalLayout` usages — hotkeys are not the only path)
- Test: extend `app/test/providers/session_provider_app_session_test.dart`

- [ ] **Step 1: Guard each terminal-only affordance**

Per spec these are disabled/hidden when the active tab is an RDP session: session recording, split view, input bar, snippets panel. Pattern at every call site:

```dart
final active = context.watch<SessionProvider>().activeSession;
final isTerminal = active is TerminalSession;
// hide or disable the affordance when !isTerminal
```

Task 11's analyzer pass already fixed the type errors — this step is about UX (hide/disable), which the type system does not enforce; walk each affordance manually.

- [ ] **Step 2: Add a regression test**

```dart
test('terminal-only affordances are gated on TerminalSession', () {
  // with an RdpSession active: SessionProvider.activeSshSession is null,
  // and activeSession is not a TerminalSession
});
```

- [ ] **Step 3: Run + commit**

Run: `flutter test && flutter analyze`
Expected: green.

```bash
git add -A app/lib app/test
git commit -m "feat(rdp): gate terminal-only features off RDP tabs (#44)"
```

### Task 19: CI — build, test, and bundle the native library

**Files:**
- Modify: `.github/workflows/release.yml`, `.github/workflows/pr-test.yml`

**Context the executor must know:** `release.yml` builds a matrix that includes **arm64 Windows (`windows-11-arm`) and arm64 Linux (`ubuntu-24.04-arm`)** alongside x64 — every matrix job needs the Rust build, and the build scripts compile for the runner's native arch (no cross-compilation). There is **no existing native-lib bundling precedent** in the workflow (the QuickJS dylib is not bundled today) — the bundling steps below are designed from scratch, not copied.

- [ ] **Step 1: Add Rust build to every `release.yml` matrix job**

Before the `flutter build` step of each OS job:

```yaml
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
        with:
          workspaces: packages/yourssh_rdp/rust
      - name: Build yourssh_rdp native library
        run: packages/yourssh_rdp/build.sh        # build.ps1 on Windows jobs
```

- [ ] **Step 2: Bundle the library into each artifact**

After `flutter build`, before packaging/signing:

- **macOS** (arm64): copy into the app bundle and sign it with the same identity the workflow uses for the app, **before** the final app codesign/notarization step so the seal stays valid:

```yaml
      - name: Bundle RDP library
        run: |
          cp packages/yourssh_rdp/assets/native/macos/libyourssh_rdp.dylib \
             app/build/macos/Build/Products/Release/YourSSH.app/Contents/Frameworks/
          codesign --force --options runtime --sign "$MACOS_SIGN_IDENTITY" \
             app/build/macos/Build/Products/Release/YourSSH.app/Contents/Frameworks/libyourssh_rdp.dylib
```

  (Slot into the existing signing flow — reuse the workflow's existing identity variable/step names.)

- **Linux** (both arches): copy `libyourssh_rdp.so` into the bundle's `lib/` directory (next to the other bundled `.so` files under `app/build/linux/<arch>/release/bundle/lib/`).
- **Windows** (both arches): copy `yourssh_rdp.dll` next to `yourssh.exe` in `app/build/windows/<arch>/runner/Release/`.

These three locations are exactly the release-bundle candidates the Task 2 loader checks first.

- [ ] **Step 3: Add Rust + package tests to `pr-test.yml`**

`pr-test.yml` currently runs `flutter test` only in `app/` — the new package's Dart tests and the Rust tests need explicit steps. The FRB roundtrip test loads the dylib, so build it first:

```yaml
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
        with:
          workspaces: packages/yourssh_rdp/rust
      - name: Rust tests (yourssh_rdp)
        run: cargo test --manifest-path packages/yourssh_rdp/rust/Cargo.toml
      - name: Build RDP native library for Dart tests
        run: packages/yourssh_rdp/build.sh
      - name: Dart tests (yourssh_rdp)
        working-directory: packages/yourssh_rdp
        run: flutter test
```

- [ ] **Step 4: Validate + commit**

Push a branch and confirm both workflows pass end-to-end (this is the only real validation for CI changes).

```bash
git add .github/workflows
git commit -m "ci(rdp): build, test, and bundle yourssh_rdp native library (#44)"
```

### Task 20: Manual verification matrix + docs

**Files:**
- Modify: `CLAUDE.md` (architecture entries), `README.md` (feature list), `CHANGELOG.md` ([Unreleased])

- [ ] **Step 1: Manual verification checklist (run on at least macOS + one more OS)**

| # | Check | Target |
|---|---|---|
| 1 | Direct connect, NLA, correct password → desktop renders | Windows 11 VM |
| 2 | Wrong password → error overlay; Retry re-prompts password; correct entry connects | Windows 11 VM |
| 3 | Connect via SSH tunnel (jump host) → desktop renders; killing SSH shows "SSH tunnel closed" | Windows VM behind SSH |
| 4 | xrdp container, TLS mode → desktop renders | `docker run -p 3389:3389 danielguerra/ubuntu-xrdp` or similar |
| 5 | Typing (letters, shortcuts Ctrl+C/V inside remote, arrows, F-keys) | both |
| 6 | Mouse move/click/right-click/scroll, coordinates correct when window resized | both |
| 7 | Ctrl+Alt+Del toolbar button opens the secure screen | Windows VM |
| 8 | Clipboard: copy remote → paste local; copy local → focus RDP → paste remote | both |
| 9 | TOFU dialog on first connect; no dialog on second; mismatch warning when server cert changes | both |
| 10 | Tab behavior: rename, pin, color survive reconnect; next/prev hotkeys; recording/split/input-bar/snippets hidden | both |
| 11 | Close tab → no leaked sockets (check `lsof -p <pid> \| grep 3389`) | macOS |

- [ ] **Step 2: Update docs**

- `CLAUDE.md`: add `yourssh_rdp` to the monorepo layout, `RdpSession`/`AppSession` to models, `RdpTunnelProxy` to services, and remove the stale `core/` + Makefile section (it no longer exists).
- `README.md`: add Remote Desktop (RDP) to the feature list.
- `CHANGELOG.md`: add the feature under `[Unreleased]`.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md README.md CHANGELOG.md
git commit -m "docs(rdp): document in-app RDP client (#44)"
```

- [ ] **Step 4: Close the loop on GitHub**

Per the project's issue workflow: after the PR lands, label/type/priority issue #44, link the commits, and comment in Vietnamese summarizing what shipped and what's deferred (audio, drive redirect, dynamic resize).

---

## Plan self-review notes

- **Spec coverage:** package+FRB (T1–2), connection/TLS/NLA + cert event (T4), framebuffer dirty regions (T5), input (T6, T14), clipboard both directions incl. focus-gain push (T7, T13, T15), panic guard (T8), Dart facade + resolution rules (T9), Host fields (T10), AppSession split incl. main_screen retyping (T11), RdpSession + "SSH tunnel closed" message (T12), tunnel proxy + connect flow + workspace-size callback + tab metadata (T13), workspace UI + Ctrl+Alt+Del + Retry-with-reprompt (T15), host form/badges + tunnel picker (T16), TOFU (T17), feature exclusions (T18), CI incl. arm64 + bundling (T19), manual matrix + docs (T20). No auto-reconnect, audio, dynamic resize, Pause key — out of scope per spec / documented limitation.
- **Reviewed:** this plan incorporated a two-agent adversarial review (consistency-vs-spec + technical correctness, verified against docs.rs/FRB docs/the dartssh2 fork). Key corrections applied: session id via `RdpEvent::Started` (FRB #2233), `connect_finalize` NetworkClient requirement, exhaustive `connector::Config`, `process_fastpath_input(image, events)` shape, 12-method `CliprdrBackend`, `StreamSink` import path, `TunnelEnd.sink` as `StreamSink<List<int>>` + `destroy()`, ironrdp version line 0.15, Pause key dropped, arm64 CI matrix + from-scratch bundling, Retry password re-prompt, tab-metadata carry-over.
- **Known reality-contact points (expected, not placeholders):** exact ironrdp API names (Tasks 4–7) must be aligned with the pinned version using the `ironrdp-client` example as reference; FRB generated names for `RdpEvent` variants (record them in Task 3 Step 4); existing constructor/field names in `SessionProvider`/`StorageService`/`KnownHostsProvider` (Tasks 11, 13, 17).
