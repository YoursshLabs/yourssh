# Jump Host / Bastion Proxy — Design Spec

**Date:** 2026-05-30  
**Status:** Approved

---

## Problem

Users in hardened network environments cannot reach internal servers directly. They must connect through a bastion (jump host) first. OpenSSH solves this with `ProxyJump` / `-J`. YourSSH currently has no equivalent.

---

## Approach

Use `dartssh2`'s `SSHClient.forwardLocal()` to open a direct-tcpip channel through the bastion. The returned `SSHForwardChannel` implements `SSHSocket`, so it can be passed directly as the transport socket for the inner `SSHClient`. Fully in-process, no local port binding, no external tools, cross-platform.

```
SSHSocket.connect(bastion.host, bastion.port)
  → jumpClient (SSHClient)
    → jumpClient.forwardLocal(target.host, target.port)
      → SSHForwardChannel (implements SSHSocket)
        → targetClient (SSHClient)
```

---

## Scope

- Single hop only: local → bastion → target.
- Jump host is referenced by ID from the existing host list (reuses its saved auth).
- All operations go through jump: shell, SFTP, port forwarding, test connection.

---

## Data Model

### `Host` (app/lib/models/host.dart)

Add one nullable field:

```dart
String? jumpHostId;
```

- `null` = direct connection (no behaviour change).
- Serialized as `'jumpHostId'` in `toJson` / `fromJson`.
- Added to `copyWith`.

---

## SshService

### New state

```dart
final Map<String, SSHClient> _jumpClients = {};
```

Jump clients are keyed by the jump host's `Host.id`. Multiple targets sharing the same bastion reuse one jump connection.

### `connect()` changes

```
if host.jumpHostId != null:
  jumpHost = look up from StorageService / passed in
  jumpClient = await _ensureJumpClient(jumpHost, keyEntry, verifyHostKey)
  socket = await jumpClient.forwardLocal(host.host, host.port)
else:
  socket = await SSHSocket.connect(host.host, host.port)

client = SSHClient(socket, username: host.username, ...)
```

`_ensureJumpClient` returns the cached `_jumpClients[id]` if it exists, otherwise connects and caches.

No signature change to `connect()`. The jump host's key is resolved inside `_ensureJumpClient` by looking up the jump host's `keyId` via the existing key-lookup callback (same path as any normal connection).

### `disconnect()` changes

After removing `_clients[hostId]`, check whether any remaining entry in `_clients` has `jumpHostId == hostId`. If none, close and remove `_jumpClients[hostId]`.

### `testConnection()` changes

If `host.jumpHostId != null`, open a temporary jump client (not cached), forward through it, test, then tear everything down in `finally`.

### Error surface

If the bastion connection drops while a target is active, the next read/write on the `SSHForwardChannel` will throw. This surfaces to `SessionProvider` as a normal connection error — no special handling needed.

---

## UI

### `AddHostDialog` / Edit Host

- Add a "Jump Host" `DropdownButtonFormField` below the auth section.
- Items: `(None)` + all saved hosts except the host being edited.
- Hidden when the host list has no other entries.
- Saves `host.jumpHostId`.

### `HostDetailPanel`

- Connection info line shows `via [jump label]` when `jumpHostId` is set.

---

## What does NOT change

- Port forward, SFTP, exec, test connection call `connect()` internally — they pick up jump host support automatically.
- Auth flow (password, key, certificate, agent) for the target host is unchanged.
- Known-hosts verification fires for both the jump host and the target host independently.

---

## Out of scope

- Multi-hop chaining (bastion1 → bastion2 → target).
- Jump host-specific auth that differs from its saved host entry.
- UI indicator showing bastion connection status separately.
