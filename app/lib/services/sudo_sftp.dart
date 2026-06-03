import 'dart:convert';
import 'dart:typed_data';

import '../models/host.dart';

/// Orchestrates elevated SFTP sessions (SftpMode.sudo / custom): the SFTP
/// server binary is started through `sudo` on an exec channel instead of the
/// `sftp` subsystem, so the whole session runs as root.
///
/// Pure policy — all IO is injected, so this is unit-testable without SSH.
/// See docs/superpowers/specs/2026-06-03-sudo-sftp-design.md.

/// Common sftp-server locations across distros.
const kSftpServerPaths = [
  '/usr/lib/openssh/sftp-server', // Debian / Ubuntu
  '/usr/libexec/openssh/sftp-server', // RHEL / Fedora
  '/usr/lib/ssh/sftp-server', // Arch / SUSE
];

/// Single remote exec that prints the first executable sftp-server path
/// (empty output when none exists, e.g. servers using internal-sftp).
String buildPathProbeCommand() =>
    'for p in ${kSftpServerPaths.join(' ')}; do '
    'if [ -x "\$p" ]; then echo "\$p"; break; fi; done';

/// Forces C locale so sudo's diagnostics are emitted in English, keeping
/// [classifySudoFailure] independent of the server's LANG/LC_ALL.
const _kCLocale = "LANG=C LC_ALL=C ";

/// Validates a sudo password fed via stdin AND caches the sudo timestamp on
/// success. `-p ''` suppresses the prompt so stderr stays parseable; the
/// caller must close stdin after one line so a wrong password fails fast
/// instead of hanging on sudo's re-prompt.
const kSudoValidateCommand = "${_kCLocale}sudo -S -p '' -v";

// [path] is always one of kSftpServerPaths (echoed back by the probe), never free-form input.
String buildSudoRunCommand(String path) => '${_kCLocale}sudo -n $path';

/// Last-resort start when sudo timestamp caching is disabled
/// (timestamp_timeout=0): the validated password is fed as a stdin preamble.
// [path] is always one of kSftpServerPaths (echoed back by the probe), never free-form input.
String buildInlineSudoCommand(String path) => "${_kCLocale}sudo -S -p '' $path";

enum SudoSftpFailureReason {
  binaryNotFound,
  sudoNotInstalled,
  notInSudoers,
  wrongPassword,
  requiresTty,
  passwordRequired,
  userCancelled,
  commandMissing,
  handshakeFailed,
}

/// Best-effort classification of sudo stderr. Returns null when the output
/// matches no known pattern — callers pick a context-appropriate fallback.
// Matches sudo stderr (English locale); unknown/localized output falls through to null → caller's generic fallback.
SudoSftpFailureReason? classifySudoFailure(String stderr) {
  final s = stderr.toLowerCase();
  if (s.contains('not in the sudoers') ||
      s.contains('not allowed to execute')) {
    return SudoSftpFailureReason.notInSudoers;
  }
  if (s.contains('a terminal is required') ||
      s.contains('a tty is required') ||
      s.contains('must have a tty')) {
    return SudoSftpFailureReason.requiresTty;
  }
  if (s.contains('incorrect password') || s.contains('try again')) {
    return SudoSftpFailureReason.wrongPassword;
  }
  if (s.contains('sudo: not found') || s.contains('command not found')) {
    return SudoSftpFailureReason.sudoNotInstalled;
  }
  return null;
}

class SudoSftpException implements Exception {
  final SudoSftpFailureReason reason;
  final String? detail;

  SudoSftpException(this.reason, {this.detail});

  String get message {
    switch (reason) {
      case SudoSftpFailureReason.binaryNotFound:
        return 'No sftp-server binary found on the server '
            '(checked: ${kSftpServerPaths.join(', ')}). Servers using '
            'internal-sftp are not supported in Sudo mode — switch the host '
            'to a custom SFTP command, or to Default mode.';
      case SudoSftpFailureReason.sudoNotInstalled:
        return 'sudo is not installed on the server.';
      case SudoSftpFailureReason.notInSudoers:
        return 'Your user may not run sftp-server via sudo. Add this line '
            'on the server with visudo (replace <user> and the path):\n'
            '<user> ALL=(root) NOPASSWD: /usr/lib/openssh/sftp-server';
      case SudoSftpFailureReason.wrongPassword:
        return 'sudo rejected the password.';
      case SudoSftpFailureReason.requiresTty:
        return 'sudo on the server requires a TTY (Defaults requiretty). '
            'Disable requiretty for your user, or configure NOPASSWD for '
            'sftp-server.';
      case SudoSftpFailureReason.passwordRequired:
        return 'sudo requires a password and none is stored for this host.';
      case SudoSftpFailureReason.userCancelled:
        return 'Sudo password prompt was cancelled.';
      case SudoSftpFailureReason.commandMissing:
        return 'SFTP mode is set to Custom but no server command is '
            'configured for this host.';
      case SudoSftpFailureReason.handshakeFailed:
        return 'The SFTP server command did not produce a valid SFTP '
            'session. Check the command and server logs.';
    }
  }

