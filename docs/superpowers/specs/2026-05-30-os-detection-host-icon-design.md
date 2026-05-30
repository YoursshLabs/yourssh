# OS Detection & Host Icon Feature

**Date:** 2026-05-30  
**Branch:** feat/ssh-certificate-auth  
**Status:** Approved

## Overview

After a successful SSH connection, detect the remote host's OS and update the host list icon to reflect it (Linux, macOS, or Windows). The detected OS is persisted so the icon survives disconnects and app restarts.

## Architecture

### 1. Host Model (`app/lib/models/host.dart`)

Add a nullable `String? detectedOs` field. Accepted values: `'linux'`, `'macos'`, `'windows'`, `null` (unknown/not yet detected).

- `toJson`: include `'detectedOs': detectedOs`
- `fromJson`: `json['detectedOs'] as String?` — defaults to null for existing data
- `copyWith`: add `String? detectedOs` parameter

### 2. OS Detection (`app/lib/services/ssh_service.dart`)

Add `Future<String?> detectOs(String hostId)` method:
- Runs: `uname -s 2>/dev/null || ver`
- Parse output:
  - Contains `Linux` → `'linux'`
  - Contains `Darwin` → `'macos'`
  - Contains `Windows` or `MINGW` or `CYGWIN` → `'windows'`
  - Anything else / exception → `null`

### 3. SessionProvider (`app/lib/providers/session_provider.dart`)

After `session.status = SessionStatus.connected`, **only if `host.detectedOs == null`**, call `detectOs` then `HostProvider.updateDetectedOs`. The `HostProvider` reference is injected via a callback (same pattern as existing `onMutation`). This ensures detection runs once per host and never re-runs once cached.

New callback on SessionProvider:
```dart
Future<void> Function(String hostId, String os)? onOsDetected;
```

Wired in `main.dart` to call `HostProvider.updateDetectedOs`.

### 4. HostProvider (`app/lib/providers/host_provider.dart`)

Add method:
```dart
Future<void> updateDetectedOs(String hostId, String os)
```
Finds host by id, sets `detectedOs`, saves via `StorageService`, calls `notifyListeners()`. Does **not** trigger `onMutation` (sync push) — this is local metadata only.

### 5. Image Assets

Add PNG files to `app/assets/os/`:
- `linux.png`
- `macos.png`  
- `windows.png`

Register in `app/pubspec.yaml` under `flutter.assets`. Use simple, clean monochrome/white icons on colored background to match current `Icons.dns` aesthetic.

### 6. UI (`app/lib/widgets/hosts_dashboard.dart`)

Replace the hardcoded `Icons.dns` widget with a helper `_osIcon(Host host)`:

```dart
Widget _osIcon(Host host) {
  if (host.detectedOs != null) {
    return Image.asset('assets/os/${host.detectedOs}.png',
        width: 20, height: 20, color: Colors.white);
  }
  return const Icon(Icons.dns, color: Colors.white, size: 18);
}
```

## Data Flow

```
SSH Connect success
  → SessionProvider calls SshService.detectOs(hostId)
  → SshService runs "uname -s 2>/dev/null || ver"
  → Returns 'linux' | 'macos' | 'windows' | null
  → SessionProvider calls onOsDetected(hostId, os)
  → HostProvider.updateDetectedOs updates model + saves to SharedPreferences
  → notifyListeners() → HostsDashboard rebuilds → icon updates
```

## Error Handling

- If `detectOs` throws (exec fails, session not found): silently swallow, leave `detectedOs` as-is.
- If asset file missing at runtime: Flutter throws, so all 3 PNGs must exist before shipping.
- Detection runs fire-and-forget (not awaited by connect flow); connection UX is unaffected.

## Backward Compatibility

- `Host.fromJson` with no `detectedOs` key → null, renders `Icons.dns` as before.
- No migration needed.

## Out of Scope

- Re-detecting OS on every reconnect (only detect once; existing value is kept unless null).
- Manual override of detected OS.
- Sync of `detectedOs` to Supabase (it's excluded from `onMutation`).
