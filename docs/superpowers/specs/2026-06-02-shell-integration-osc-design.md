# Shell Integration (OSC 7 / OSC 133) — Design

> Status: approved (design) · 2026-06-02
> Roadmap item: P1 · Terminal UX & protocol support — "Shell integration (semantic prompts)"

## Goal

Make yourssh aware of what the remote shell is doing by parsing the de-facto
**semantic-prompt** escape sequences (OSC 133) and the **current-directory**
report (OSC 7). From that signal, deliver four user-visible wins in v1:

1. **cwd in tab title + status bar** — show the working directory of the focused
   session.
2. **Per-command status markers** — a colored dot in a left gutter next to each
   command's prompt line (green = exit 0, red = non-zero, grey = running).
3. **Jump-to-prompt** — `Cmd/Ctrl+↑/↓` scrolls between command prompt lines.
4. **cwd-aware autocomplete** — path completion in the input bar sourced from a
   live listing of the resolved remote directory.

The remote shell does not emit these sequences by default, so yourssh injects a
small prompt-hook script into the shell on connect (bash/zsh only).

## Scope decisions (from brainstorming)

- **Injection policy:** auto-inject, **opt-out per host**. Default ON for bash
  and zsh; a global toggle (`SettingsProvider.shellIntegrationEnabled`) and a
  per-host override (`Host.shellIntegration`) can disable it. The script mutates
  only the **live shell session** (sets hooks), never the user's `.bashrc`/`.zshrc`.
- **Shell support:** bash and zsh only. Any other shell (fish, POSIX sh, network
  gear) gets no injection; the feature is simply inactive — nothing breaks.
- **v1 includes all four features**, including autocomplete (built internally in
  phases — see Phasing).
- **Marker rendering = Approach A (inline gutter overlay)**, not a separate
  timeline panel and not an xterm fork.
- **OSC capture = `Terminal.onPrivateOSC`** (see Background) — no manual stdout
  parsing, no HookBus involvement.

## Background — why this is feasible without forking xterm

xterm.dart 4.0.0 parses every OSC sequence and reassembles it across read
chunks via its escape state machine. It natively handles only OSC 0/1/2
(title/icon); **every other code falls through to `unknownOSC` →
`Terminal.onPrivateOSC(code, args)`** and the raw bytes are consumed (never
rendered as garbage):

- `xterm-4.0.0/lib/src/core/escape/parser.dart:1060-1079` — switch handles
  `'0'`/`'1'`/`'2'`, else `handler.unknownOSC(_osc[0], _osc.sublist(1))`.
- `xterm-4.0.0/lib/src/terminal.dart:64` — `void Function(String code, List<String> args)? onPrivateOSC`.

So setting `session.terminal.onPrivateOSC` gives us OSC 7 and OSC 133 fully
parsed, with `args` already split on `;`.

**Scroll/jump feasibility:** xterm has no per-line decoration API and no
`scrollToLine`. `Terminal.scrollUp/Down` is the VT100 scroll-region op (it
shifts buffer content — do NOT use it for navigation). The real viewport scroll
is a Flutter `ScrollController` that the app **already** owns and drives:

- `app/lib/widgets/terminal_view.dart:53` — `final _scrollController = ScrollController();`
- `:349` — passed to `TerminalView(scrollController: _scrollController, …)`.
- `:164-176` — `_scrollToMatch` scrolls to `lineIdx * (fontSize * 1.35)` clamped
  to `maxScrollExtent`. Jump-to-prompt and gutter positioning reuse this exact
  line→pixel conversion.

**Absolute line index** for a prompt comes from
`Terminal.buffer.absoluteCursorY` (`xterm-4.0.0/lib/src/core/buffer/buffer.dart:87`)
captured when the OSC 133;A marker arrives.

## OSC contract used

