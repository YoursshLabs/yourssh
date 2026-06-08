# Discover Local Devices — Design

**Date:** 2026-06-08  
**Status:** Approved

## Overview

Scan the local network for SSH/RDP-capable devices and allow users to add them as hosts with OS auto-detection. Combines mDNS/Bonjour discovery (real-time, no scan needed) with parallel TCP port scanning across the detected subnet.

Entry points:
- **Hosts Dashboard** — "Discover" button next to the "+" Add Host button
- **Host Detail Panel** — "Scan network to pick a device" link under the IP field (add-new-host mode only)

---

## Architecture

### Model: `DiscoveredHost`

```dart
// app/lib/models/discovered_host.dart

enum DiscoverySource { mdns, tcpScan, both }

class DiscoveredHost {
  final String ip;
  final String? hostname;         // from mDNS service name or reverse DNS
  final List<int> openPorts;      // e.g. [22, 3389]
  final DiscoverySource source;
  final String? mdnsServiceType;  // "_ssh._tcp", "_rdp._tcp", etc.
}
```

### Model: `SubnetInfo`

```dart
class SubnetInfo {
  final String interfaceName;   // "en0", "eth0"
  final String displayName;     // "Wi-Fi", "Ethernet"
  final String address;         // "192.168.1.5"
  final String subnet;          // "192.168.1.0/24"
}
```

Subnet is derived from the interface address assuming `/24` (covers virtually all home/office LANs). The user can override the subnet string before scanning.

### Service: `NetworkDiscoveryService`

**File:** `app/lib/services/network_discovery_service.dart`

```
NetworkDiscoveryService
  ├── getLocalSubnets() → Future<List<SubnetInfo>>
  │     reuses NetworkInterface.list logic from P2PSyncService, adds subnet derivation
  │
  ├── scan(SubnetInfo subnet, {List<int> ports, Duration timeout}) → Stream<DiscoveredHost>
  │     merges two sub-streams, deduplicates by IP
  │     ├── _runMdnsScan()   → uses multicast_dns package, watches _ssh._tcp / _sftp-ssh._tcp / _rdp._tcp
  │     └── _runTcpScan()    → Socket.connect per (ip, port), 50 concurrent max, 500ms timeout
  │
  └── cancel() → stops both sub-streams, closes all pending sockets
```

**Default ports scanned:** `[22, 2222, 3389]`

**mDNS service types watched:** `_ssh._tcp`, `_sftp-ssh._tcp`, `_rdp._tcp`

**Deduplication:** results are keyed by IP. When the same IP arrives from both mDNS and TCP scan, they are merged into a single `DiscoveredHost` with `source: both` and ports union-merged.

**Concurrency:** TCP scan uses a `Semaphore`-style counter (max 50 in-flight `Socket.connect` at a time) so 254 addresses are worked through in ~3 seconds at 500ms timeout.

**Dependency:** add `multicast_dns: ^0.3.2` to `app/pubspec.yaml`.

---

## UI

### `NetworkDiscoverySheet`

**File:** `app/lib/widgets/network_discovery_sheet.dart`

Draggable bottom sheet (same pattern as `ServerMonitorSheet`). Two modes:

- **Browse mode** (opened from dashboard "Discover" button) — user can Add or Connect each result
- **Selection mode** (opened from Host Detail Panel) — tap a result closes the sheet and pre-fills the panel

```
┌─────────────────────────────────────────────┐
│  Discover Devices              [×]           │
│                                              │
│  Interface: Wi-Fi  192.168.1.0/24  [Edit]   │
│  ████████████████░░░░  Scanning… 127/254    │
│                                              │
│  ● raspberrypi.local   192.168.1.42   SSH   │
│  ● MacBook-Pro.local   192.168.1.10   SSH   │
│  ● DESKTOP-WIN11       192.168.1.55   RDP   │
│  ○ 192.168.1.88        (no hostname)  SSH   │
│                          [Add ▾] [Connect]  │
│                                              │
│  mDNS: 3 found · TCP scan: 1 found          │
└─────────────────────────────────────────────┘
```

