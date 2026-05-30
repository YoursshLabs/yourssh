# P2P QR Sync — Design Spec

**Date:** 2026-05-30  
**Branch:** feat/ssh-certificate-auth  
**Status:** Approved

## Overview

Add a P2P sync option that lets users transfer all SSH hosts and passwords from Device A to Device B using a QR code, with no cloud dependency. Device A starts a local HTTP server, Device B scans the QR code and pulls the encrypted payload over LAN/Tailscale/any IP-routable network.

This is a **one-time import**: Device B replaces all existing hosts with the imported data. There is no ongoing bidirectional sync.

---

## Architecture & Flow

### Device A (Sender)

1. User clicks "Show QR Code" (Sync Settings or Host list toolbar)
2. App collects hosts + passwords via existing `SyncService.buildPayload`
3. Generate random 32-byte AES-256 key
4. Encrypt payload with `P2PSyncEncryption.encrypt(payload, key)`
5. Start `HttpServer` on `InternetAddress.anyIPv4`, port 0 (OS assigns)
6. User selects network interface from dropdown (default: first non-loopback IPv4 via `NetworkInterface.list()`)
7. Encode QR payload: `{"u":"http://<IP>:<PORT>/sync","k":"<base64url_key>"}`
8. Show `QrExportDialog` with QR + 2-minute countdown
9. On first `GET /sync` request: serve encrypted blob → close server immediately (one-time use)
10. On countdown expiry: close server, dismiss dialog

### Device B (Receiver)

1. User clicks "Scan QR Code" in Sync Settings → opens `QrImportScreen`
2. Camera scans QR → parse JSON to extract `u` (URL) and `k` (key)
3. HTTP GET to `u` with 5-second timeout
4. Decrypt response with key via `P2PSyncEncryption.decrypt`
5. Parse payload via `SyncService.parsePayload`
6. Replace all existing hosts and passwords in `HostProvider` + `StorageService`
7. Show success dialog: `"Imported X hosts. All previous hosts replaced."`

---

## Components

### New Files

| File | Responsibility |
|---|---|
| `lib/services/p2p_sync_service.dart` | HTTP server + client, network interface enumeration, server lifecycle |
| `lib/services/p2p_sync_encryption.dart` | AES-256-GCM with raw random key (no PBKDF2) |
| `lib/widgets/qr_export_dialog.dart` | QR display, interface picker dropdown, countdown timer, status text |
| `lib/widgets/qr_import_screen.dart` | Camera scanner, fetch + decrypt flow, error/success states |

### Existing Files Modified

| File | Change |
|---|---|
| `lib/widgets/sync_settings_screen.dart` | Add "P2P Transfer" section with Export + Import buttons |
| `lib/screens/main_screen.dart` or host list widget | Add "Export via QR" toolbar button |

---

## Encryption

`P2PSyncEncryption` uses AES-256-GCM directly with a raw random key — no PBKDF2 derivation, because the key is already 32 cryptographically random bytes. Using PBKDF2 on a random key adds ~500ms latency with no security benefit.

```
key     = SecureRandom(32 bytes)
keyB64  = base64url.encode(key)          // embedded in QR
encrypt: nonce(12) + ciphertext + tag(16) → base64 → HTTP response body
decrypt: base64 decode → split → AesGcm.with256bits().decrypt
```

The `cryptography` package (already a dependency) is used for AES-256-GCM.

**Transport security:** HTTP is used intentionally — data is AES-256-GCM encrypted before transmission, so plaintext is never on the wire. An attacker on the same network can capture the ciphertext but cannot decrypt without the key embedded in the QR code.

---

## Network Interface Support

`NetworkInterface.list()` from `dart:io` enumerates all IPv4 interfaces (WiFi, Ethernet, Tailscale `100.x.x.x`, other VPNs). The interface picker dropdown in `QrExportDialog` shows all non-loopback IPv4 interfaces, defaulting to the first one. This handles LAN, Tailscale, and any other IP-routable network transparently.

---

## UI

### Export entry points (Device A)

1. **Sync Settings** — "P2P Transfer" section with "Show QR Code" button
2. **Host list** — "Export via QR" icon in toolbar/action menu

Both open `QrExportDialog`:
- Interface picker dropdown (shown before QR if multiple interfaces detected)
- QR code rendered by `qr_flutter`
- Countdown: `2:00 → 0:00`
- Status: `"Waiting for device to scan..."` → `"Connected! Transferring..."` → `"Done ✓"`
- "Cancel" button closes server early

### Import entry point (Device B)

Sync Settings → "P2P Transfer" section → "Scan QR Code" button → `QrImportScreen`:
- Full-screen camera preview with crosshair overlay (`mobile_scanner`)
- Auto-detect QR → show loading spinner
- On success: dismiss + show snackbar with host count
- On error: inline error message with retry option

---

## Error Handling

| Scenario | Behavior |
|---|---|
| No network interface available | Show inline error, do not open server |
| Server bind fails (port conflict) | Retry up to 3 times with port 0 (OS re-assigns) |
| Device B fetch timeout (5s) | `"Cannot reach device. Make sure both devices are on the same network."` |
| Decrypt failure | `"Invalid QR code."` |
| Server session expires (2 min) | Auto-close server, show `"Session expired"` in dialog |
| Import results in 0 hosts | Warning: `"No hosts found in transfer"` (do not replace existing hosts) |

---

## Dependencies

| Package | Purpose | Status |
|---|---|---|
| `qr_flutter` | Render QR code widget | **New** |
| `mobile_scanner` | Camera-based QR scanning (macOS + Windows) | **New** |
| `cryptography` | AES-256-GCM | Already present |
| `network_info_plus` | (Superseded by `NetworkInterface.list()`) | Already present, not used for this feature |
| `dart:io` | `HttpServer`, `NetworkInterface` | SDK built-in |

---

## Testing

- **Unit tests** for `P2PSyncEncryption`: encrypt → decrypt roundtrip, wrong key throws
- **Unit tests** for `P2PSyncService`: server starts → client fetches → server closes after one request; timeout behavior
- **Integration test**: start server on localhost → client fetches → verify `SyncService.parsePayload` output matches input
- **Widget tests** for `QrExportDialog`: mock server, verify countdown, verify status text transitions
- **Widget tests** for `QrImportScreen`: mock scanner result, mock HTTP client, verify host import call

No real two-device setup required for automated tests.