Terminator: BEL (`\a`, 0x07); ST (`ESC \`) is also accepted by the parser.

| Sequence | Meaning | Emitted by |
|---|---|---|
| `OSC 7 ; file://<host>/<path>` | report cwd | precmd hook (each prompt) |
| `OSC 133 ; A` | prompt start | precmd hook |
| `OSC 133 ; B` | prompt end / input start | end of `PS1` |
| `OSC 133 ; C` | command pre-exec | preexec hook / `DEBUG` trap |
| `OSC 133 ; D ; <exit>` | command finished + exit code | precmd hook (next cycle) |

Command **text** is not carried over OSC in v1; it is read best-effort from the
buffer prompt line at finalize time (tooltip only — not required for the dot,
exit code, or duration).

## Components & files

### New

- `app/lib/models/shell_command.dart`
  - Immutable-ish `ShellCommand`:
    `{ String? cwd, String? text, int promptLine, DateTime startedAt, DateTime? finishedAt, int? exitCode }`.
  - Helpers: `bool get isRunning => finishedAt == null;`
    `bool? get succeeded => exitCode == null ? null : exitCode == 0;`
    `Duration? get duration`.
- `app/lib/models/shell_session_state.dart`
  - `ShellSessionState`: `String? cwd`, `List<ShellCommand> commands`,
    `int? pendingIndex`. Mutation methods: `onPromptStart(promptLine, cwd)`,
    `onExec(text)`, `onFinished(exitCode)`, `setCwd(path)`.
  - Caps `commands` length (e.g. last 500) to bound memory.
- `app/lib/services/shell_integration_service.dart`
  - **Pure, no Flutter deps.** Two responsibilities:
    1. `String buildInjectionScript()` — returns the one-line bash/zsh setup
       (guarded + idempotent; see below).
    2. `ShellOscEvent? parseOsc(String code, List<String> args)` — maps an OSC
       callback into a typed event (`Cwd(path)`, `PromptStart`, `Exec`,
       `Finished(exit)`), returning `null` for anything irrelevant/malformed.
  - Parses `file://host/path` → decoded path (percent-decoding, strips host).
- `app/lib/providers/shell_integration_provider.dart`
  - `ShellIntegrationProvider extends ChangeNotifier`.
  - `Map<String, ShellSessionState> _states` keyed by `sessionId`.
  - `void handleOsc(String sessionId, String code, List<String> args, Buffer buffer)`
    — runs `parseOsc`, applies to the session state (using
    `buffer.absoluteCursorY` for `promptLine`), `notifyListeners()`.
  - `ShellSessionState? stateFor(String sessionId)`, `String? cwdFor(id)`.
  - `void clear(String sessionId)` on disconnect.

### Modified

- `app/lib/services/ssh_service.dart`
  - In `connect`, after the shell is opened and after the tmux/`initialCommand`
    writes (current lines ~349-354): if the global toggle is on and the host is
    not opted out, `shell.write(injectionScript)`.
  - Set `session.terminal.onPrivateOSC = (code, args) =>
    shellIntegration.handleOsc(session.id, code, args, session.terminal.buffer);`
    when wiring the shell stream (near the existing `onOutput` wiring, ~397).
  - Constructor gains an optional `ShellIntegrationProvider? shellIntegration`
    (injected from `main.dart`, same pattern as `hookBus`). On disconnect, call
    `shellIntegration?.clear(id)` and null out `onPrivateOSC`.
- `app/lib/models/host.dart`
  - Add `bool shellIntegration` (default `true`); include in JSON
    (tolerant parse — missing key → `true`).
- `app/lib/providers/settings_provider.dart`
  - Add `bool shellIntegrationEnabled` (default `true`) persisted in prefs.
- `app/lib/main.dart`
  - Instantiate `ShellIntegrationProvider`, register in `MultiProvider`, inject
    into `SshService`.
- `app/lib/widgets/terminal_view.dart`
  - **Gutter overlay**: wrap the `TerminalView` in a `Stack` with a left strip
    (~8px) painted by a `CustomPainter` that, for each `ShellCommand` whose
    `promptLine` is in the visible range, draws a dot at
    `y = promptLine * (fontSize*1.35) - _scrollController.offset`. Repaints on
    `_scrollController` ticks (already a listener target) and on provider notify.
    Tapping a dot calls the jump helper.
  - **Jump-to-prompt**: add `Shortcuts`/`Actions` (local to the terminal view,
    no global hotkey) for `Cmd/Ctrl+↑` / `Cmd/Ctrl+↓` → scroll to the
    prev/next `promptLine` reusing the `_scrollToMatch` math.
- `app/lib/screens/main_screen.dart`
  - The tab label is rendered at `:1395` from `session.tabLabel`. The tab
    builder additionally reads `ShellIntegrationProvider.cwdFor(id)` and, when no
    `customLabel` is set and a cwd is known, composes
    `<tabLabel> · <basename(cwd)>`. `SshSession`/`tabLabel` themselves are **not
    modified** — the cwd lives in the provider and the composition is display-only.
- `app/lib/widgets/terminal_input_bar.dart`
  - When the current token is a path (contains `/`, or the first word is a
    path-taking command like `cd`/`ls`/`cat`/`cp`/`mv`/`./`), debounce ~120ms,
    resolve `cwd + prefixDir` via `ShellIntegrationProvider`, list it through
    `SshService.sftp` (cancel in-flight on new keystroke), and **merge** the
    directory entries into `_suggestions` ahead of history matches. No cwd or
    SFTP error → fall back to history-only (current behavior).
- `app/lib/widgets/settings_screen.dart`
  - A "Shell integration" toggle under the terminal section.
- `app/lib/widgets/host_detail_panel.dart`
  - A per-host "Shell integration" checkbox (opt-out).

## Injection script (sketch)

One guarded, idempotent line written to the shell. Pseudocode of intent (final
form minimized to a single `printf`-built string):

```sh
if [ -z "$__yourssh_si" ]; then __yourssh_si=1
  if [ -n "$ZSH_VERSION" ]; then
    __yourssh_osc7() { printf '\033]7;file://%s%s\a' "$HOST" "$PWD"; }
    __yourssh_pre() { print -n '\033]133;A\a'; __yourssh_osc7; }
    __yourssh_exec() { print -n '\033]133;C\a'; }
    __yourssh_post() { print -n "\033]133;D;$?\a"; }
    precmd_functions+=(__yourssh_post __yourssh_pre)
    preexec_functions+=(__yourssh_exec)
    PS1="%{$(printf '\033]133;B\a')%}$PS1"
  elif [ -n "$BASH_VERSION" ]; then
    __yourssh_post() { local e=$?; printf '\033]133;D;%s\a' "$e"; printf '\033]133;A\a'; printf '\033]7;file://%s%s\a' "$HOSTNAME" "$PWD"; }
    PROMPT_COMMAND="__yourssh_post;${PROMPT_COMMAND:-}"
    trap 'printf "\033]133;C\a"' DEBUG
    PS1="$PS1\[$(printf '\033]133;B\a')\]"
  fi
fi
```

Notes:
- **Append, don't overwrite** `PROMPT_COMMAND` / `precmd_functions`.
- The bash `DEBUG` trap fires for every simple command; acceptable for v1 (the
  `C` marker just opens a command window — `D` closes it). A
  fire-once-per-prompt guard is a future refinement.
- The setup line echoes once on screen (cosmetic). Minimized to a single line.

## Data flow / state machine

```
connect → open shell → [inject script] → set onPrivateOSC
   prompt cycle:
     OSC 133;D;<exit>  → state.onFinished(exit)   (finalize previous command)
     OSC 133;A         → state.onPromptStart(buffer.absoluteCursorY, cwd)
     OSC 7;file://…     → state.setCwd(path)
     (PS1 prints) OSC 133;B  → input window open (no state change in v1)
     user runs cmd:
     OSC 133;C         → state.onExec(text?=best-effort buffer read)
   → notifyListeners → tab title / status bar / gutter / suggestions update
disconnect → provider.clear(sessionId), onPrivateOSC = null
```

## Edge cases & limitations

- **Non-bash/zsh, or OSC swallowed by tmux** (no `allow-passthrough`): no
  markers/cwd. Feature degrades silently; documented limitation.
- **Malformed / partial OSC:** reassembled by xterm; `parseOsc` validates and
  drops anything unexpected.
- **Reconnect:** `clear(sessionId)` then re-inject on the new shell.
- **Recording:** OSC bytes are part of stdout, so they persist in `.cast` files;
  harmless (players ignore unknown OSC). No redaction needed.
- **Search overlay coexistence:** both the search highlight and the gutter use
  `_scrollController`; they layer in the `Stack` without conflict.
- **Memory:** `commands` capped per session.
- **Initial command / tmux:** inject **after** those writes so the markers wrap
  the user's real shell, not the bootstrap.

## Testing

- **Unit — `ShellIntegrationService`:** OSC 7 URL parsing (percent-encoding,
  host stripping, missing path); `parseOsc` for `A`/`B`/`C`/`D;<n>`/`D` and
  malformed args; `buildInjectionScript` snapshot (bash + zsh branches, guard
  present, append semantics).
- **Unit — `ShellSessionState`:** A→C→D transitions, exit-code capture,
  duration, list cap, `cwd` updates, out-of-order/duplicate markers.
- **Widget:** gutter dot vertical position vs scroll offset; jump-to-prompt
  selects the correct neighboring `promptLine`; input-bar merges path
  suggestions ahead of history and cancels stale SFTP lists.

## Out of scope / future

- Inline native decorations / precise `scrollToLine` via an **xterm fork**
  (Approach C) — only if the gutter overlay proves insufficient.
- A **command timeline panel** (Approach B) as an alternate/overview view.
- Carrying command text over a private OSC marker (vs best-effort buffer read).
- Fire-once-per-prompt `DEBUG`-trap guard for bash.
- Using shell integration to drive richer features (per-command output folding,
  re-run, copy-output).

## Phasing (for the implementation plan)

1. **Foundation** — models, `ShellIntegrationService` (parser + script),
   `ShellIntegrationProvider`, `SshService` wiring, settings + host opt-out.
   Unit-tested end to end with synthetic OSC input.
2. **cwd surfacing** — tab title composition + status bar.
3. **Gutter markers + jump-to-prompt** — overlay painter + local shortcuts.
4. **cwd-aware autocomplete** — input-bar path-suggestion merge over SFTP.