**Behavior:**
- mDNS results appear immediately as the sheet opens (real-time stream)
- TCP scan progress bar is shown while scan is running; hidden on completion or cancel
- Interface selector shows all `SubnetInfo` from `getLocalSubnets()`; user can also type a custom subnet (validated inline — must be valid CIDR; Start Scan disabled while invalid)
- Each row shows: hostname (or IP if no hostname), IP badge, port badge (SSH / SSH:2222 / RDP)
- **[Add]** opens `HostDetailPanel` pre-filled: `host=ip`, `port=openPorts.first`, `protocol` derived from port (3389→RDP, else SSH), display name from hostname if present
- **[Connect]** same as Add but calls `SessionProvider.connectHost` immediately after saving
- In **selection mode** rows are tappable; tap closes the sheet and calls `onSelected(DiscoveredHost)`

### Hosts Dashboard

`app/lib/widgets/hosts_dashboard.dart`: add an icon button `Icons.wifi_find` (label "Discover") beside the existing "+" add-host button in the app bar / actions row. Tapping opens `NetworkDiscoverySheet` in browse mode.

### Host Detail Panel

`app/lib/widgets/host_detail_panel.dart`: when creating a new host (no existing host id), add a text button `🔍 Scan network to pick a device` below the host/IP text field. Tapping opens `NetworkDiscoverySheet` in selection mode. On selection, the panel's fields are updated: `_hostController.text = ip`, `_portController.text = port`, display name set to hostname, protocol toggled if RDP.

---

## OS Auto-Detection

No changes to the detection flow. After a discovered host is added and the user connects, `SessionProvider` calls `SshService.detectOs` as it already does for every new SSH session. The `detectedOs` field on `Host` is null until first connect, same as manually-added hosts.

---

## Error Handling

| Situation | Behavior |
|---|---|
| No active network interfaces | Empty state in sheet: "No active network interfaces found" |
| mDNS socket fails (firewall / permission) | TCP scan continues; mDNS counter shows warning icon |
| Individual TCP connect timeout/error | Silent skip — does not interrupt the stream |
| Invalid custom subnet entered | Inline validation error; "Start Scan" button disabled |
| Sheet closed while scan in progress | `cancel()` called immediately; all pending sockets aborted |
| `multicast_dns` package unavailable at runtime | mDNS sub-stream skipped; TCP-only scan proceeds |

---

## Testing

### Unit tests — `NetworkDiscoveryService`

Inject a `SocketConnector` function type `(String ip, int port, Duration timeout) → Future<bool>` so tests never touch real network:

- Deduplication: same IP from mDNS + TCP scan → one result with `source: both`
- Concurrency cap: verify no more than 50 concurrent in-flight connects
- Stream completion: stream closes after TCP scan finishes (mDNS stays open until `cancel()`)
- Cancel: stream emits no more items after `cancel()` called mid-scan

### Unit tests — mDNS path

Wrap `MDnsClient` behind a `MdnsScanner` interface; inject a fake that emits pre-canned `ResourceRecord` entries.

### Widget tests — `NetworkDiscoverySheet`

- Progress bar visible while scanning, hidden after completion
- Rows render correctly given a mock `Stream<DiscoveredHost>`
- "Add" button triggers `HostDetailPanel` pre-fill
- Selection mode: tap closes sheet and calls `onSelected`

---

## File Checklist

| File | Change |
|---|---|
| `app/pubspec.yaml` | add `multicast_dns: ^0.3.2` |
| `app/lib/models/discovered_host.dart` | new |
| `app/lib/services/network_discovery_service.dart` | new |
| `app/lib/widgets/network_discovery_sheet.dart` | new |
| `app/lib/widgets/hosts_dashboard.dart` | add Discover button |
| `app/lib/widgets/host_detail_panel.dart` | add "Scan network" link in add-new-host mode |
| `app/test/services/network_discovery_service_test.dart` | new |
