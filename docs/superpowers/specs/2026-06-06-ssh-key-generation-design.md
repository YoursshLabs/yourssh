# In-app SSH Key Generation — Design

**Date:** 2026-06-06
**Status:** Approved

## Problem

The Keychain screen already has a Generate panel, but it is incomplete and
partly wrong:

- The dropdown says "RSA 4096" yet never passes `-b 4096` — ssh-keygen
  silently generates a 3072-bit key.
- Everything depends on the system `ssh-keygen` binary; on Windows without
  the optional OpenSSH Client feature, generation fails with a raw error.
- There is no way to copy or export the public key — the roadmap item's
  core ask.
- The passphrase typed at generation time is not saved to secure storage
  (`pp_<keyId>`), so the key prompts again on first use.
- No deploy story: getting the new public key onto a server is manual.

## Goals

- **Ed25519 generated pure-Dart, always** — no external binary for the
  recommended default: 32 random bytes (`Random.secure`) → pinenacl
  `SigningKey` → the dartssh2 fork's `OpenSSHEd25519KeyPair` → OpenSSH PEM.
- **RSA 4096 / ECDSA P-256 via ssh-keygen**, with the `-b` flags actually
  passed; both options disabled (with a "requires OpenSSH client" hint)
  when a startup probe finds no `ssh-keygen`.
- **Encrypted OpenSSH PEM encoding in the dartssh2 fork** —
  `toPem({String? passphrase})`: bcrypt-pbkdf (16 rounds) + aes256-ctr,
  reusing the primitives the decrypt path already has. Null passphrase
  stays byte-identical to today's unencrypted output.
- **Copy public key** from each key tile (hover icon) and from the
  Generate panel's success state.
- **Passphrase saved** to secure storage as `pp_<keyId>` on successful
  generation.
- **Deploy to host…** — ssh-copy-id-style: pick a saved host, append the
  public key to `~/.ssh/authorized_keys` over SSH exec (duplicate-safe).
- Generated private keys get mode 600 on macOS/Linux.

## Non-goals

- ECDSA curve selection (P-256 fixed) and RSA bit selection (4096 fixed).
- Pure-Dart RSA/ECDSA generation (pointycastle 4096-bit RSA takes tens of
  seconds in Dart).
- FIDO2 / `sk-ssh-ed25519` keys (separate roadmap item).
- Exporting the private key elsewhere (the file already lives on disk at a
  visible path).
- Windows ACL tightening for the key file.
- Deploying to hosts not saved in the app.

## Components

### KeyGenService (`app/lib/services/key_gen_service.dart`, new)

- `Future<GeneratedKey> generateEd25519({required String name, String passphrase = '', required String dir})`
  — seeds pinenacl, builds `OpenSSHEd25519KeyPair(publicKey, privateKey,
  comment: name)`, writes `<dir>/<safeName>` (PEM via
  `toPem(passphrase: …)`) and `<dir>/<safeName>.pub`
  (`ssh-ed25519 <base64> <name>`), then `chmodLocal(path, 0o600)` on
  macOS/Linux. Returns the paths + public key line.
- `Future<GeneratedKey> generateWithSshKeygen({required String type, required String name, String passphrase = '', required String dir})`
  — current Process.run flow plus `-b 4096` (rsa) / `-b 256` (ecdsa);
  non-zero exit throws with stderr.
- `Future<bool> probeSshKeygen()` — runs `ssh-keygen -?` (any exit code
  counts as present; only a ProcessException means missing); result cached.
- Pure helpers (separately unit-testable): `sanitizeKeyName`,
  `buildPublicKeyLine(publicKeyBytes, comment)`.

### dartssh2 fork — encrypted encoder

`OpenSSHKeyPair.toPem({String? passphrase})` and a parallel
`OpenSSHKeyPairs.encrypted(...)` factory:

- null/empty passphrase → existing unencrypted output, byte-identical.
- otherwise: 16-byte random salt, `bcrypt_pbkdf(passphrase, salt,
  rounds: 16)` derives key+IV for `aes256-ctr`, private blob padded to the
  cipher block then encrypted; `cipherName/kdfName/kdfOptions` set so the
  existing decrypt path (`SSHKeyPair.fromPem(pem, passphrase)`) reads it
  back. Round-trip is the acceptance test.

### KeyProvider (`app/lib/providers/key_provider.dart`)

- `addKeyFromFile` returns the created `SshKeyEntry` (currently void) so
  the panel can store the passphrase under `pp_<entry.id>` via
  `StorageService.savePassphrase` — the same store
  `loadKeychainKeyPairs` already reads, so the key works without
  re-prompting.

### Generate panel (`keychain_screen.dart`)

- Algorithm dropdown: `Ed25519 (recommended)` / `RSA 4096` /
  `ECDSA P-256`; the last two disabled with helper text
  "requires OpenSSH client (ssh-keygen)" when the probe fails.
- Ed25519 routes to `generateEd25519`; rsa/ecdsa to
  `generateWithSshKeygen`.
- Success state replaces the form: shows the public key (selectable,
  monospace) with **Copy public key** and **Done** — the panel no longer
  closes before the user can grab the key.
- Raw SnackBars → `AppSnack`.

### Key tile (`keychain_screen.dart`)

- Hover actions gain **copy public key** (Clipboard + AppSnack
  confirmation; hidden when `publicKey` is empty) and
  **Deploy to host…**.

### Deploy dialog (`app/lib/widgets/deploy_key_dialog.dart`, new)

- Searchable host list from `HostProvider`; one pick → runs over
  `SshService.exec` (auto-connect via `ensureClient`: stored credentials,
  jump-aware; audited with `source: app`):

  ```
  mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
  if grep -qxF '<pub>' ~/.ssh/authorized_keys 2>/dev/null; then echo EXISTS; \
  else printf '%s\n' '<pub>' >> ~/.ssh/authorized_keys && echo ADDED; fi && \
  chmod 600 ~/.ssh/authorized_keys
  ```

  `<pub>` single-quote-escaped (reuse `ShellIntegrationService.shQuote`);
  `grep -qxF` makes redeploys idempotent. Exit 0 → success AppSnack whose
  wording follows the `EXISTS`/`ADDED` marker on stdout; otherwise stderr
  in an error AppSnack.

## Error handling

- Pure-Dart path failures (disk write, chmod) surface as AppSnack errors;
  nothing is registered in KeyProvider unless both files were written.
- ssh-keygen missing at submit time (raced past the probe) → same
  disabled-hint message as an error snack.
- Deploy failures never modify local state; the dialog stays open with
  the error so the user can retry or pick another host.

## Testing

- **Fork:** encrypted toPem round-trip (encode with passphrase → fromPem →
  sign/verify), wrong passphrase throws, null passphrase byte-identical to
  the old output (regression pin).
- **KeyGenService:** generated Ed25519 PEM parses via `SSHKeyPair.fromPem`
  (with and without passphrase) and signs; `.pub` line round-trips through
  the fork's public-key decoder; `sanitizeKeyName` cases.
- **Deploy:** pure command-builder test (escaping, dedup guard) + exec
  wiring test with the existing `_ExecClient` fake pattern.
- **Widget:** probe-fail disables rsa/ecdsa options; success state shows
  the public key and Copy; tile copy action puts the key on the clipboard.
