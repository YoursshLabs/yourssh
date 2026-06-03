# Sudo SFTP — Design

**Date:** 2026-06-03
**Status:** Approved

## Problem

SFTP sessions run as the login user. To place files in root-owned locations
(`/etc`, `/var/www`, ...) users must upload to a temp directory, then manually
`sudo cp` over SSH. WinSCP solves this by running the SFTP server binary through
`sudo` over an exec channel instead of requesting the `sftp` subsystem. yourssh
controls a local dartssh2 fork, so it can do the same.

## Goals

- Per-host option to run the whole SFTP session as root (or any custom command).
- Works with `NOPASSWD` sudoers entries **and** password-protected sudo.
- Applies to every SFTP consumer of that host: SFTP panel, transfers, file ops,
  path autocomplete, JS plugin bridge (single chokepoint: `SshService.openSftp`).
- Clear, actionable errors. No silent fallback to the non-elevated subsystem.

## Non-goals

- Per-session elevate/de-elevate toggle in the SFTP panel (host-level only).
- Servers using `internal-sftp` with no on-disk binary (documented limitation;
  surfaced via the `binaryNotFound` error).
- Syncing the sudo password (consistent with existing `pw_` secrets).

## Key constraints discovered in code

- `SftpClient`'s constructor sends the SFTP INIT packet immediately
  (`_startHandshake()` in `packages/dartssh2/lib/src/sftp/sftp_client.dart`),
  so any password bytes must be written to the channel **before** construction.
- If sudo does **not** need a password (NOPASSWD / cached timestamp), it never
  reads stdin — a blindly written password line would reach `sftp-server` as
  garbage and corrupt the protocol. Password feeding must therefore be
  conditional, never speculative.
- `SshService.openSftp(host)` is the single entry point for all SFTP usage in
  the app, so a host-level setting naturally covers every consumer.

## Design

### 1. dartssh2 fork — mechanism only

New method on `SSHClient` next to `sftp()`:

```dart
Future<SftpClient> sftpOnExec(String command, {Uint8List? stdinPreamble}) async {
  await _authenticated.future;
  final channelController = await _openSessionChannel();
  if (!await channelController.sendExec(command)) {
    channelController.close();
    throw SSHChannelRequestError('Failed to start sftp server command');
  }
  // write stdinPreamble (if any) to the channel sink before the SFTP
  // handshake starts
  return SftpClient(channelController.channel, printDebug: ..., printTrace: ...);
}
```

No sudo knowledge in the fork. `stdinPreamble` is generic "bytes written before
the protocol starts".

### 2. Host model

- New enum: `SftpMode { normal, sudo, custom }`.
- New `Host` fields:
  - `sftpMode` (`SftpMode`, default `normal`) — JSON key `sftpMode`, absent →
    `normal` (backward compatible; Supabase sync carries it automatically).
  - `sftpServerCommand` (`String?`) — only meaningful when `sftpMode == custom`.
    Nullable `copyWith` handling follows the existing `_Unset` pattern used by
    `jumpHostId`.

### 3. UI

- `add_host_dialog.dart`: `DropdownButtonFormField<SftpMode>` with entries
  "Default", "Sudo (root)", "Custom command", plus a conditional command
  TextField when Custom is selected — same conditional pattern as `_authType`.
- SFTP panel: small "root" chip/badge when the connected host's
  `sftpMode != normal`.

### 4. Orchestration — `app/lib/services/sudo_sftp.dart` (new)

Follows the `ShellIntegrationService` pure/injectable pattern.

**Pure helpers** (unit-testable without IO):

- `kSftpServerPaths`: `/usr/lib/openssh/sftp-server` (Debian/Ubuntu),
  `/usr/libexec/openssh/sftp-server` (RHEL/Fedora), `/usr/lib/ssh/sftp-server`
  (Arch/SUSE).
- Command builders: path probe (single exec that echoes the first executable
  path), `sudo -n <path>` runner, `sudo -S -p '' -v` validator.
- `classifySudoFailure(stderr, exitCode)` → failure reason enum.

**`SudoSftpOrchestrator`** — constructor-injected effects so tests use fakes:

- `runExec(String cmd)` → `(stdout, stderr, exitCode)`
- `runExecWithStdin(String cmd, List<int> stdin)` → exit code (writes stdin,
  closes it, awaits exit — closing stdin prevents sudo from hanging on a
  re-prompt after a wrong password)
- `openSftpExec(String cmd, {Uint8List? stdinPreamble})` → `SftpClient`
- `getSudoPassword(Host host, {required bool interactive})` → `String?`

