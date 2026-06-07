# Multi-hop Jump Chain — Design

**Date:** 2026-06-07
**Status:** Approved

## Problem

Layered networks need bastion → bastion → target, but `Host.jumpHostId`
holds exactly one hop: `SshService.connect` dials one bastion and opens a
single `forwardLocal` channel, and `HostChainEditor` hides "Add a Host"
once a hop is set. Roadmap P0 #2 (single-hop chain editor shipped 0.1.30).

## Goals

- `Host` carries an ordered hop list; existing single-hop hosts migrate
  transparently and cross-version sync degrades gracefully.
- `SshService` dials the chain sequentially — each hop authenticated with
  its own credentials and host-key verification, the next hop's socket
  being the previous client's `forwardLocal`.
- Chain-aware client caching and teardown (deepest-first, refcounted by
  the hosts that use each prefix).
- All auto-connect paths (`ensureClient`: SFTP / exec / port forwarding)
  tunnel through the full chain.
- `HostChainEditor` appends/removes hops; cycle-impossible by
  construction in the picker, defensively checked at dial time.
- A missing hop (id that no longer resolves) **fails the connect** with a
  clear error — silently skipping a hop would route traffic around a
  network boundary the user explicitly configured.

## Non-goals

- Drag-reorder in the chain editor (remove + re-add covers it).
- Per-hop agent forwarding (destination-only, as today — ProxyJump
  semantics).
- Multi-hop support in `tool/jump_probe.dart` (stays single-hop; noted in
  its header).
- Shared/named chain templates.

## Model — `Host`

- New field `List<String> jumpHostIds` (default `[]`; constructor takes
  an iterable and owns a growable copy, same as `tags`).
- Getter `String? get jumpHostId => jumpHostIds.firstOrNull` retained for
  "has a bastion?" consumers; the **setter/field form is removed** — all
  writers move to the list.
- `fromJson`: prefer `jumpHostIds` (tolerant: non-list/malformed → `[]`,
  entries stringified); when absent, wrap a legacy `jumpHostId` string
  into a one-element list.
- `toJson`: writes **both** — `jumpHostIds` (full list) and `jumpHostId`
  (first hop or null) so an older app receiving a synced payload keeps
  working single-hop instead of losing the bastion entirely.
- `copyWith({List<String>? jumpHostIds})` (null = keep; empty list =
  clear — no `_Unset` needed for a non-nullable list).

## Dialing — `SshService`

- `connect()` replaces `jumpHost`/`jumpKeyEntry` with
  `List<JumpHop> jumpChain` (`typedef JumpHop = ({Host host, SshKeyEntry? keyEntry})`,
  empty = direct). Internal callers (SessionProvider, `_ensureClient`,
  tests) migrate; no deprecated shim.
- Sequential dial: hop₀ over a direct `SSHSocket.connect`; each subsequent
  hop over `clientᵢ.forwardLocal(next.host, next.port)`; the destination
  over the last hop's `forwardLocal`. Every hop resolves identities and
  verifies host keys exactly like today's single bastion (per-hop
  hostname/port passed to the verifier).
- **Cache by chain-prefix key**: `hopIds.take(i+1).join('>')` — a client
  to B *through A* is distinct from a direct client to B. `_jumpClients`
  and `_jumpAgentProxies` re-key on the prefix; `_hostToJump` becomes
  `Map<String, List<String>>` (host id → its chain keys).
- Teardown (disconnect and failed-connect cleanup): walk the host's chain
  keys deepest-first; close a prefix client only when no other host's key
  list contains it.
- **Cycle guard** at dial time: duplicate hop ids or the target id inside
  the chain → throw `ArgumentError` with the offending id (the picker
  already prevents this; sync/import payloads might not).
- `_ensureClient` resolves every id in `host.jumpHostIds` via
  `defaultJumpHostLookup` (+ key via `defaultKeyLookup`); any unresolved
  id throws.

## SessionProvider

`_doConnect` builds the chain: map each `host.jumpHostIds` entry through
`jumpHostLookup` + `keyLookup`. An unresolved hop throws before any dial
(fails the connect with "Jump host not found: <id>"); the existing
retry/error surface handles presentation.

## UI — `HostChainEditor` + host panel

- Props: `jumpHost: Host?` → `chain: List<Host>`; callback
  `onChanged(List<String> ids)` replaces `onSelect`.
- Renders hop₁ → hop₂ → … → destination with the existing card/arrow
  style; **Add a Host stays visible** (appends before the destination).
- Candidates exclude the host being edited and every host already in the
  chain (no cycles by construction).
- Each hop card gets a hover **remove (×)**; **Clear** empties the chain.
- `HostDetailPanel`: `_selectedJumpHostId` → `List<String> _jumpHostIds`;
  save writes the list; `_test()` (test-connection) resolves the full
  chain the same way `_doConnect` does.

## Testing

- **Model:** round-trip with multiple hops; legacy payload (`jumpHostId`
  only) migrates to a one-element list; `toJson` writes both fields;
  malformed `jumpHostIds` degrades to `[]`; `copyWith` keep/clear.
- **SshService:** fake `SSHClient` whose `forwardLocal` records calls and
  returns a fake socket — a 2-hop chain dials in order with per-hop
  auth/verify; prefix cache reused across two targets sharing hop₀;
  teardown closes deepest-first and spares prefixes still in use; cycle
  guard throws; unresolved hop in `_ensureClient` throws.
- **SessionProvider:** unresolved hop fails the connect with the clear
  message (capturing-fake pattern).
- **Widget:** editor appends a second hop, removes a middle hop,
  candidates exclude chain members; panel saves/loads the list.
