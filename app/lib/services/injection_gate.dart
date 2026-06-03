/// What one output chunk says about injection readiness.
enum ReadinessSignal {
  /// Nothing relevant in this chunk.
  none,

  /// Bracketed paste turned on: the line editor (zle/readline) is reading
  /// input — the only moment a typed line is echoed exactly once, by the
  /// editor itself.
  editorReading,

  /// Bracketed paste turned off: the shell is executing something.
  editorBusy,

  /// Alt-screen entered (vim/less/etc.): a full-screen app owns the tty —
  /// never inject into it.
  altScreen,
}

/// Tracks terminal-mode signals that tell when it is safe to inject the
/// shell-integration bootstrap. Pure (no IO/timers); the caller owns timing.
///
/// Timing heuristics (quiescence, prompt-looking text) are not enough: a MOTD
/// stalling mid-line ("Last login:" … reverse-DNS pause) looks exactly like a
/// prompt, and instant-prompt frameworks (powerlevel10k) paint a prompt long
/// before the shell reads input. Injecting then gets the line echoed by the
/// kernel (canonical mode) mid-MOTD — mangled output, observed in the field.
/// The bracketed-paste toggle (`ESC[?2004h/l`) is the reliable signal: modern
/// zsh/bash emit `h` exactly when the editor starts reading.
class InjectionReadiness {
  String _scanTail = '';
  bool _bpEver = false;
  bool _bpOn = false;

  /// Whether bracketed paste was ever seen — a shell that has it never needs
  /// the probe fallback.
  bool get bpEver => _bpEver;

  /// Whether the line editor is reading right now (last toggle was `h`).
  bool get bpOn => _bpOn;

  ReadinessSignal onChunk(String text) {
    // Keep the previous chunk's tail so sequences split across chunk
    // boundaries are still seen.
    final scan = _scanTail + text;
    _scanTail = scan.length > 16 ? scan.substring(scan.length - 16) : scan;
    if (scan.contains('\x1b[?1049h') || scan.contains('\x1b[?47h')) {
      return ReadinessSignal.altScreen;
    }
    final hi = scan.lastIndexOf('\x1b[?2004h');
    final lo = scan.lastIndexOf('\x1b[?2004l');
    if (hi < 0 && lo < 0) return ReadinessSignal.none;
    _bpEver = true;
    _bpOn = hi > lo;
    return _bpOn ? ReadinessSignal.editorReading : ReadinessSignal.editorBusy;
  }

  static final _escapes = RegExp(
      r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)' // OSC
      r'|\x1b\[[0-9;?]*[A-Za-z]' // CSI
      r'|\x1b.' // ESC + one (charset, keypad…)
      r'|[\x00-\x08\x0b-\x1f]' // other C0 controls
      );
  static const _promptChars = r'$#%>❯➜»';

  /// Whether [s] (output accumulated since a probe) ends in something that
  /// looks like a shell prompt once escape sequences are stripped. Fallback
  /// readiness check for shells without bracketed paste (bash ≤ 5.0).
  static bool promptLikeTail(String s) {
    final visible = s.replaceAll(_escapes, '').trimRight();
    if (visible.isEmpty) return false;
    return _promptChars.contains(visible[visible.length - 1]);
  }
}

/// Result of feeding one output chunk through [InjectionGate].
class GateResult {
  /// Text to write to the terminal now; null while output is withheld.
  final String? emit;

  /// True exactly once: when the ready sentinel is first seen.
  final bool sendPayload;

  const GateResult({this.emit, this.sendPayload = false});
}

/// Withholds shell output between the shell-integration bootstrap write and
/// the done sentinel, then discards it: the held head is just the echoed
/// bootstrap line plus sentinels. Discarding (rather than writing it and
/// erasing afterwards) keeps the app-side cursor in sync with where the
/// remote shell believes it is — erase-by-cursor-math desyncs the two and
/// fancy prompts then paint over the wrong rows.
/// Pure (no IO/timers) — the caller owns the timeout.
class InjectionGate {
  InjectionGate({
    required this.readySentinel,
    required this.doneSentinel,
    this.maxHold = 2048,
  });

  final String readySentinel;
  final String doneSentinel;

  /// Largest head that can plausibly be bootstrap echo. A bigger head means
  /// real server output (late MOTD) landed inside the hold window — it is
  /// emitted instead of discarded, rendered exactly as if never held.
  final int maxHold;

  final StringBuffer _held = StringBuffer();
  bool _passthrough = false;
  bool _payloadSent = false;
  int _readyScanFrom = 0;
  int _doneScanFrom = 0;

  bool get isHolding => !_passthrough;

  /// Size of the withheld buffer.
  int get heldLength => _held.length;

  GateResult feed(String text) {
    if (_passthrough) return GateResult(emit: text);
    _held.write(text);
    final buf = _held.toString();
    var sendPayload = false;
    if (!_payloadSent && buf.contains(readySentinel, _readyScanFrom)) {
      _payloadSent = true;
      sendPayload = true;
    }
    final idx = buf.indexOf(doneSentinel, _doneScanFrom);
    // Resume the next scan one sentinel-length before this buffer's end so a
    // sentinel split across chunks is still seen, without rescanning the
    // whole held buffer on every chunk.
    _readyScanFrom = _tailFrom(buf, readySentinel);
    _doneScanFrom = _tailFrom(buf, doneSentinel);
    if (idx >= 0) {
      _passthrough = true;
      _held.clear();
      final head = buf.substring(0, idx);
      final tail = buf.substring(idx + doneSentinel.length);
      final emit = head.length > maxHold ? _strip(head) + tail : tail;
      return GateResult(emit: emit, sendPayload: sendPayload);
    }
    return GateResult(sendPayload: sendPayload);
  }

  /// Timeout / shell-closed path: release held text as-is and stop gating.
  String flush() {
    _passthrough = true;
    final out = _strip(_held.toString());
    _held.clear();
    return out;
  }

  String _strip(String s) =>
      s.replaceAll(readySentinel, '').replaceAll(doneSentinel, '');

  static int _tailFrom(String buf, String sentinel) {
    final from = buf.length - sentinel.length + 1;
    return from < 0 ? 0 : from;
  }
}
