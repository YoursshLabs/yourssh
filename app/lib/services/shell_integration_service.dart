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
