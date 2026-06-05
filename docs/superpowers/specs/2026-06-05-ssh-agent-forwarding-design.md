# SSH Agent Forwarding — Design

**Date:** 2026-06-05
**Issue:** [#49](https://github.com/YoursshLabs/yourssh/issues/49) — Support SSH Agent Forwarding (similar to Termius)
**Status:** Approved design, pending implementation

## Goal

Let users hop from a connected host to further hosts (`ssh user@next-server` inside the
session) authenticating with keys held on their local machine, without copying private
keys to the intermediate server. Equivalent to OpenSSH `ssh -A` / `ForwardAgent yes`,
exposed as a per-host toggle like Termius.

## What already exists

The local `dartssh2` fork already implements the protocol plumbing:

- `SSHClient(agentHandler: …)` constructor parameter (`ssh_client.dart:179,218`)
- `shell()`/`exec()` send `auth-agent-req@openssh.com` on the session channel when
  `agentHandler != null` (`ssh_client.dart:448,515`)
- Server-initiated `auth-agent@openssh.com` channel opens are accepted and bridged to
  the handler via `SSHAgentChannel` (`ssh_client.dart:947,1054`)
- `SSHAgentHandler` interface (`handleRequest(Uint8List) → Future<Uint8List>`, payloads
  are unframed agent-protocol messages; `SSHAgentChannel` strips/adds the 4-byte length
  frame) and `SSHKeyPairAgent` (serves a `List<SSHKeyPair>` as a virtual agent,
  answering `REQUEST_IDENTITIES` and `SIGN_REQUEST`) — `ssh_agent.dart`

The app already has `SystemAgentProxy` (`app/lib/services/system_agent_proxy.dart`)
which connects to the local agent — `SSH_AUTH_SOCK` Unix socket on macOS/Linux,
`SSH_AUTH_SOCK` then `\\.\pipe\openssh-ssh-agent` named pipe (Win32 FFI) on Windows —
with framed read/write via the internal `_AgentSession`.

Only the app-layer wiring is missing, plus one fork fix (see below).

## Architecture

```
remote sshd opens auth-agent@openssh.com channel
  └── SSHClient._handleAgentChannelOpen → SSHAgentChannel (deframes requests)
        └── AgentForwardingHandler.handleRequest(rawRequest)      [new, app layer]
              ├── primary: SystemAgentProxy.roundtrip(rawRequest) [new API]
              │     (fresh agent connection per request; relays bytes verbatim)
              └── fallback (no system agent): SSHKeyPairAgent built once per
                    handler from app Keychain keys, delegate the request to it
```

Decisions:

- **Connection-per-request** to the system agent. The agent protocol is strictly
  serial per connection; multiple concurrent forwarded channels would otherwise need a
  request queue. Fresh connections are cheap (this is how `ssh-add` works), avoid stale
  sockets after agent restarts, and need no shared state.
- **Verbatim relay** for the system agent path. The handler does not parse or filter
  agent messages; it forwards request bytes and returns response bytes. Extensions and
  newer message types work for free.
- **Lazy resolution.** No agent probing at connect time. The first
  `handleRequest` decides the path; if the system agent is unavailable
  (`SSHAgentUnavailableException`), the keychain fallback is built and cached on the
  handler. Subsequent requests retry the system agent first (cheap fail when absent),
  so an agent started mid-session gets picked up.
- **Keychain fallback scope:** every Keychain key that loads without interaction —
  unencrypted, or encrypted with a stored passphrase (`StorageService.loadPassphrase`).
  Keys that fail to load (missing file, wrong/missing passphrase, parse error) are
  skipped silently. Certificates (`certificatePath`) are not served in v1 — private
  keys only. The fallback set is loaded once per handler (i.e. per SSH connection) and
  cached; Keychain edits apply on next connect.
- **Forwarding applies to the destination client only.** `host.agentForwarding`
  controls the `agentHandler` passed to that host's `SSHClient` in
  `SshService.connect()`. Jump-host clients (`_ensureJumpClient`) never get a handler —
  matching OpenSSH `ProxyJump` + `ForwardAgent` semantics, where forwarding terminates
  at the destination. `testConnection` never gets a handler either.
- **All auth types.** The toggle is independent of `Host.authType` (OpenSSH
  `ForwardAgent` works regardless of how you authenticated). With `AuthType.agent` the
  session already holds a `SystemAgentProxy` for auth signing; forwarding still opens
  its own per-request connections — no sharing, no interleaving risk.

## Components

### 1. `Host.agentForwarding` (model)

`bool agentForwarding`, default `false` (security default — same as OpenSSH and
Termius). Follows the `shellIntegration` pattern exactly:

- constructor param `this.agentForwarding = false`
- `toJson()`: `'agentForwarding': agentForwarding`
- `fromJson()`: `(json['agentForwarding'] as bool?) ?? false` (backward compatible)
- `copyWith(bool? agentForwarding)`

Synced via Supabase/P2P automatically (field rides along in host JSON).

### 2. `SystemAgentProxy.roundtrip` (new API)

```dart
/// Sends one raw (unframed) agent-protocol request and returns the raw
/// (unframed) response body. The caller owns framing-free payloads;
/// length-prefix framing is handled internally by _AgentSession.
Future<Uint8List> roundtrip(Uint8List requestBody)
```

Implemented on the existing `_AgentSession` (frame request via the `_AgentWriter`
header logic, `readMessage()` for the response). No behavioural change to
`getIdentities`/`signAsync`.

### 3. `AgentForwardingHandler` (new, `app/lib/services/agent_forwarding_handler.dart`)

Implements `SSHAgentHandler`. Constructor takes:

```dart
AgentForwardingHandler({
  Future<SystemAgentProxy> Function() connectSystemAgent, // default: SystemAgentProxy.connect
  required Future<List<SSHKeyPair>> Function() loadKeychainIdentities,
})
```

`handleRequest(request)`:

1. Try `connectSystemAgent()` → `proxy.roundtrip(request)` → `proxy.close()` (in
   `finally`) → return response.
2. On `SSHAgentUnavailableException` **from the connect step only**: build (once,
   cached) an `SSHKeyPairAgent` from `loadKeychainIdentities()` and delegate. A failure
   *after* connect succeeded (agent died mid-request) propagates instead — we never
   switch key sources mid-request. An empty key list still gets an agent —
   `SSHKeyPairAgent` answers `REQUEST_IDENTITIES` with zero keys, which remote `ssh`
   handles gracefully.
3. Any other exception propagates — `SSHAgentChannel` already converts handler
   exceptions into `SSH_AGENT_FAILURE` responses, so the remote `ssh` sees a clean
   failure instead of a hung channel.

### 4. Keychain identity loader (wiring in `main.dart` / `SshService`)

`SshService` gains a settable callback (same style as `defaultKeyLookup`):

```dart
Future<List<SSHKeyPair>> Function()? keychainIdentitiesLoader;
```

Wired in `main.dart` from `KeyProvider`: for each `SshKeyEntry`, read the PEM file,
`loadPassphrase(entry.id)`, `SSHKeyPair.fromPem(pem, passphrase)`; collect successes,
skip failures. (Reuses the load logic shape of `_resolveIdentities`'s `privateKey`
case.)

In `SshService.connect()`:

```dart
agentHandler: host.agentForwarding
    ? AgentForwardingHandler(
        loadKeychainIdentities: keychainIdentitiesLoader ?? () async => [],
      )
    : null,
```

No teardown needed: the handler holds no persistent resources (system-agent
connections are per-request; the cached `SSHKeyPairAgent` holds in-memory keys
released with the client).

### 5. dartssh2 fork fix: non-fatal refusal

Today `shell()`/`exec()` throw `SSHChannelRequestError` and close the channel when the
server refuses `auth-agent-req@openssh.com` (`ssh_client.dart:448–453, 515–520`) —
a hardened sshd with `AllowAgentForwarding no` would kill the whole session. OpenSSH
merely warns and continues. Change both sites to:

```dart
if (agentHandler != null) {
  final agentOk = await channelController.sendAgentForwardingRequest();
  if (!agentOk) {
    printDebug?.call('Agent forwarding refused by server');
  }
}
```

(Channel stays open; pty/shell requests proceed.)

### 6. UI toggle (`host_detail_panel.dart`)

`SwitchListTile` following the existing `_autoRecord`/`_shellIntegration` pattern,
placed directly after the Shell integration toggle:

- title: `Agent forwarding`
- subtitle: `Forward your local SSH agent to this host (like ssh -A)`
- default off; visible for all auth types
- state `bool _agentForwarding`, initialised from `widget.existing`, passed into the
  `Host(...)` constructor on save

## Error handling

| Scenario | Behaviour |
|---|---|
| Server refuses `auth-agent-req` | Debug log, session continues without forwarding (fork fix) |
| No system agent, Keychain has loadable keys | Fallback agent serves Keychain keys |
| No system agent, no loadable keys | Fallback agent answers with zero identities; remote `ssh` reports "no identities" |
| System agent dies mid-session | Next request fails to connect → falls back to Keychain agent for that request |
| Agent request fails / malformed | Exception → `SSHAgentChannel` replies `SSH_AGENT_FAILURE` |
| Keychain key fails to load | Skipped; other keys still served |

## Security considerations

- Default **off**, per host — forwarding lets root on the remote host use (not read)
  your keys while the session is open; users opt in per trusted host.
- Private key material never leaves the local machine; only signatures cross the wire
  (inherent to the agent protocol).
- Keychain fallback only serves keys already decryptable by the app (stored
  passphrase); it never prompts and never serves raw key bytes.
- No confirmation-per-signature in v1 (matches OpenSSH default and Termius).

## Testing

- **Model:** `agentForwarding` JSON round-trip; absent field defaults to `false`.
- **`AgentForwardingHandler` unit tests** (follow `system_agent_proxy_test.dart`'s
  fake-agent-socket pattern):
  - relays request/response verbatim through a fake system agent
  - falls back to `SSHKeyPairAgent` when connect throws `SSHAgentUnavailableException`,
    and caches the fallback agent (loader called once across multiple requests)
  - retries the system agent on each request (recovers when the fake agent comes back)
  - propagates non-availability exceptions from `roundtrip`
- **`SystemAgentProxy.roundtrip`:** framing round-trip against the fake agent socket.
- **Fork:** test that a refused `auth-agent-req` no longer throws (shell still opens).
- Manual verification: macOS `ssh-agent` + two-hop `ssh -A`-style hop; toggle off →
  remote `SSH_AUTH_SOCK` absent.

## Out of scope (v1)

- Serving SSH certificates from the Keychain through the forwarded agent
- Per-signature confirmation prompts / forwarding indicators in the terminal UI
- Agent forwarding through the jump leg (`ProxyJump` semantics make it unnecessary)
- `add`/`remove` identity agent operations from remote (`ssh-add` on the remote
  targeting the forwarded agent): system-agent path relays them verbatim (works);
  Keychain fallback answers `SSH_AGENT_FAILURE` (read-only)
