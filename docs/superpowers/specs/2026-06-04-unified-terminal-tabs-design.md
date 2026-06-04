# Unified Terminal Tabs — Local Sessions in the Top Tab Bar

**Date:** 2026-06-04
**Status:** Approved

## Problem

Local terminal sessions live in a separate sidebar screen (`NavSection.localTerminal` → `LocalTerminalScreen`) with their own internal tab bar, managed by `LocalSessionProvider`. Remote SSH sessions appear as tabs in the global top tab bar, managed by `SessionProvider`. The two cannot be cycled with hotkeys together, cannot be reordered together, and local sessions get none of the SSH tab features (split view, tab metadata, recording).

## Goal

Full unification: local terminal sessions become first-class peers of SSH sessions — same top tab row, same hotkeys (next/prev/close), full-screen display via the same content area, split-view mixing, tab metadata (rename/color/pin), and asciicast recording.

## Design

### 1. Model — `TerminalSession` interface

New file `app/lib/models/terminal_session.dart`:

```dart
abstract class TerminalSession {
  String get id;
  Terminal get terminal;
  String get tabLabel;
  String? customLabel;
  String? colorTag;
  bool isPinned;
  bool get isLocal;
  Future<void> close();
}
```

- `SshSession` implements it — already has every field; `isLocal` returns `false`, `close()` delegates to the existing disconnect path.
- `LocalSession` implements it — gains `customLabel`, `colorTag`, `isPinned` (in-memory only, not persisted), `isLocal` returns `true`, `close()` kills the PTY. Default `tabLabel` is `Local N` (monotonic counter per app run). Keeps its own `LocalSessionStatus` (running/exited/error).

### 2. `SessionProvider` — single unified session list

- `sessions` becomes `List<TerminalSession>` (was `List<SshSession>`).
- New getter `sshSessions` → `sessions.whereType<SshSession>()` for SSH-only consumers (plugin context `activeSessions`, AI chat exec, SFTP host pickers, HookBus lifecycle, sync).
- SSH-specific logic (reconnect, host-key verification, host-scoped tab metadata via `TabMetadataService`) applies only to `SshSession` entries.
- New `newLocalSession()` — spawns a PTY via `LocalShellService` (injected from `main.dart`), adds the `LocalSession` to the unified list, sets it active.
- `activateNext()` / `activatePrev()` / `closeActive()` / reorder operate on the unified list — hotkeys work across both types with no further changes.
- Local tab metadata (rename/color/pin) is set directly on the session object; `TabMetadataService` is not involved and nothing persists across restarts.
- **Deleted:** `LocalSessionProvider` (logic absorbed into `SessionProvider`) and `LocalTerminalScreen` (no longer reachable).

### 3. Tab bar + sidebar (`main_screen.dart`)

- The reorderable session tab row renders the unified list. Local tabs show a computer/terminal icon in place of the SSH status dot. The existing tab context menu (rename / color / pin / close) works for both types.
- The "+" button becomes a two-item menu: **New SSH session** (opens the host panel, unchanged) and **New local terminal** (`SessionProvider.newLocalSession()`).
- The **Local Terminal** sidebar item remains but becomes an action, not a screen: if any local session exists, focus the most recently active local tab; otherwise create a new one. `NavSection.localTerminal` no longer maps to content in `_buildContent`.

### 4. Split view

- `SplitTerminalView` pane allocation logic is unchanged (still `sessions[paneIndex]` from the unified list). Each pane branches on session type:
  - `SshSession` → `SessionTerminalView` (unchanged: search, shell integration, command history, recording button, status views).
  - `LocalSession` → new `LocalTerminalPane`: xterm `TerminalView` + status overlay for exited/error (with a **Restart shell** button) + recording button.
- Search, shell integration, and command-history autocomplete remain SSH-only in this iteration. The shared input bar still works against local panes (it only calls `sendInput`).

### 5. Recording for local sessions

- The PTY output pump (where `pty output → terminal.write` happens in `LocalShellService` / `LocalSession`) additionally calls `RecordingService.writeOutput(sessionId, data)` and `RecordingService.onShellClosed(sessionId)` on exit — the same passive-intercept pattern `SshService` uses (no-ops when not recording).
- `RecordingProvider.startRecording` accepts `TerminalSession` instead of `SshSession`.
- Local recordings are written to `{basePath}/local/session_YYYY-MM-DD_HH-mm-ss.cast`. `RecordingEntry`'s path parser naturally yields `hostTitle = "local"` — no parser changes.

### 6. Edge cases

- **SSH-only consumers:** plugin `ssh.exec`/`sftp.*`, AI chat command execution, and SFTP screens consume `sshSessions`. When the active session is local, these features skip it or report "not available for local sessions" — they must not crash on a `LocalSession`.
- **Session IDs:** both types use UUIDs; per-session keyed providers (`CommandHistoryProvider`, `ShellIntegrationProvider`, `RecordingProvider`) are collision-safe.
- **Sync:** untouched — local sessions never reach `HostProvider` or `SyncService`.

### 7. Testing

- Unit tests for `SessionProvider` mixed-list operations: next/prev/close/reorder across interleaved local + SSH sessions; active-session transitions when closing a local tab.
- Default label assignment (`Local 1`, `Local 2`, …).
- Recording wiring for local sessions (writeOutput / onShellClosed pass-through).
- `flutter analyze` clean and the existing test suite passes.

## Out of scope

- Shell integration (OSC 7/133) for local shells.
- Command-history autocomplete and terminal search for local panes.
- Persisting local tab metadata or restoring local sessions across app restarts.
