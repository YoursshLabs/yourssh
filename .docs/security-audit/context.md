# Context

## Method
- Static review split in 5 areas (SSH core + dartssh2; secrets/sync/crypto/update; plugins/MCP/AI/devops; injection/files/terminal/listeners; RDP/VNC/native/platform/CI). Every Critical/High finding was re-read in code before being accepted.
- `gitleaks git` over all 1228 commits: 26 hits, all false positives (test fixture keys, Podfile.lock checksums, test passphrases).
- OSV.dev batch query of 580 locked packages (all `pubspec.lock` + both `Cargo.lock`).
- `cargo test`: `yourssh_rdp` 12/12 pass, `yourssh_vnc` 9/9 pass.

## Not done
- `flutter analyze` / `flutter test` — Flutter SDK not installed on this machine.
- Vendored QuickJS C sources, `vnc-rs` internals, `frb_generated.rs`.
- No dynamic testing against a malicious server.

## Threat model used
Malicious/compromised SSH/SFTP/RDP/VNC server, network MITM, holder of the Supabase anon key, LAN peer, malicious JS plugin, other local users/processes, compromised release channel.

## Key facts learned
- Cloud sync: `sync_id` (12-char code) is both the row id and the only KDF input; RLS is `using (true)` for `anon`. Payload includes every `pw_<hostId>` password.
- Known-hosts identity is `host+port+keyType`; unknown → silently added (accept-new).
- RDP pin check runs pre-CredSSP only when a pin exists; first connect has no gate.
- Plugin `PermissionGuard` covers JS bridges but not the panel `postMessage` native handlers.
