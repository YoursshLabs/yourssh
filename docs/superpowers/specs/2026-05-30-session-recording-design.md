# Session Recording — Design Spec

**Date:** 2026-05-30  
**Status:** Approved

---

## Overview

Add SSH session recording to YourSSH. Records terminal I/O in **Asciinema v2 (asciicast)** format. Per-host auto-record setting with manual start/stop override. Recordings stored under a global base path with per-host subfolders. Browseable via a dedicated Recording Library screen with in-app playback.

---

## Architecture

### New Components

| Layer | Component | Responsibility |
|---|---|---|
| Service | `RecordingService` | Write `.cast` files, track active recordings |
| Provider | `RecordingProvider` | State management, library scan from disk |
| Model | `RecordingEntry` | Metadata for one recording file |
| Widget | `RecordingLibraryScreen` | Sidebar screen: list + delete + launch playback |
| Widget | `RecordingPlayerWidget` | In-app asciicast playback with controls |

### Data Flow

```
SshService.openShell()
  └─ stdout chunk → RecordingService.writeOutput(sessionId, text)   ← passive intercept
                         └─ if isRecording(sessionId) → append event line

SessionProvider._doConnect()
  └─ if host.autoRecord → RecordingProvider.startRecording(session) ← auto trigger
                               └─ RecordingService.startRecording(...)

Manual UI → RecordingProvider.startRecording / stopRecording
```

`RecordingService` is passive: `SshService` always notifies it, service no-ops when no recording is active for that session.

### Changes to Existing Code

| File | Change |
|---|---|
| `SshService` | Accept `RecordingService` via constructor; call `writeOutput` + `onShellClosed` in `openShell()` |
| `SessionProvider` | After `status = connected`, if `host.autoRecord` call `recordingProvider.startRecording(session)` |
| `Host` model | Add `autoRecord: bool` (default `false`) |
| `SettingsProvider` | Add `recordingPath: String` (default `~/Documents/YourSSH/Recordings`) |
| `main_screen.dart` | Add `NavSection.recordings` to sidebar |
| `main.dart` | Wire `RecordingService` + `RecordingProvider` into provider tree |

---

## Data Models

### Asciicast v2 File Format

```
{"version":2,"width":80,"height":24,"timestamp":1748600000,"title":"ubuntu@prod"}
[0.000,"o","$ "]
[1.234,"o","ls -la\r\n"]
[2.100,"o","total 32\r\n..."]
```

Header = single JSON line. Each event = `[elapsed_seconds, type, data]` where type `"o"` = stdout output.

### File Naming

```
{globalPath}/{username}@{hostname}/session_YYYY-MM-DD_HH-mm-ss.cast
```

Example: `~/Documents/YourSSH/Recordings/ubuntu@prod.example.com/session_2026-05-30_09-00-00.cast`

### RecordingEntry

```dart
class RecordingEntry {
  final String filePath;
  final String hostTitle;    // "user@host"
  final DateTime recordedAt; // parsed from filename
  final Duration? duration;  // null if in-progress; parsed from last event line
  final int? fileSize;       // bytes
}
```

### Internal RecordingService State

```dart
class _ActiveRecording {
  final IOSink sink;
  final Stopwatch stopwatch;
  final String filePath;
}

Map<String, _ActiveRecording> _active; // keyed by sessionId
```

### Settings Addition

- Key: `recordingPath`
- Type: `String`
- Default: `{homeDirectory}/Documents/YourSSH/Recordings`

### Host Model Addition

- Field: `autoRecord: bool`, default `false`
- Serialized in `Host.toJson()` / `Host.fromJson()`

### Library Scan

`RecordingProvider.refreshLibrary()` uses `Directory.list(recursive: true)`, filters `*.cast`, sorts by `recordedAt` descending. File duration is read lazily (last line of file) only when needed for display.

---

## UI Components

### 1. Session Tab — Recording Indicator

Red dot (●) appended to tab label when session is actively recording. Reads `RecordingProvider.isRecording(sessionId)`.

### 2. Terminal Toolbar — Record Button

Icon button in terminal view corner:
- Idle: `Icons.fiber_manual_record` (grey)
- Recording: `Icons.stop` (red)
- Tap → `RecordingProvider.startRecording` / `stopRecording`

### 3. Host Detail Panel — Auto-Record Toggle

Toggle "Auto-record sessions" in host settings panel, bound to `host.autoRecord`. Saved via `HostProvider`.

### 4. Settings Screen — Recording Path

Row "Recording Path" showing current path + "Change…" button. Button opens `FilePicker.getDirectoryPath()`. Updates `SettingsProvider.recordingPath`.

### 5. Recording Library Screen

New sidebar entry (`NavSection.recordings`, icon: `Icons.video_library`).

Layout: recordings grouped by host, sorted by date descending.

```
Recording Library
────────────────────────────────────
[ubuntu@prod]        2 recordings
  session_2026-05-30_09-00   12m 34s  48 KB   [▶ Play]  [🗑]
  session_2026-05-29_17-22    5m 10s  18 KB   [▶ Play]  [🗑]

[ubuntu@staging]     1 recording
  session_2026-05-28_11-05    8m 02s  31 KB   [▶ Play]  [🗑]
```

Delete shows confirmation dialog before removing file from disk.

### 6. RecordingPlayerWidget

Shown inline (right panel) or full-screen overlay when Play is clicked.

- Uses a dedicated `xterm.Terminal` instance (read-only — no `onOutput` wired)
- Parses all events from `.cast` file on open
- `Timer`-driven playback: schedules each event at `elapsed / speed`
- Controls: ▶/⏸ Play/Pause, speed selector (0.5× / 1× / 2× / 5×), progress scrubber (LinearProgressIndicator), elapsed/total timestamp label

---

## Error Handling

- If `globalPath` directory does not exist → create on first recording start
- If file write fails mid-session → log error, stop recording silently (do not interrupt SSH session)
- If `.cast` file is corrupt/truncated → skip entry in library scan, show parse error inline in player

---

## Out of Scope

- Recording stdin (user input) — only stdout is captured
- Cloud upload / sharing of recordings
- Compression of `.cast` files
- Recording local terminal sessions (`LocalSessionProvider`)
