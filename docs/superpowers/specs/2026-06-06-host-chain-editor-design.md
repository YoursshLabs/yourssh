# Host Chain Editor — visual jump-host UI

**Date:** 2026-06-06
**Status:** Approved
**Scope:** UI only — single hop, no model/service changes

## Problem

The JUMP HOST section in `host_detail_panel.dart` is a plain dropdown. Users
asked for a Termius-style visual chain (host cards connected by arrows,
"Add a Host", "Clear") so the connection path is obvious at a glance.

The reference screenshot is Termius's host-chaining UI. Note: that UI is
about **jump hosts (ProxyJump)**, not agent forwarding — agent forwarding
stays a separate toggle in the SESSION section. The chain only *displays*
a key icon when agent forwarding is enabled.

## Decision

Replace the JUMP HOST dropdown with a visual chain editor. Keep the
existing single-hop backend (`Host.jumpHostId`, `SshService` one jump
client per target) untouched. Multi-hop chains are out of scope.

## UI

Section renamed `JUMP HOST` → `CONNECTION CHAIN`.

**Empty state** (no jump host selected):

```
┌─────────────────────────────────────┐
│ Adding a host will route the        │
│ connection to <current host label>  │
│ ┌─────────────────────────────────┐ │
│ │           Add a Host            │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

**Chain state** (jump host selected):

```
┌──────────────────────────────────┐
│ [OS icon]  Jump Host Label    🔑 │   ← key icon iff agentForwarding on
└──────────────────────────────────┘
                 ↓
┌──────────────────────────────────┐
│ [OS icon]  <current host label>  │
└──────────────────────────────────┘
┌──────────────────────────────────┐
│              Clear               │   ← AppColors.red tint, clears jump
└──────────────────────────────────┘
```

- Host cards use `osIconAsset(detectedOs)` (same as `SessionTab`),
  fallback generic server/Linux glyph when `detectedOs` is null.
- Order matches Termius: jump host on top, target below (connection flows
  top → bottom).
- Single hop: once a jump host is set, "Add a Host" is hidden.
- Clicking the jump host card reopens the picker to swap hosts.
- "Add a Host" opens a picker dialog: list of all other saved hosts
  (excluding the host being edited) with a search field filtering on
  label / `user@host`.
- Current-host card label: live text from the label field controller
  (falls back to `user@host` when label empty), so the chain reads
  correctly while creating a new host.

## Components

- **New:** `app/lib/widgets/host_chain_editor.dart`
  - `HostChainEditor({ required String currentHostLabel, Host? jumpHost,
    bool agentForwarding, required ValueChanged<Host?> onSelect,
    required List<Host> candidates })`
  - Pure presentational; no provider reads inside — testable with plain
    `pumpWidget`.
  - Contains the host-picker dialog (`showDialog`) with search.
- **Changed:** `app/lib/widgets/host_detail_panel.dart`
  - The JUMP HOST `Builder` block swaps the `_Card`/dropdown for
    `HostChainEditor`.
  - `_selectedJumpHostId` state, stale-jump-host cleanup (deleted host →
    reset to null via post-frame callback), and save/test wiring stay
    exactly as they are.

## Not changing

`Host` model, `SshService`, sync payload, agent-forwarding toggle and
`AgentStatusLine` behavior.

## Edge cases

- Jump host deleted while panel open → existing stale-id cleanup resets
  to null; editor falls back to empty state.
- No other hosts exist → keep the section hidden (same as today's
  `otherHosts.isEmpty → SizedBox.shrink()`).
- Editing host A that is itself a jump for others — irrelevant here;
  picker only excludes the host being edited (self-jump guard, same as
  the old dropdown).

## Testing

Widget tests in `app/test/widgets/host_chain_editor_test.dart`:

1. Empty state renders helper text + "Add a Host".
2. With `jumpHost` set: two cards + arrow + Clear, no "Add a Host".
3. Key icon shows iff `agentForwarding` is true.
4. Clear tap → `onSelect(null)`.
5. Picker: search filters candidates; tapping one → `onSelect(host)`.
