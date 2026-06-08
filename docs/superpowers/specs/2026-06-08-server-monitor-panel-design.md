# Server Monitor Panel — Design

**Date:** 2026-06-08
**Status:** Approved

## Overview

Add a per-host live monitoring panel to the Hosts Dashboard. When a host has an active SSH session, the user can open a draggable bottom sheet showing real-time CPU, memory, disk, uptime, open ports, and firewall status. The topology graph is out of scope for this iteration.

## Scope

**In:**
- Real-time CPU / memory / disk / uptime (5s polling)
- Open ports via `ss -tulpn` / `netstat -tulpn` (5s polling, same exec as system stats)
- Firewall status + rules (`ufw` / `iptables` / `nftables`, 30s polling)
- Entry point: new icon button on connected host cards + context menu item
- Linux hosts only; non-Linux hosts show "Unavailable" per section

**Out:**
- Network topology graph (future feature)
- Write operations (firewall rule add/remove, port close)
- macOS / Windows remote host support
- Hosts without an active SSH session (shown as "not connected" placeholder)

## Models

### `app/lib/models/system_snapshot.dart`

```dart
class SystemSnapshot {
  final double cpuPercent;       // 0.0–100.0
  final int totalMemBytes;
  final int usedMemBytes;
  final List<DiskMount> disks;
  final Duration uptime;
  final List<PortEntry> ports;
  final DateTime timestamp;

  // Pure factory: shell output string → model. Zero I/O.
  static SystemSnapshot fromShellOutput(String output) { ... }
}

class DiskMount {
  final String source;      // e.g. /dev/sda1
  final String mountPoint;  // e.g. /
  final int totalKb;
  final int usedKb;
}

class PortEntry {
  final String protocol;    // "tcp" | "udp"
  final String localAddress;
  final int localPort;
  final String? process;    // null if no sudo or not reported
}
```

CPU percent is computed from two `/proc/stat` reads 200ms apart within the same exec (avoids a second SSH round-trip).

### `app/lib/models/firewall_status.dart`

```dart
enum FirewallType { ufw, iptables, nftables, none }

class FirewallStatus {
  final FirewallType type;
  final bool enabled;
  final String? defaultInboundPolicy;   // "ACCEPT" | "DROP" | "REJECT" | null
  final List<FirewallRule> rules;

  // Pure factory: shell output string → model.
  static FirewallStatus fromShellOutput(String output) { ... }
}

class FirewallRule {
  final String description;   // formatted display line
  final String? action;       // "ALLOW" | "DENY" | "ACCEPT" | "DROP"
  final String? chain;        // iptables chain name; null for ufw
}
```

## Services

Both services follow the `NetworkStatsService` pattern exactly: `Timer.periodic` → `SshService.exec` → parse → callback. `auditSource: null` on every exec to avoid flooding the audit log.

### `app/lib/services/system_stats_service.dart`

```dart
class SystemStatsService {
  final Host host;
  final SshService sshService;
  final void Function(SystemSnapshot) onUpdate;

  void start({Duration interval = const Duration(seconds: 5)});
  void stop();
}
```

Single compound shell command per poll:

```sh
c1=$(awk '/^cpu /{print}' /proc/stat); sleep 0.2; c2=$(awk '/^cpu /{print}' /proc/stat)
printf '__CPU1__\n%s\n__CPU2__\n%s\n' "$c1" "$c2"
printf '__MEM__\n'; cat /proc/meminfo
printf '__DISK__\n'; df -k
printf '__UPTIME__\n'; cat /proc/uptime
printf '__PORTS__\n'; ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null
```

Exec errors (session mid-reconnect, command not found) are silently ignored; the UI holds the last known snapshot.

### `app/lib/services/firewall_status_service.dart`

```dart
class FirewallStatusService {
  final Host host;
  final SshService sshService;
  final void Function(FirewallStatus) onUpdate;

  void start({Duration interval = const Duration(seconds: 30)});
  void stop();
}
```

Single exec per poll:

```sh
ufw status numbered 2>/dev/null \
  || iptables-save 2>/dev/null \
  || nft list ruleset 2>/dev/null \
  || echo '__NO_FIREWALL__'
```

