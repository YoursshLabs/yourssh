# OSC 52 Clipboard Design

**Date:** 2026-06-14
**Feature:** OSC 52 clipboard — let remote apps (tmux, vim) write to the local clipboard via the OSC 52 escape sequence
**Priority:** P1 (Terminal UX & protocol support)

---

## Goal

Let a program on the remote host write to the user's local system clipboard through the
`OSC 52` escape sequence (`ESC ] 52 ; Pc ; Pd ST`). This is what makes `tmux set-clipboard`,
vim/neovim with the OSC 52 clipboard providers, and similar tools put text on the local
machine's clipboard across an SSH session — without a SFTP round-trip or mouse selection.

**Write only.** The read side of OSC 52 (a query `OSC 52 ; c ; ?` that asks the terminal to
report the local clipboard back to the remote) is deliberately **not** implemented: it lets a
remote server exfiltrate whatever is on the user's clipboard (passwords, tokens). Most
terminals disable read by default for the same reason.

**Opt-in per host, default off.** A remote that can write the clipboard can stage a
paste-injection (set the clipboard to a malicious command the user later pastes into a shell).
The feature is therefore gated behind a per-host toggle that defaults off, matching the
existing `Host.agentForwarding` opt-in pattern.

---

## Key finding

OSC 52 already reaches the app. The xterm parser special-cases only OSC `0`/`1`/`2` (title /
icon) and routes **every other** OSC code to `handler.unknownOSC(ps, args)` →
`Terminal.onPrivateOSC(code, args)` (`packages/xterm/lib/src/core/escape/parser.dart`
`_escHandleOSC`, `terminal.dart:917`). For `ESC ] 52 ; c ; <base64> ST` the callback fires as
`onPrivateOSC('52', ['c', '<base64>'])`. `_consumeOsc` accumulates the full payload into a
`StringBuffer` until BEL/ST with **no length cap**, so large clipboard payloads are not
truncated by the parser.

Consequence: the **write path needs no change to the xterm core.** The work is to route code
`52` in the app, decode it, gate it per-host, and call `Clipboard.setData` (which lives in
`flutter/services`, i.e. the app layer — not the pure-Dart xterm core).

One wiring gap: `SshService.openShell` only assigns `terminal.onPrivateOSC` when shell
integration is active (`ssh_service.dart:605` — `siOn`). For OSC 52 to work independently of
shell integration, the callback must be wired whenever **either** shell integration **or**
OSC 52 is enabled, and the callback must dispatch by code.

---

## Architecture (app-layer routing — no xterm fork change)

### 1. `app/lib/services/osc52_clipboard.dart` (new, pure — no Flutter import)

Parses the OSC 52 argument list into a typed result. Pure so it is unit-testable without a
terminal or Flutter binding.

```dart
const int kOsc52MaxBytes = 1 << 20; // 1 MiB decoded cap

sealed class Osc52Result {}
class Osc52Write   extends Osc52Result { final String text; Osc52Write(this.text); }
class Osc52Ignored extends Osc52Result {} // read query, bad base64, oversized, empty

class Osc52Clipboard {
  /// `args` is the tail after the code, i.e. `['c', '<base64>']` for
  /// `OSC 52 ; c ; <base64>`. Returns [Osc52Write] only for a valid, in-cap,
  /// UTF-8-decodable write; everything else maps to [Osc52Ignored] (fail-soft).
  static Osc52Result parse(List<String> args);
}
```

Rules:
- First element is the selection target (`c`/`p`/`s`/`0`–`7`/empty). Desktop has a single
  system clipboard, so the target is ignored — all map to the system clipboard.
- The data element is the last element. If it is `?` → read query → `Osc52Ignored` (never
  read the local clipboard).
- Base64-decode the data (`base64.decode`, tolerant of missing padding via normalization). On
  `FormatException` → `Osc52Ignored`.
- If decoded length > `kOsc52MaxBytes` → `Osc52Ignored`.
- Decode bytes as UTF-8 (`utf8.decode(..., allowMalformed: true)`) → `Osc52Write(text)`.
- Empty / malformed arg list → `Osc52Ignored`.

### 2. `app/lib/models/host.dart`

Add `bool osc52Clipboard = false`:
- Constructor default `false`.
- `toJson`: `'osc52Clipboard': osc52Clipboard`.
- `fromJson`: `(json['osc52Clipboard'] as bool?) ?? false` (old rows / sync payloads default
  off).
