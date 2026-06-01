# Terminal Multiplayer — Design Spec

**Date:** 2026-06-01  
**Status:** Approved  
**Feature:** Pair terminal / session sharing via Supabase Realtime

---

## Overview

Allow a YourSSH user (host) to share a live SSH terminal session with one or more guests in read-only mode, with optional temporary control delegation. Transport is Supabase Realtime Broadcast. Feature is only available when Supabase is configured (`SyncProvider.isSupabaseConfigured`).

---

## Architecture & Data Flow

```
HOST side
─────────────────────────────────────────────────────────
SshSession.terminal
    │
    ▼ HookBus.observe("terminal.output")
ShareSessionService
    │  publishes events to Supabase Broadcast channel
    │  channel name: "share:<shareCode>"
    │
    ▼ Events published:
    ├─ {type: "output",           data: base64(bytes)}
    ├─ {type: "input",            data: base64(bytes)}      ← when guest has control
    ├─ {type: "snapshot",         data: base64(ansiDump)}   ← one-time on guest join
    ├─ {type: "snapshot_chunk",   index: n, total: n, data: base64}  ← large buffers
    ├─ {type: "control_grant",    guestId: "..."}
    ├─ {type: "control_revoke",   guestId: "..."}
    └─ {type: "ended"}

GUEST side
─────────────────────────────────────────────────────────
ShareSessionService
    │  subscribes to channel "share:<shareCode>"
    │
    ▼ On join:
    ├─ sends    {type: "join_request", guestId: uuid}
    ├─ receives "snapshot" / "snapshot_chunk" → Terminal.write(ansiDump)
    └─ receives "output" → Terminal.write(bytes)

    ▼ When granted control:
    └─ terminal.textInput() → publishes {type: "input", data: base64(bytes)}
```

**Share code:** 6-char uppercase alphanumeric (e.g. `A3K9PX`), randomly generated per `startSharing()` call. Not persisted to DB — lives in memory only while the host is sharing.

**Gating:** `ShareProvider.canShare` = `SyncProvider.isSupabaseConfigured`. Share button is hidden entirely when Supabase is not configured.

---

## Components

### New files

| File | Responsibility |
|---|---|
| `app/lib/services/share_session_service.dart` | Supabase Realtime channel management, publish/subscribe, scrollback snapshot |
| `app/lib/providers/share_provider.dart` | Flutter state — share code, guest list, control state, isGuest flag |
| `app/lib/widgets/share_session_dialog.dart` | Host UI: show code + QR, guest list, grant/revoke control, stop sharing |
| `app/lib/widgets/join_share_dialog.dart` | Guest UI: enter 6-char code or scan QR |

### Modified files

| File | Change |
|---|---|
| `app/lib/screens/main_screen.dart` | Add share icon button on active session tab (visible only when `canShare && session.status == connected`) |
| `app/lib/main.dart` | Instantiate `ShareProvider`, wire `SyncProvider` reference |

### `ShareSessionService` API

```dart
// Host
Future<String> startSharing(String sessionId, Terminal terminal, String supabaseUrl, String anonKey);
void stopSharing();
void grantControl(String guestId);
void revokeControl();

// Guest
Future<void> joinSession(String shareCode, String supabaseUrl, String anonKey, Terminal localTerminal);
void leaveSession();

// Streams (both roles)
Stream<ShareEvent> get events;
```

### `ShareProvider` state

```dart
bool get canShare           // SyncProvider.isSupabaseConfigured
bool get isSharing          // host: actively sharing
String? get shareCode       // host: active 6-char code
Set<String> get guests      // host: connected guest IDs
String? get controlledBy    // host: guestId with control, or null
bool get isGuest            // guest: joined someone else's session
String? get viewingSessionId
```

---

## UI Flows

### Host flow

1. Active SSH tab → share icon (visible only when `canShare && connected`)
2. Tap → `ShareSessionDialog`:
   - Large share code display: `A3K9PX`
   - QR code encoding `yourssh://share/A3K9PX`
   - Live badge: "N viewers"
   - "Grant control" button → dropdown of connected guest IDs
   - "Stop sharing" button → publishes `ended`, closes dialog
3. While a guest has control: narrow red banner at top of terminal reading `"Guest <id> is controlling"`

### Guest flow

1. Command Palette or sidebar → "Join shared session"
2. `JoinShareDialog`:
   - 6-char code text field (auto-uppercase)
   - "Scan QR" button (macOS/Windows: system camera via `image_picker`)
   - "Join" button
3. On success: new tab opens as `[WATCH] user@host`
4. Blue banner at top: `"Watching: user@host · Read-only"`
5. When granted control: banner turns green → `"You have control"`
6. When host stops: banner → `"Session ended by host"` — tab stays open with existing scrollback

### Control delegation

- Host selects guest from dropdown → `grantControl(guestId)` → only one guest at a time
- Host can revoke at any time
- Guest losing connection while holding control → control auto-revoked

---

## Error Handling & Edge Cases

| Scenario | Handling |
|---|---|
| Supabase Realtime disconnect | Client auto-reconnects; if still failed after 30s → toast to host, banner to guests |
| Guest joins with wrong/expired code | `joinSession` times out after 5s waiting for snapshot → error "Session not found or host disconnected" |
| Scrollback snapshot > 500KB (base64) | Chunked as `snapshot_chunk` events with `index` + `total`; guest reassembles before writing |
| Host app closes mid-share | Channel closes → Supabase delivers `ended` to all guests automatically |
| Guest disconnects while holding control | Host detects via Presence absence → auto-revokes control |
| > 5 guests attempt to join | Host rejects `join_request` beyond limit; guest receives `{type: "rejected", reason: "full"}` |

---

## Security

- Terminal data is **not end-to-end encrypted** beyond TLS (Supabase transport). This is disclosed in the share dialog: *"Shared over TLS via your Supabase project."*
- Share code is single-use per `startSharing()` call — cannot be reused after host stops sharing.
- No share session data is written to the `sync_data` Supabase table.
- Guests use the same `anonKey` as the host's Supabase config — no separate auth needed to join a channel, but the channel name is the only access control (6-char code is the "password").

---

## Out of Scope

- End-to-end encryption of terminal stream (future)
- Persistent session replay (Approach B) 
- More than 5 simultaneous guests
- Guest-to-guest visibility
- Web viewer (no YourSSH app required)