Both services are instantiated inside `ServerMonitorSheet.initState` and stopped in `dispose`. No global provider needed — state is ephemeral and per-sheet.

## UI

### Entry point

A `Icons.monitor_heart` icon button added to the host card action row — visible only when `SessionProvider.sshSessions.containsKey(host.id)` (no point surfacing it when clearly offline). The context menu always shows a "Monitor" item (even for disconnected hosts) so the feature is discoverable; the sheet handles the "not connected" placeholder state when no session is active.

### `ServerMonitorSheet`

`showModalBottomSheet` wrapping a `DraggableScrollableSheet` (initialChildSize: 0.6, min: 0.4, max: 0.95).

```
┌─────────────────────────────────────┐
│ ● ubuntu-prod  [Linux]     ◉ Live   │  ← header
├─────────────────────────────────────┤
│ SYSTEM                              │
│  Uptime    14d 3h 22m               │
│  CPU       ████████░░  82.4%        │
│  Memory    ██████░░░░  3.1 / 8.0 GB │
│  /         ████░░░░░░  45% of 120GB │
│  /boot     ██░░░░░░░░  18% of 512MB │
├─────────────────────────────────────┤
│ PORTS                               │
│  tcp  0.0.0.0:22    sshd            │
│  tcp  0.0.0.0:80    nginx           │
│  udp  127.0.0.1:53  systemd-resolve │
├─────────────────────────────────────┤
│ FIREWALL  [ufw • active]            │
│  Default inbound: DENY              │
│  22/tcp  ALLOW  anywhere            │
│  80/tcp  ALLOW  anywhere            │
│  443/tcp ALLOW  anywhere            │
└─────────────────────────────────────┘
```

### States

| State | Behavior |
|---|---|
| Host not connected | Centered message: "No active session — open a terminal first" |
| Connected, awaiting first poll | `CircularProgressIndicator` per section |
| Section exec failed | Grey "Unavailable" chip with reason |
| Firewall type `none` | Grey "No firewall detected" in firewall section |
| `ufw`/`iptables` requires sudo | "Firewall detection unavailable (may require sudo)" note |

### No new global provider

`SystemStatsService` and `FirewallStatusService` are owned by `_ServerMonitorSheetState`. Data flows via `setState`. This avoids polluting the global provider tree with per-host ephemeral monitoring state.

## Error handling

- Per-field parse failures produce `null` or `0` values — never throw. One bad field does not blank the section.
- Unknown firewall output → `FirewallType.none`, empty rules list.
- `df` rows missing mount point → skipped.
- `ss`/`netstat` lines that fail to parse → skipped individually.
- Exec errors during polling → silently ignored; UI holds last snapshot.

## Testing

| File | What it covers |
|---|---|
| `test/models/system_snapshot_test.dart` | Parser with `/proc/stat`, `/proc/meminfo`, `df -k`, `ss -tulpn` fixtures |
| `test/models/firewall_status_test.dart` | Parser with ufw / iptables-save / nft / unknown fixtures |
| `test/services/system_stats_service_test.dart` | Timer fires → exec called → `onUpdate` receives snapshot (mock `SshService`) |
| `test/services/firewall_status_service_test.dart` | Same shape |
| `test/widgets/server_monitor_sheet_test.dart` | Renders all sections from fixed snapshot; "not connected" state |

Parser tests are the highest-value layer — pure functions, real distro fixture strings, no mocking.

## File checklist

```
app/lib/models/system_snapshot.dart          (new)
app/lib/models/firewall_status.dart          (new)
app/lib/services/system_stats_service.dart   (new)
app/lib/services/firewall_status_service.dart (new)
app/lib/widgets/server_monitor_sheet.dart    (new)
app/lib/widgets/hosts_dashboard.dart         (edit — add monitor button + context menu item)
app/test/models/system_snapshot_test.dart    (new)
app/test/models/firewall_status_test.dart    (new)
app/test/services/system_stats_service_test.dart    (new)
app/test/services/firewall_status_service_test.dart (new)
app/test/widgets/server_monitor_sheet_test.dart     (new)
```
