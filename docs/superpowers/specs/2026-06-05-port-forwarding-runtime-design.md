# Port Forwarding Runtime — Design

**Date:** 2026-06-05
**Status:** Approved

## Problem

The port forwarding feature is scaffolding only: `PortForward` model,
`PortForwardProvider` (add/delete + SharedPreferences persistence), and a
CRUD screen exist, but **no code ever activates a tunnel**. `setStatus()` has
no caller, rules stay `idle` forever, and the Web Tools port-forward browser
is permanently empty. The dartssh2 fork already ships every required API
(`forwardLocal`, `forwardRemote` + `cancelForwardRemote`, `forwardDynamic`
SOCKS5). The gap is purely the app-side integration layer.

## Goals

- Start/stop all three forward types: local, remote, dynamic (SOCKS5).
- Reuse the host's existing `SSHClient` when connected; auto-connect with
  stored credentials when not (same `_ensureClient` path `exec` uses today) —
  a tunnel must not require an open terminal tab.
- Auto-reconnect: when the SSH connection of a host with active tunnels
  drops, re-establish the connection and the tunnels without user action.
- UI: per-rule start/stop toggle, edit, auto-start flag, live connection
  counter, visible error messages.

## Non-goals

- Auto-connect through a jump host (inherits today's `_ensureClient`
  behavior: direct connect only; tunnels piggyback on an already-open
  jump-host connection just fine).
- Per-tunnel bandwidth stats or traffic inspection.
- Closing the shared `SSHClient` when the last tunnel stops (clients stay
  alive until `SshService.disconnect`, as today).

## Model & provider changes

`PortForward` (`app/lib/models/port_forward.dart`):
- New persisted field `autoStart` (bool, default `false`), in
  `toJson`/`fromJson`.
- New transient field `activeConnections` (int, default 0) — like
  `status`/`errorMessage`, never serialized.

`ForwardStatus`: `idle, connecting, active, reconnecting, error`
(adds `connecting`, `reconnecting`).

`PortForwardProvider`:
- `update(PortForward fwd)` — replace by id, persist, notify.
- `setConnections(String id, int n)` — transient, notify (drop silently if
  the rule was deleted, same as `setStatus`).

## PortForwardService (new, `app/lib/services/port_forward_service.dart`)

Owns all runtime tunnel state, keyed by forward id. Constructor takes
injectable hooks so tests never need a real `SshService`:

```dart
PortForwardService({
  required Future<SSHClient> Function(Host host) ensureClient, // SshService._ensureClient (exposed)
  required Host? Function(String hostId) resolveHost,          // HostProvider lookup
  required void Function(String id, ForwardStatus s, {String? error}) onStatus,
  required void Function(String id, int connections) onConnections,
})
```

Public API:
- `Future<void> start(PortForward fwd)` — validates (`hostId` set, host
  exists), sets `connecting`, acquires client, opens the tunnel, sets
  `active`. Any failure → `error` with a human-readable message
  (e.g. "Port 8080 already in use").
- `Future<void> stop(String forwardId)` — closes the listener / SOCKS server
  / remote forward and every live piped connection; cancels any pending
  reconnect; sets `idle`. Never closes the shared `SSHClient`.
- `Future<void> stopAll()` — app shutdown / host deleted.
- `bool isRunning(String forwardId)`.
- `Future<void> autoStartAll(List<PortForward> rules)` — starts every rule
  with `autoStart == true`; failures surface per-rule via `onStatus`, never
  throw.

Per-type runtime:
- **Local**: `ServerSocket.bind(localHost, localPort)`; each accepted socket
  → `client.forwardLocal(remoteHost, remotePort)` → pipe both directions;
  increment/decrement the connection counter as sockets open/close.
- **Remote**: `client.forwardRemote(port: remotePort)` (null result →
  error "server refused remote forward"); for each incoming
  `SSHForwardChannel` → `Socket.connect(localHost, localPort)` → pipe both
  directions. Stop = `cancelForwardRemote`.
- **Dynamic**: `client.forwardDynamic(bindHost: localHost, bindPort:
  localPort)`; stop = `.close()`. The fork's `SSHDynamicForward` interface
  gains `int get activeConnections` (the impl already tracks a private
  `_connections` set); the SOCKS server has no connection-event stream, so
  the service samples the getter with a 2 s periodic timer while the tunnel
  is active.

### Reconnect

The service watches `client.done` for every host that has ≥1 running tunnel.
When it fires (and the drop wasn't user-initiated stop):
1. All tunnels of that host → `reconnecting`; local listeners stay bound if
   possible (only the SSH side is re-dialed), otherwise re-bound.
2. Retry `ensureClient` with exponential backoff: 2s, 4s, 8s … capped at
   30s, unlimited attempts.
3. On success, re-establish every tunnel of the host → `active`.
4. `stop()` during reconnect cancels the retry loop for that tunnel; when
   the host's last tunnel is stopped the retry loop dies with it.

### Ownership rules

- Clients acquired via `ensureClient` live in `SshService._clients` — shared
  with terminal sessions and SFTP. The tunnel layer never closes them.
- `SshService.disconnect(hostId)` (user disconnects) also triggers
  `client.done` → tunnels go into reconnect, which will simply re-dial.
  This is intended: a tunnel is an independent consumer of the host.

## UI (`app/lib/widgets/port_forwarding_screen.dart`)

- Play/stop icon button per rule row → `start`/`stop`.
- Status dot: idle grey, connecting amber, active green, reconnecting amber
  (pulsing not required), error red. Error message line (red, small) under
  the summary when status is `error`.
- Click a rule → the existing add panel opens prefilled as **Edit** (Save
  calls `provider.update`; if the rule is running, stop it first).
- "Auto-start" checkbox in the add/edit panel.
- Connection-count chip ("3 conn") next to the status dot while active.

## Wiring (`app/lib/main.dart`)

- Instantiate `PortForwardService` with: `SshService.ensureClient` (new
  public wrapper around `_ensureClient`), `HostProvider` lookup,
  `PortForwardProvider.setStatus` / `setConnections`.
- After `PortForwardProvider` finishes loading, call
  `autoStartAll(provider.forwards)`.
- `HostProvider` deletion of a host stops that host's tunnels.

## Edge cases

- Local port already bound → `error: "Port N already in use"`.
- Rule without `hostId` → `error: "Select an SSH host first"`.
- Host deleted while tunnel running → tunnel stopped.
- Rule deleted while running → the screen calls `service.stop(id)` before
  `provider.delete(id)` (the screen is the only deletion entry point).
- App quit → `stopAll()` (best-effort; OS reclaims sockets anyway).

## Testing

- `port_forward_service_test.dart`: fake `ensureClient` returning a stub
  client; real `ServerSocket` on port 0 for local-forward accept loop; cover
  start/stop per type, status transitions, error paths (port in use, missing
  host), reconnect backoff sequence (injectable delay fn), connection
  counting, stop-during-reconnect.
- `port_forward_provider_test.dart`: `update()`, `autoStart` round-trip,
  `setConnections` on deleted rule.
- Widget-level: screen shows toggle, error line, counter chip (existing
  widget-test patterns).
- `flutter analyze` + full `flutter test` green; manual run on macOS to
  verify a real local forward end-to-end.
