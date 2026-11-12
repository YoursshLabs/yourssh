# Fix plan (Critical/High + #13 #14 #17 done 2026-11-12 — remaining: Medium/Low)

1. Sync RLS + key separation + confirm-before-apply (finding 1). Needs a migration and a payload format bump.
2. Share-session input gate + join approval (2).
3. Host-key checks: key-type downgrade, testConnection verifier, fail-closed defaults (3, 4).
4. SFTP filename sanitising helper used by every download/temp path (5); add tests with `../`, `/abs`, `a/..`.
5. Plugin panel permission checks (7) + JS interrupt/memory limits (15).
6. RDP pre-CredSSP TOFU gate in Rust (6).
7. `cargo update` for rustls / rustls-webpki / h2 / tokio; re-run `cargo test`.
8. Medium/Low items in batches; CI: pin actions by SHA, per-job permissions, publish SHA256SUMS, add VNC build to release.

Each fix: failing test first, then code (repo has extensive `app/test`). Requires Flutter SDK to run `flutter test`.
