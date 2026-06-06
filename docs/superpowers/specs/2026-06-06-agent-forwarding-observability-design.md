# Agent Forwarding Observability — Design

**Date:** 2026-06-06
**Status:** Approved
**Related:** `docs/superpowers/specs/2026-06-05-ssh-agent-forwarding-design.md` (runtime design, issue #49)

## Problem

Agent forwarding works, but users can't tell whether it works. Three confirmed pain points:

1. **No feedback** — the toggle gives no indication whether the local agent is running, which keys would be offered, or whether the server accepted forwarding. When no agent is running the handler silently falls back to app-Keychain keys without telling the user.
2. **Concept confusion** — the relationship between auth method "SSH Agent" (authenticate *to* this host) and "Agent forwarding" (let this host borrow keys for *onward* hops) is not explained anywhere in the UI.
3. **Errors easy to miss** — a server refusal is one yellow line in terminal scrollback; agent-unavailable errors surface only at connect time for `AuthType.agent`, never for forwarding.

Competitive note: Termius has no system-agent integration at all and no failure surfacing for forwarding — yourssh already talks to the real system agent and detects refusal (`SSHSession.agentForwardingRefused`). This design leans into that edge: make the existing signals visible.

## Scope

In scope:
- Clearer copy + inline explainer in the host detail panel
- Live agent status line in the host detail panel (pre-connect feedback)
- Per-session forwarding state with a `SessionTab` indicator (in-session feedback)
- Refusal pushed to the notification bell

Out of scope (YAGNI, explicitly deferred):
- Global default / group inheritance for the forwarding toggle
- Dedicated agent diagnostics screen
- Agent forwarding option in the quick Add Host dialog
- Manual agent socket path override

## Design

### 1. Concept clarity (host detail panel)

In `host_detail_panel.dart` (toggle at ~line 450):

- New subtitle: *"Let this host use your local SSH keys for onward connections — git, ssh to other servers (like `ssh -A`). Applies on next connect."*
- Info icon (ⓘ) next to the "Agent forwarding" title opens a small popover/dialog (3–4 lines):
  - **SSH Agent auth** = your agent's keys log you in to *this* host.
  - **Agent forwarding** = this host can borrow your local keys to reach *other* places (git pull, next ssh hop). Private keys never leave your machine.
  - Security note: *"Only enable for trusted hosts — anyone with root on the host can use your keys while you're connected."*

### 2. Live agent status line (host detail panel)

New widget `AgentStatusLine`, rendered:
- under the Agent forwarding toggle **when the toggle is on**, and
- under the auth method dropdown **when auth = SSH Agent**.

When both conditions hold, only the auth-section instance is shown (one probe, no duplicate line).

Probes on first appearance; manual refresh button re-probes. States:

| Probe result | Display |
|---|---|
| System agent reachable | ✓ `System agent connected — N identities` |
| No agent, Keychain keys loadable | ⚠ `No system agent — N app Keychain keys will be offered instead` |
| No agent, no usable Keychain keys | ✗ `No agent and no usable Keychain keys — forwarding will offer nothing. Run "ssh-add <key>" or add a key in Keychain.` |

Probe logic is a pure, testable function `probeAgentStatus()` (new file next to `agent_forwarding_handler.dart`):
- inputs injected: `connectSystemAgent` (defaults to `SystemAgentProxy.connect`) and `loadKeychainIdentities` (the same loader `SshService.keychainIdentitiesLoader` uses)
- implementation: `SystemAgentProxy.connect()` + `getIdentities()` (already exists, used by `AuthType.agent` auth at `ssh_service.dart:123`), close the proxy after; on `SSHAgentUnavailableException`, count loadable Keychain keys
- returns a sealed result: `AgentProbeResult.systemAgent(identityCount)` / `.keychainFallback(keyCount)` / `.nothing(detail)`

The probe is cheap (local socket connect + one `REQUEST_IDENTITIES` round trip) and read-only.

### 3. Per-session forwarding state

New enum (in `app/lib/models/`):

```dart
enum AgentForwardingState { off, ready, active, fallback, refused }
```

- `off` — host has forwarding disabled (no indicator shown)
- `ready` — enabled, shell open, no agent request served yet
- `active` — ≥1 request served via the system agent (proof it actually works)
- `fallback` — last request served via Keychain keys (agent unreachable)
- `refused` — server refused `auth-agent-req` (`AllowAgentForwarding no`)

State transitions: `ready → active/fallback` on each served request (source can flip per request, matching the handler's per-request retry design — display tracks the *latest* request's source); `ready → refused` on shell-open refusal. `refused` is terminal for the session (the request is sent once per shell).

Wiring (follows the existing callback pattern in `main.dart`):
1. `AgentForwardingHandler` gains an optional `onRequestServed(bool usedFallback)` callback, fired after each successfully served request.
2. `SshService` gains an `onAgentForwardingEvent(String hostId, AgentForwardingState state)` callback field. It forwards handler callbacks and fires `refused` from the existing check at `ssh_service.dart:395`.
3. `main.dart` wires it to `SessionProvider`, which sets a mutable `agentForwardingState` field on the matching `SshSession` and notifies.

`SessionTab` indicator: a small key icon (~12px, `Icons.key`), rendered **only when the session's host has forwarding enabled** (no clutter on normal tabs), colored by state:
- grey = ready, accent green = active, yellow = fallback, red = refused
- Tooltip explains the state in one line, e.g. *"Agent forwarding active — serving keys from your system agent"* or *"Agent forwarding refused by server (AllowAgentForwarding no)"*.

### 4. Error surfacing

- On refusal: keep the existing yellow terminal line, **and** push an `AppNotification` to `NotificationCenterProvider` with `dedupeKey: 'agent-refused:<sessionId>'` (dedupe prevents spam across reconnects of the same session).
- Audit existing agent error messages for actionable hints (most already good: `ssh-add` hint, Windows service hint); normalize where missing.

## Error handling

- Probe failures other than `SSHAgentUnavailableException` (e.g. malformed agent reply) display as the ✗ state with the error detail — never throw into the widget tree.
- Handler callback failures must not break request serving: callbacks are fire-and-forget, wrapped so an exception in UI-side code can't fail the agent round trip.
- `SessionProvider` lookups by hostId must tolerate the session being closed mid-event (drop the event).

## Testing

Unit:
- `probeAgentStatus()` with fake `connectSystemAgent` / `loadKeychainIdentities` — all three result states, plus proxy close on both success and failure paths
- `AgentForwardingHandler.onRequestServed` fires with correct `usedFallback` for system-agent and Keychain paths; callback exception doesn't fail the request
- `SessionProvider` state transitions (`ready → active`, `ready → fallback`, `ready → refused`, event after session close is a no-op)
- Notification dedupe: two refusals for the same session produce one bell item

Widget:
- `AgentStatusLine` renders the three probe states; refresh re-probes
- `SessionTab` shows no key icon when forwarding is off; correct color per state; tooltip text
- Host detail panel: status line appears when toggle flips on and when auth = SSH Agent
