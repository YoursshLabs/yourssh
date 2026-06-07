# Local Shell Picker — Design

**Date:** 2026-06-06
**Status:** Approved

## Problem

The local terminal hardcodes its shell: `powershell.exe` on Windows, `$SHELL ?? /bin/zsh` elsewhere (`LocalShellService.resolveShell`). Windows users who work in Git Bash, WSL, or PowerShell 7 cannot use their preferred shell inside yourssh. macOS/Linux users likewise cannot pick anything other than `$SHELL`.

## Goals

- All platforms can choose which shell the local terminal runs.
- A default shell is configurable in Settings; the new-terminal button also offers a per-session picker (split button, Windows Terminal style).
- Installed shells are auto-detected; users can also add a custom executable + arguments.
- No behavior change for users who never touch the feature (`defaultShellId == null` → today's `resolveShell` path; no migration).

## Non-goals (YAGNI)

- Per-profile working directory, environment variables, icons, tab colors.
- Argument quoting in the custom-profile args field (plain space-split; the UI says so).
- Switching the shell of an already-running session.
- Full profile-management UI (edit/reorder/duplicate à la Windows Terminal).

## Design

### 1. Model — `ShellProfile` (`app/lib/models/shell_profile.dart`)

```dart
class ShellProfile {
  final String id;          // stable across restarts (see ID scheme below)
  final String name;        // "PowerShell", "Git Bash", "WSL · Ubuntu", "zsh"…
  final String executable;  // absolute path, or bare name resolved via PATH
  final List<String> args;  // e.g. ['-d', 'Ubuntu'] for WSL
  final bool isCustom;      // true = user-added, persisted
}
```

**ID scheme** (stable so `defaultShellId` survives restarts without persisting detected profiles):

| Source | id |
|---|---|
| Windows PowerShell | `powershell` |
| cmd | `cmd` |
| PowerShell 7 | `pwsh` |
| Git Bash | `git-bash` |
| WSL distro | `wsl-<distroName>` |
| /etc/shells entry | `etc-<path>` (e.g. `etc-/bin/zsh`) |
| Custom | `custom-<uuid>` |

- Detected profiles are **not** persisted — re-detected each launch. Only custom profiles serialize to JSON (`toJson`/`fromJson` round-trip).
- `LocalSession` gains a nullable `profile` field so "Restart shell" relaunches the same shell, and `tabLabel` defaults to `"<profile.name> N"` when a profile was used ("Git Bash 2"), keeping "Local N" for the platform default.

### 2. Detection — `app/lib/services/shell_detection.dart`

Follows the `os_detection.dart` pattern: parsing is pure (unit-testable), IO injected via callbacks.

**Windows candidates, in list order:**

1. `powershell.exe` — always present, listed first. (The *platform default* when `defaultShellId == null` is whatever `resolveShell` returns — `powershell.exe` on Windows — independent of list order.)
2. `cmd.exe` — always present.
3. PowerShell 7 — `pwsh.exe` on PATH, else `%ProgramFiles%\PowerShell\7\pwsh.exe`.
4. Git Bash — first hit of `%ProgramFiles%\Git\bin\bash.exe`, `%ProgramFiles(x86)%\Git\bin\bash.exe`, `%LocalAppData%\Programs\Git\bin\bash.exe`.
5. WSL — run `wsl.exe --list --quiet`; one profile per distro: executable `wsl.exe`, args `['-d', '<distro>']`. Output is **UTF-16LE** — pure `parseWslDistroList(List<int> bytes)` decodes, strips CRLF/blank lines, and is tested separately. Any `wsl.exe` failure (missing, non-zero exit, no distros) yields no WSL profiles — never throws.

**macOS/Linux:**

- Read `/etc/shells`; pure `parseEtcShells(String content)` drops comments/blanks and dedupes.
- Filter to paths that exist on disk.
- The current `$SHELL` value is always first in the list (added if missing from `/etc/shells`).

**API:** `Future<List<ShellProfile>> detectShells()`. Every failure degrades to an empty/partial list — detection must never block opening a terminal.

### 3. Settings & persistence — `SettingsProvider`

- `defaultShellId: String?` — `null` means platform default (today's behavior; no migration needed).
- `customShellProfiles: List<ShellProfile>` — JSON list in prefs key `customShellProfiles`.
- **Resolution:** look up `defaultShellId` in detected + custom profiles. If not found (shell uninstalled, distro removed), fall back to the platform default and write a yellow warning line into the new session's terminal (same pattern as the agent-forwarding refusal warning) — never an error state.

### 4. Spawn — `LocalShellService`

- `openShell({ShellProfile? profile})`; `restartShell` reuses `session.profile`.
- `PtyFactory` typedef gains a `List<String> args` parameter → `Pty.start(shell, arguments: args, …)` (the local flutter_pty fork already supports `arguments`).
- `profile == null` → existing `resolveShell(Platform.environment, isWindows: …)` path, unchanged.
- Spawn failure → existing error path (`LocalSessionStatus.error` + error view + Restart button).

### 5. UI

**Settings → Terminal — "Default local shell":**

- Dropdown: *Platform default* + detected profiles + custom profiles.
- "Add custom shell…" opens a dialog: display name, executable (via `file_selector`), arguments (single text field, split on spaces; helper text states quoting is unsupported).
- Custom profiles show a delete button. Deleting the profile that is the current default resets `defaultShellId` to `null`.

**New-terminal button (`main_screen.dart`):**

- Plain click → default shell (resolution above).
- Becomes a split button: a dropdown arrow opens a menu listing *Platform default* plus all detected and custom profiles (same set as the Settings dropdown); choosing one opens a session with that shell.
- `SessionProvider.newLocalSession({ShellProfile? profile})` threads the choice through; `LocalShellService.openShell` receives it.

### 6. Error handling summary

| Failure | Behavior |
|---|---|
| `wsl.exe` missing / errors | No WSL profiles; detection continues |
| `/etc/shells` unreadable | Only `$SHELL` profile listed |
| `defaultShellId` dangling | Platform default + yellow terminal warning |
| Custom executable gone at spawn | Existing error view + Restart button |
| Detection throws anywhere | Caught; partial/empty list; terminal still opens |

### 7. Testing

- **Pure units:** `parseWslDistroList` (UTF-16LE bytes, CRLF, blank lines, empty output), `parseEtcShells` (comments, dupes), default-shell resolution incl. dangling-id fallback, `ShellProfile` JSON round-trip.
- **`LocalShellService`:** fake `PtyFactory` asserting the executable and args passed for a given profile; null profile keeps current `resolveShell` behavior; restart reuses `session.profile`.
- **Detection service:** injected fake file-exists / process-run callbacks per platform branch.