Flow (sudo mode):

```
1. Probe sftp-server path via exec; none found → SudoSftpException(binaryNotFound).
2. Try openSftpExec("sudo -n <path>"); handshake OK → done
   (NOPASSWD or cached sudo timestamp).
3. Handshake failed → password path:
   a. getSudoPassword(...): login password (AuthType.password) → stored
      `sudopw_<hostId>` secret → interactive prompt dialog. None available →
      SudoSftpException(passwordRequired / userCancelled).
   b. Validate separately: runExecWithStdin("sudo -S -p '' -v", password + "\n").
      exit 0 → password correct AND sudo timestamp now cached.
      exit ≠ 0 → classify stderr → wrongPassword / notInSudoers / requiresTty.
   c. Retry openSftpExec("sudo -n <path>") — normally succeeds via cached
      timestamp.
   d. If (c) still fails (timestamp_timeout=0): open
      openSftpExec("sudo -S -p '' <path>", stdinPreamble: password + "\n").
      Safe: step (b) proved sudo will consume exactly one stdin line here.
```

Flow (custom mode): run `sftpServerCommand` verbatim via openSftpExec (no path
probe). If the command starts with `sudo ` and the direct start fails, run the
same validate step (3a/3b) first, then retry verbatim. If that still fails,
surface the classified error (the message recommends a NOPASSWD sudoers entry).

Probes and validation execs call `SSHClient.execute()` directly, **bypassing
the plugin HookBus** — no sudo metadata leaks to JS plugins, and the password
itself only ever travels via stdin, never inside a command string.

### 5. `SshService` integration

- `openSftp(Host host, {bool interactive = true})`:
  - `normal` → existing `client.sftp()`.
  - `sudo` / `custom` → delegate to `SudoSftpOrchestrator`.
- `listDirectory` (autocomplete cache) passes `interactive: false` — it never
  pops a dialog and keeps its existing never-throws contract.
- New callback field wired in `main.dart` (same pattern as the host-key
  verifier and key lookup): `Future<String?> Function(Host host)?
  sudoPasswordPrompt` backing the interactive branch of `getSudoPassword`.

### 6. Password storage

- Secret key: `sudopw_<hostId>` via existing
  `StorageService.saveGenericSecret` / `loadGenericSecret` /
  `deleteGenericSecret` (secure-first strategy applies automatically).
- Prompt dialog (new widget, e.g. `sudo_password_dialog.dart`): password field +
  "Remember" checkbox → saves the secret on success.
- Deleting a host should delete its `sudopw_` secret alongside `pw_`.

### 7. Error handling

`SudoSftpException implements Exception` with:

- `reason`: `binaryNotFound`, `sudoNotInstalled`, `notInSudoers`,
  `wrongPassword`, `requiresTty`, `passwordRequired`, `userCancelled`,
  `handshakeFailed`.
- A user-facing message including a copyable fix where applicable, e.g.:

```
user ALL=(root) NOPASSWD: /usr/lib/openssh/sftp-server
```

No automatic fallback to the plain subsystem — the user explicitly chose
elevation; failing loudly avoids confusing permission errors later.

### 8. Tests

`app/test/services/sudo_sftp_test.dart` (orchestrator with fakes + pure helpers):

- NOPASSWD: direct `sudo -n` start succeeds, no password requested.
- Password flow: validate → cached-timestamp retry succeeds.
- Wrong password: validator exit ≠ 0 → `wrongPassword`, no SFTP channel opened.
- `timestamp_timeout=0`: retry fails → inline `stdinPreamble` start.
- Binary missing → `binaryNotFound`.
- Custom command passthrough (verbatim, no path probe).
- Non-interactive (`interactive: false`) with no stored password →
  `passwordRequired`, no prompt invoked.
- `Host` JSON round-trip for the new fields; absent keys → `normal`.

Fork test (`packages/dartssh2/test/src/sftp/`): `sftpOnExec` sends an exec
request (not a subsystem request) and writes the preamble before the client's
INIT packet — added alongside the existing `sftp_client_test.dart` suite.

## Decisions log

- Config shape: dropdown of three modes (Default / Sudo auto-detect / Custom
  command) — chosen over a bare toggle or free-text-only.
- Failure behavior: loud, actionable error; no silent fallback.
- Scope: host-level setting applies to all SFTP consumers of that host.
- Password support: yes — `sudo -S` with separate `-v` validation; NOPASSWD
  remains the recommended setup and is what error messages suggest.
