# Changelog

- 2026-11-12 — Audit run: gitleaks (clean), OSV deps scan, cargo tests (RDP 12/12, VNC 9/9), 5-area static review. Findings recorded in `findings.md`. No source changes.
- 2026-11-12 — Branch `fix/security-critical-high` (uncommitted). Fixed, each with tests written first:
  - #1 sync: row id = `SyncCode.rowId` (SHA-256 of code), legacy row fallback + cleanup, anti-rollback on inner `updated_at` (`sync_last_applied_at`).
  - #2 share: E2E AES-GCM envelopes + hashed channel from an 80-bit `ROOM-SECRET` code (`share_crypto.dart`); host applies input only from the controlling guest; targeted rejections.
  - #3/#4 host keys: new key type for a pinned endpoint raises a challenge; `testConnection` verifies target + hops, fail-closed; `connect`/`dialHop` reject when no verifier.
  - #5 SFTP: `util/safe_local_path.dart` guards every remote-name → local-path sink; dir download depth cap 64.
  - #6 RDP: unpinned hosts probe with `kRdpUnpinnedProbe` → first-use dialog before CredSSP → reconnect with the pin.
  - #7 plugins: panel native messages enforce `ssh.exec` / `session.observe` / `sftp.read`.
  - #13 update: macOS installer must carry a Developer ID signature by team 84T567KMYD (`verifyMacInstallerSignature`); quarantine strip removed.
  - #14 CI: actions pinned by SHA, read-only token except the `release` job, macOS Developer ID signing + notarization (secrets-gated), VNC lib built/bundled on all desktop platforms.
  - #17 Rust deps bumped (rustls 0.23.46, rustls-webpki 0.103.16, h2 0.4.20, tokio 1.54.1, anyhow 1.0.104, …); only `rsa` (no fix) + unmaintained notices remain.
  - Verification: app `flutter test` 1805 pass / 1 skip (baseline 1720 / 1), script engine 43/43, cargo RDP 12/12 + VNC 9/9, `flutter analyze` adds no new issues vs baseline, actionlint clean for new steps.
