enum ShellOscKind { cwd, promptStart, finished }

class ShellOscEvent {
  final ShellOscKind kind;
  final String? cwd;
  final int? exitCode;
  const ShellOscEvent.cwd(this.cwd)
      : kind = ShellOscKind.cwd,
        exitCode = null;
  const ShellOscEvent.promptStart()
      : kind = ShellOscKind.promptStart,
        cwd = null,
        exitCode = null;
  const ShellOscEvent.finished(this.exitCode)
      : kind = ShellOscKind.finished,
        cwd = null;
}

/// Pure helpers for shell integration. No Flutter / IO deps so it unit-tests
/// without a Terminal or SSH connection.
class ShellIntegrationService {
  /// Parse an `OSC 7 ; file://host/path` URL into a decoded absolute path.
  /// Returns null for anything that isn't a file URL with a path.
  static String? parseOsc7Path(String url) {
    if (!url.startsWith('file://')) return null;
    final rest = url.substring('file://'.length); // host/path  or  /path
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    final raw = rest.substring(slash);
    try {
      return Uri.decodeFull(raw);
    } catch (_) {
      return raw;
    }
  }

  /// Map an xterm `onPrivateOSC(code, args)` callback to a typed event,
  /// or null when irrelevant/malformed.
  ShellOscEvent? parseOsc(String code, List<String> args) {
    if (code == '7') {
      if (args.isEmpty) return null;
      // Rejoin on ';' — xterm splits the OSC payload on every ';', so a cwd
      // containing a semicolon arrives as multiple args.
      final path = parseOsc7Path(args.join(';'));
      return path == null ? null : ShellOscEvent.cwd(path);
    }
    if (code == '133') {
      if (args.isEmpty) return null;
      switch (args.first) {
        case 'A':
          return const ShellOscEvent.promptStart();
        case 'D':
          return ShellOscEvent.finished(
              args.length > 1 ? int.tryParse(args[1]) : null);
        default:
          return null; // B, C and anything else are ignored
      }
    }
    return null;
  }

  /// Sentinels printed by the injected shell code. Built at runtime with
  /// `printf '__YS_%s__' RDY` so the literal string never appears in the
  /// echoed command line — the output scanner cannot false-positive on echo.
  static const kReadySentinel = '__YS_RDY__';
  static const kDoneSentinel = '__YS_DONE__';

  /// Short first-phase line written to the shell instead of the full script.
  /// bash/zsh: disables tty echo, prints RDY, then blocks in `read -rs` so
  /// the payload that follows is consumed raw and never echoed. The explicit
  /// `stty -echo` BEFORE the RDY printf closes the race where the payload
  /// arrives after RDY but before `read -s` has switched the tty itself —
  /// the kernel would echo it. Other POSIX shells: print DONE immediately so
  /// the client skips the payload and cleans up.
  String buildBootstrapLine() =>
      r'[ -n "$BASH_VERSION$ZSH_VERSION" ] && '
      r"{ stty -echo 2>/dev/null; printf '__YS_%s__' RDY; "
      r'IFS= read -rs __ys; eval "$__ys"; unset __ys; '
      r'stty echo 2>/dev/null; } '
      r"|| printf '__YS_%s__\n' DONE"
      '\n';

  /// Second-phase line: the hook installer plus the DONE sentinel. Sent only
  /// after RDY is seen, while `read -rs` is consuming stdin — never echoed.
  /// DONE carries a trailing newline so both the remote shell and the app
  /// land on a fresh line (col 0) once the client discards everything up to
  /// and including the sentinel — the next prompt then renders in sync.
  String buildPayloadLine() {
    final body = buildInjectionScript(); // ends with '\n'
    return '${body.substring(0, body.length - 1)}; '
        "printf '__YS_%s__\\n' DONE\n";
  }

  /// Single-line bash/zsh setup written to the shell on connect. Guarded
  /// (`__yourssh_si`) so a re-source is a no-op; appends to PROMPT_COMMAND /
  /// precmd/preexec arrays rather than overwriting; silent on other shells.
  String buildInjectionScript() {
    const zsh =
        r'''__ys_osc7(){ printf '\033]7;file://%s%s\a' "$HOST" "${PWD}"; }; __ys_pre(){ printf '\033]133;A\a'; __ys_osc7; }; __ys_exec(){ printf '\033]133;C\a'; }; __ys_post(){ printf '\033]133;D;%s\a' "$?"; }; precmd_functions+=(__ys_post __ys_pre); preexec_functions+=(__ys_exec); PS1="%{$(printf '\033]133;B\a')%}$PS1"''';
    const bash =
        r'''__ys_post(){ local e=$?; printf '\033]133;D;%s\a' "$e"; printf '\033]133;A\a'; printf '\033]7;file://%s%s\a' "$HOSTNAME" "${PWD}"; }; PROMPT_COMMAND="__ys_post;${PROMPT_COMMAND:-}"; trap 'printf "\033]133;C\a"' DEBUG; PS1="$PS1\[$(printf '\033]133;B\a')\]"''';
    return 'if [ -z "\$__yourssh_si" ]; then __yourssh_si=1; '
        'if [ -n "\$ZSH_VERSION" ]; then $zsh; '
        'elif [ -n "\$BASH_VERSION" ]; then $bash; fi; fi\n';
  }
}