  @override
  String toString() =>
      detail == null || detail!.isEmpty ? message : '$message\n$detail';
}

typedef SudoExecResult = ({String stdout, String stderr, int exitCode});

/// `attempt` 0 = stored/login candidates; 1 = forced re-prompt after a
/// wrong password (only reached when `interactive`).
typedef GetSudoPassword = Future<String?> Function({
  required bool interactive,
  required int attempt,
});

/// Generic over the client type so tests don't need dartssh2. In production
/// [TClient] is `SftpClient` and `openSftpExec` must complete the SFTP
/// handshake (throwing on failure) before returning.
class SudoSftpOrchestrator<TClient> {
  final Future<SudoExecResult> Function(String command) runExec;
  final Future<({String stderr, int exitCode})> Function(
      String command, List<int> stdinData) runExecWithStdin;
  final Future<TClient> Function(String command, {Uint8List? stdinPreamble})
      openSftpExec;

  SudoSftpOrchestrator({
    required this.runExec,
    required this.runExecWithStdin,
    required this.openSftpExec,
  });

  Future<TClient> openForHost(
    Host host, {
    required GetSudoPassword getPassword,
    required bool interactive,
  }) {
    switch (host.sftpMode) {
      case SftpMode.normal:
        throw ArgumentError(
            'SudoSftpOrchestrator only handles sudo/custom modes');
      case SftpMode.sudo:
        return _openSudo(getPassword: getPassword, interactive: interactive);
      case SftpMode.custom:
        return _openCustom(host.sftpServerCommand,
            getPassword: getPassword, interactive: interactive);
    }
  }

  Future<TClient> _openSudo({
    required GetSudoPassword getPassword,
    required bool interactive,
  }) async {
    final probe = await runExec(buildPathProbeCommand());
    final path = probe.stdout.trim();
    if (path.isEmpty) {
      throw SudoSftpException(SudoSftpFailureReason.binaryNotFound);
    }

    // NOPASSWD or still-cached sudo timestamp.
    try {
      return await _start(buildSudoRunCommand(path));
    } on SudoSftpException {
      // Expected when sudo needs a password — fall through.
    }

    final password = await _validatePassword(
        getPassword: getPassword, interactive: interactive);

    // Validation cached the sudo timestamp, so -n normally works now.
    try {
      return await _start(buildSudoRunCommand(path));
    } on SudoSftpException {
      // timestamp_timeout=0 — feed the already-validated password inline. Safe: validation proved the password+sudo work and path ∈ kSftpServerPaths, so the password only ever reaches sudo.
    }
    return _start(
      buildInlineSudoCommand(path),
      stdinPreamble: Uint8List.fromList(utf8.encode('$password\n')),
    );
  }

  Future<TClient> _openCustom(
    String? command, {
    required GetSudoPassword getPassword,
    required bool interactive,
  }) async {
    final cmd = command?.trim() ?? '';
    if (cmd.isEmpty) {
      throw SudoSftpException(SudoSftpFailureReason.commandMissing);
    }

    try {
      return await _start(cmd);
    } on SudoSftpException {
      if (!cmd.startsWith('sudo ')) rethrow;
    }

    // sudo-based custom command: validating caches the sudo timestamp, then
    // the verbatim command runs without prompting.
    await _validatePassword(getPassword: getPassword, interactive: interactive);
    try {
      return await _start(cmd);
    } on SudoSftpException {
      final diag = await runExec('$cmd </dev/null');
      throw SudoSftpException(
        classifySudoFailure(diag.stderr) ??
            SudoSftpFailureReason.handshakeFailed,
        detail: diag.stderr.trim(),
      );
    }
  }

  Future<String> _validatePassword({
    required GetSudoPassword getPassword,
    required bool interactive,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final password =
          await getPassword(interactive: interactive, attempt: attempt);
      if (password == null) {
        throw SudoSftpException(interactive
            ? SudoSftpFailureReason.userCancelled
            : SudoSftpFailureReason.passwordRequired);
      }
      final result = await runExecWithStdin(
          kSudoValidateCommand, utf8.encode('$password\n'));
      if (result.exitCode == 0) return password;

      final reason = classifySudoFailure(result.stderr) ??
          SudoSftpFailureReason.wrongPassword;
      if (reason != SudoSftpFailureReason.wrongPassword || !interactive) {
        throw SudoSftpException(reason, detail: result.stderr.trim());
      }
      // Wrong password and interactive → loop once more (attempt 1 forces a
      // fresh prompt instead of reusing stored candidates).
    }
    throw SudoSftpException(SudoSftpFailureReason.wrongPassword);
  }

  Future<TClient> _start(String command, {Uint8List? stdinPreamble}) async {
    try {
      return await openSftpExec(command, stdinPreamble: stdinPreamble);
    } catch (e) {
      throw SudoSftpException(SudoSftpFailureReason.handshakeFailed,
          detail: '$e');
    }
  }
}
