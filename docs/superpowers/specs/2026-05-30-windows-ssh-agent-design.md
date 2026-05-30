# Windows SSH Agent (Named Pipe) — Design Spec

**Date:** 2026-05-30  
**Branch:** feat/ssh-certificate-auth  
**Status:** Approved

---

## Goal

Add Windows SSH agent support so users can authenticate via the Windows OpenSSH agent (`\\.\pipe\openssh-ssh-agent`) without needing `SSH_AUTH_SOCK`. Covers Windows 10 1803+ built-in agent and compatible managers (1Password, Bitwarden, KeePassXC).

---

## Architecture

Introduce a `_AgentTransport` abstraction so `_AgentSession` is decoupled from the underlying I/O channel.

```
SystemAgentProxy
  └── _AgentSession         (SSH agent protocol: message framing)
        └── _AgentTransport (abstract)
              ├── _SocketTransport        (Unix socket — macOS/Linux, unchanged)
              └── _WindowsPipeTransport   (Win32 named pipe — Windows, new)
```

`_AgentWriter`, `_AgentReader`, `_AgentKeyPair`, `_RawBlobHostKey`, `_RawSignature` — unchanged.

---

## _AgentTransport Interface

```dart
abstract class _AgentTransport {
  void write(List<int> data);
  Stream<List<int>> get incoming;
  Future<void> close();
}
```

`_AgentSession` is refactored to take `_AgentTransport` instead of `Socket` directly.

---

## _SocketTransport

Wraps the existing `Socket`-based logic. Behaviour is identical to current `_AgentSession` internals — just moved behind the interface.

---

## _WindowsPipeTransport

**Dependency:** `win32: ^5.x` (added to `app/pubspec.yaml`).

**Connection:**
```dart
final handle = CreateFileW(
  '\\\\.\\\pipe\\openssh-ssh-agent'.toNativeUtf16(),
  GENERIC_READ | GENERIC_WRITE,
  FILE_SHARE_NONE,
  nullptr,
  OPEN_EXISTING,
  FILE_ATTRIBUTE_NORMAL,
  NULL,
);
if (handle == INVALID_HANDLE_VALUE) throw SSHAgentUnavailableException(...);
```

**Write:** Synchronous `WriteFile` — safe on main thread (named pipe writes are non-blocking for small payloads).

**Read:** Blocking `ReadFile` runs inside a `dart:isolate` `Isolate`. The isolate loops, reading chunks and sending them back to the main isolate via `SendPort`. The main `_AgentSession` buffer logic is unchanged.

**Close:** Posts a sentinel to the isolate's `ReceivePort` and calls `CloseHandle`.

---

## Connection Flow

```
SystemAgentProxy.connect()
  if Platform.isWindows:
    1. Try SSH_AUTH_SOCK (Unix socket via WSL forwarding) → success → _SocketTransport
    2. Try \\.\pipe\openssh-ssh-agent              → success → _WindowsPipeTransport
    3. Both fail → SSHAgentUnavailableException with message listing both attempted paths
  else:
    Try SSH_AUTH_SOCK → _SocketTransport (unchanged)
```

---

## Error Messages

| Condition | Message |
|---|---|
| Windows, no agent available | `"No SSH agent found. Start Windows OpenSSH Agent service or set SSH_AUTH_SOCK."` |
| Pipe exists but access denied | `"Cannot open Windows SSH agent pipe: access denied."` |
| Unix, SSH_AUTH_SOCK not set | `"SSH_AUTH_SOCK is not set"` (unchanged) |

---

## UI Changes

None. The "SSH Agent" option in `AuthType` dropdown is unchanged. On Windows, the connection silently routes through the named pipe.

---

## Files Changed

| File | Change |
|---|---|
| `app/pubspec.yaml` | Add `win32: ^5.x` |
| `app/lib/services/system_agent_proxy.dart` | Refactor: add `_AgentTransport`, `_SocketTransport`, `_WindowsPipeTransport`; update `connect()` |

No other files change.

---

## Testing

- macOS/Linux: existing `SSH_AUTH_SOCK` path unaffected — verified by running the app and connecting with agent auth.
- Windows (manual): start Windows OpenSSH Agent service (`sc start ssh-agent`), add a key (`ssh-add`), connect to a host with auth type "SSH Agent".
- Windows (no agent): verify error message surfaces cleanly in the UI.
