# Known Hosts — Design Spec

**Date:** 2026-05-29  
**Status:** Approved

## Problem

- `SshService.connect()` hardcodes `onVerifyHostKey: (type, fingerprint) => true` — every host key is blindly trusted.
- `NavSection.knownHosts` renders `_ComingSoon` — there is no UI.
- No model, no storage, no verification logic exists.

## Goals

1. Trust-on-first-use (TOFU): save fingerprint silently on first connect.
2. Reject changed host keys and show a blocking dialog with Trust / Cancel.
3. Provide a Known Hosts screen to list and delete saved entries.

## Architecture

The challenge is showing a Flutter dialog from within `SshService`, which has no `BuildContext`. The solution is a **Completer bridge** in `KnownHostsProvider`:

```
SSHClient.onVerifyHostKey (async callback)
    │  calls
    ▼
KnownHostsProvider.verifyHostKey(host, port, keyType, fingerprint)
    │  key unknown  →  save, return true
    │  key matches  →  return true
    │  key mismatch →  create HostKeyChallenge (Completer<bool>)
    │                  notifyListeners()
    ▼
MainScreen Consumer detects pendingChallenge
    │  shows dialog (Trust / Cancel)
    │  user responds
    ▼
challenge.resolve(bool)
    │  if true  →  update stored entry
    ▼
Completer completes → bool returned to dartssh2
```

## Data Model

### `KnownHost`

```dart
class KnownHost {
  final String host;         // hostname / IP
  final int port;            // SSH port
  final String keyType;      // e.g. "ecdsa-sha2-nistp256"
  final String fingerprint;  // hex bytes joined by ':', e.g. "ab:cd:ef:..."
  final DateTime addedAt;
}
```

Lookup key: `"$host:$port:$keyType"`

Fingerprint encoding: raw bytes from `onVerifyHostKey` converted to lowercase hex octets separated by `:`.

### `HostKeyChallenge`

```dart
class HostKeyChallenge {
  final String host;
  final int port;
  final String keyType;
  final String oldFingerprint;
  final String newFingerprint;
  // internal Completer<bool>
}
```

Expose `resolve(bool trust)` and `Future<bool> get result`.

## Storage

Key in `SharedPreferences`: `yourssh.known_hosts` (JSON array, same pattern as hosts).

New methods on `StorageService`:

| Method | Description |
|---|---|
| `loadKnownHosts()` | Deserialise list from prefs |
| `saveKnownHosts(List<KnownHost>)` | Serialise and write |

`KnownHostsProvider` owns the list in memory and calls `saveKnownHosts` on every mutation.

## Provider: `KnownHostsProvider`

```
KnownHostsProvider(StorageService)
  List<KnownHost> hosts          // read-only view for UI
  HostKeyChallenge? pendingChallenge  // non-null → dialog must show

  Future<void> load()
  Future<void> remove(KnownHost)
  Future<bool> verifyHostKey(String host, int port, String keyType, Uint8List fp)
```

`verifyHostKey` is the single entry-point for SSH verification logic:
- Unknown key → add + return true
- Known, matching → return true
- Known, mismatched → set `pendingChallenge`, notify, await `challenge.result`, clear `pendingChallenge`, notify; if result is `true` remove old entry and insert new one (same host/port/keyType, new fingerprint + `addedAt`), return result

## SshService changes

`connect()` gains an optional parameter:

```dart
Future<SSHClient> connect(
  Host host, {
  SshKeyEntry? keyEntry,
  Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
})
```

`onVerifyHostKey` callback:
```dart
onVerifyHostKey: (type, fp) async {
  if (verifyHostKey != null) return verifyHostKey(type.name, fp);
  return true; // fallback: trust (used in tests / local terminal)
}
```

## SessionProvider changes

Add one callback field:

```dart
Future<bool> Function(String host, int port, String keyType, Uint8List fp)? hostKeyVerifier;
```

`_doConnect` passes it to `_ssh.connect()`:

```dart
verifyHostKey: hostKeyVerifier != null
  ? (keyType, fp) => hostKeyVerifier!(host.host, host.port, keyType, fp)
  : null,
```

## Wiring in `main.dart`

```dart
late final KnownHostsProvider _knownHostsProvider;

// initState:
_knownHostsProvider = KnownHostsProvider(_storage);
_knownHostsProvider.load();
_sessionProvider.hostKeyVerifier = _knownHostsProvider.verifyHostKey;

// MultiProvider:
ChangeNotifierProvider.value(value: _knownHostsProvider),
```

## MainScreen changes

1. Add `NavSection.knownHosts => const KnownHostsScreen()` to the switch.
2. Wrap body in a `Consumer<KnownHostsProvider>` that watches `pendingChallenge`. When non-null, schedule `_showHostKeyDialog` via `addPostFrameCallback`.

Dialog content:
- Warning icon
- "Host key changed for `host:port`"
- Key type + old fingerprint vs new fingerprint (monospace)
- Buttons: **Cancel** (returns false) and **Trust new key** (returns true, destructive style)

## Known Hosts Screen

`KnownHostsScreen` is a `StatefulWidget`. `initState` calls `provider.load()` to refresh from storage.

Table columns: **Host**, **Port**, **Key Type**, **Fingerprint** (truncated to first 3 octets + `…`), **Added**, **Delete** (icon button).

Empty state: icon + "No known hosts yet. Connect to a server to add one."

Matches existing dark theme (`AppColors`), same card/table style as `KeychainScreen`.

## Error Handling

- If `resolve(false)` → dartssh2 receives `false` → throws `SSHHandshakeError` → `SessionProvider` catches it → `session.errorMessage = e.toString()`. The error is visible in the session tile.
- If `KnownHostsProvider` fails to save (storage error) → log and continue (TOFU succeeds in-memory for current session, retried on next load).

## Out of Scope

- Importing / exporting `~/.ssh/known_hosts` files.
- Per-host "trust once vs trust always" distinction.
- Ed25519 vs RSA key-type disambiguation in display (shown as raw type string).