- `copyWith` parameter.

Rides the existing Supabase + P2P sync (host JSON is synced as-is).

### 3. `app/lib/services/ssh_service.dart`

Change the `onPrivateOSC` wiring in `openShell`:

```dart
final siOn = /* unchanged */;
final osc52On = session.host.osc52Clipboard;
if (siOn || osc52On) {
  session.terminal.onPrivateOSC = (code, args) {
    if (code == '52' && osc52On) {
      final r = Osc52Clipboard.parse(args);
      if (r is Osc52Write) {
        clipboardWriter(r.text); // injected; default Clipboard.setData
      }
      return;
    }
    if (siOn) {
      shellIntegration!.handleOsc(
        session.id, code, args, session.terminal.buffer.absoluteCursorY);
    }
  };
}
```

`clipboardWriter` is a `Future<void> Function(String text)` field on `SshService`
(constructor-injected, like the other callbacks) defaulting to:
```dart
(text) => Clipboard.setData(ClipboardData(text: text));
```
so tests assert on it without a platform clipboard. The write is silent — no SnackBar, no
notification (per-host opt-in is the security gate; matches iTerm2/kitty/wezterm).

### 4. `app/lib/widgets/host_detail_panel.dart`

Add an "OSC 52 clipboard" `SwitchListTile` in the SSH section, next to the Agent forwarding /
Shell integration toggles. Hidden when the host protocol is RDP (same as the other SSH-only
toggles). Subtitle: a one-line security note, e.g. "Let remote apps (tmux, vim) set your local
clipboard. Off by default — only enable for hosts you trust." `_save` carries the new field.

---

## Data flow

```
remote app  ──ESC]52;c;<base64>ST──▶  PTY  ──▶  xterm parser (_escHandleOSC)
   └─▶ handler.unknownOSC('52', ['c','<base64>'])
        └─▶ Terminal.onPrivateOSC('52', ['c','<base64>'])
             └─▶ SshService dispatcher  (host.osc52Clipboard?)
                  └─▶ Osc52Clipboard.parse → Osc52Write(text)
                       └─▶ clipboardWriter(text)  ⇒  Clipboard.setData
```

---

## Security & fail-soft

- **Write only.** A `?` data field (read query) is ignored — the local clipboard is never read
  or sent to the remote.
- **Opt-in, default off** per host; RDP hosts never see the toggle.
- **Size cap** of 1 MiB decoded prevents a remote from flooding the clipboard.
- **Fail-soft:** invalid base64, oversized payload, or empty args silently map to `Osc52Ignored`
  — the terminal never crashes and nothing is written.
- Silent write (no UI feedback) by design.

---

## Testing

**`test/services/osc52_clipboard_test.dart`** (pure unit):
- Valid write: `['c', base64('hello')]` → `Osc52Write('hello')`.
- Empty selection: `['', base64('x')]` → write (mapped to system clipboard).
- Read query: `['c', '?']` → `Osc52Ignored`.
- Invalid base64: `['c', '!!!notb64']` → `Osc52Ignored`.
- Oversized: decoded > 1 MiB → `Osc52Ignored`.
- Non-UTF8 bytes: decoded with `allowMalformed` → `Osc52Write` (no throw).
- Malformed arg list (`[]`, `['52']`) → `Osc52Ignored`.

**`test/services/ssh_service_osc52_test.dart`** (dispatch, fake `clipboardWriter`):
- Code `52` + `host.osc52Clipboard = true` → `clipboardWriter` called with decoded text.
- Code `52` + toggle off → `clipboardWriter` not called; `onPrivateOSC` may not even be wired.
- Codes `7`/`133` still route to shell integration when `siOn`.
- A payload fed across two chunks (mid-base64 split) composes to one write — documents the
  parser's existing resume behavior (same as a long title OSC).

**`test/models/host_osc52_test.dart`**: `toJson`/`fromJson` round-trip (default false on a row
without the key), `copyWith`.

---

## Out of scope

- OSC 52 **read** / clipboard query (security; deliberately rejected).
- Primary-selection vs clipboard distinction (desktop has one system clipboard).
- A global Settings toggle — per-host opt-in is sufficient (revisit only if users ask).
- Any xterm core/UI fork change.
