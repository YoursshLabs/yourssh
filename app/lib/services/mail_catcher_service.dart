import 'dart:convert';

import '../models/host.dart';
import 'ssh_service.dart';
import 'web_tools_service.dart';

class CaughtEmail {
  final String from;
  final String to;
  final String subject;
  final String body;
  final DateTime receivedAt;

  const CaughtEmail({
    required this.from,
    required this.to,
    required this.subject,
    required this.body,
    required this.receivedAt,
  });
}

class MailCatcherService {
  final SshService _sshService;
  static const _smtpPort = 1025;

  /// Remote state dir (mktemp -d, holds `log` and `pid`) per host. Static
  /// because the screen may rebuild the service.
  static final Map<String, String> _stateDirs = {};
  static final _dirPattern = RegExp(r'^/[A-Za-z0-9_./-]+$');

  /// Human-readable reason of the last failed [start].
  String? lastError;

  MailCatcherService(this._sshService);

  Future<bool> start(Host host) async {
    lastError = null;
    await stop(host);
    // smtpd was removed in Python 3.12; fall back to aiosmtpd when present.
    const cmd = '''
      d=\$(mktemp -d) || exit 1
      if python3 -c 'import smtpd' 2>/dev/null; then
        nohup python3 -m smtpd -n -c DebuggingServer localhost:$_smtpPort > "\$d/log" 2>&1 &
      elif python3 -c 'import aiosmtpd' 2>/dev/null; then
        nohup python3 -m aiosmtpd -n -l localhost:$_smtpPort > "\$d/log" 2>&1 &
      else
        rm -rf "\$d"
        echo "ERR:no-smtp-server"
        exit 0
      fi
      echo \$! > "\$d/pid"
      sleep 1
      if kill -0 \$(cat "\$d/pid") 2>/dev/null; then echo "started:\$d"; else echo "ERR:exited:\$d"; fi
    ''';
    final result = await _sshService.exec(host, cmd, auditSource: 'devops');
    final out = result.stdout.trim().split('\n').last.trim();
    if (out.startsWith('started:')) {
      final dir = out.substring(8);
      if (_dirPattern.hasMatch(dir)) {
        _stateDirs[host.id] = dir;
        return true;
      }
    }
    lastError = out.startsWith('ERR:no-smtp-server')
        ? 'No SMTP server available: python3 -m smtpd was removed in Python '
            '3.12. Install aiosmtpd (pip install aiosmtpd) on the server.'
        : 'Failed to start SMTP server. Ensure python3 is installed.';
    return false;
  }

  Future<void> stop(Host host) async {
    final dir = _stateDirs.remove(host.id);
    if (dir == null) return;
    await _sshService.exec(
        host,
        'kill \$(cat ${WebToolsService.shellQuote('$dir/pid')}) 2>/dev/null; '
        'rm -rf ${WebToolsService.shellQuote(dir)}',
        auditSource: 'devops');
  }

  Future<List<CaughtEmail>> fetchEmails(Host host) async {
    final dir = _stateDirs[host.id];
    if (dir == null) return [];
    final result = await _sshService.exec(
        host, 'cat ${WebToolsService.shellQuote('$dir/log')} 2>/dev/null',
        auditSource: 'devops');
    final output = result.stdout;
    if (output.isEmpty) return [];
    return _parseSmtpdLog(output);
  }

  Future<void> clearLog(Host host) async {
    final dir = _stateDirs[host.id];
    if (dir == null) return;
    await _sshService.exec(host, '> ${WebToolsService.shellQuote('$dir/log')}',
        auditSource: 'devops');
  }

  List<CaughtEmail> _parseSmtpdLog(String log) => parseLog(log);

  static final _startMarker = RegExp(r'^-{5,}\s*MESSAGE FOLLOWS\s*-{5,}$');
  static final _endMarker = RegExp(r'^-{5,}\s*END MESSAGE\s*-{5,}$');
  // Python 3 smtpd DebuggingServer prints bytes lines as their repr: b'...'.
  static final _bytesRepr = RegExp(r'''^b(['"])(.*)\1$''');

  /// Parses the output of `python3 -m smtpd -n -c DebuggingServer` (Python
  /// 3 prints each line as a bytes repr such as `b'From: a@b'`, the blank
  /// header/body separator as `b''`) and of `python3 -m aiosmtpd -n` (plain
  /// text). The first blank line ends the headers; everything up to the END
  /// MESSAGE marker is the body.
  static List<CaughtEmail> parseLog(String log) {
    final emails = <CaughtEmail>[];
    String from = '', to = '', subject = '';
    var inMessage = false;
    var inBody = false;
    var bodyLines = <String>[];

    void finish() {
      if (from.isNotEmpty || to.isNotEmpty || subject.isNotEmpty) {
        while (bodyLines.isNotEmpty && bodyLines.last.trim().isEmpty) {
          bodyLines.removeLast();
        }
        emails.add(CaughtEmail(
          from: from,
          to: to,
          subject: subject,
          body: bodyLines.join('\n'),
          receivedAt: DateTime.now(),
        ));
      }
      from = to = subject = '';
      inMessage = false;
      inBody = false;
      bodyLines = <String>[];
    }

    for (final raw in log.split('\n')) {
      final trimmedRight = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (_startMarker.hasMatch(trimmedRight)) {
        if (inMessage) finish();
        inMessage = true;
        continue;
      }
      if (_endMarker.hasMatch(trimmedRight)) {
        if (inMessage) finish();
        continue;
      }
      if (!inMessage) continue;
      final line = _unwrap(trimmedRight);
      if (inBody) {
        bodyLines.add(line);
      } else if (line.isEmpty) {
        inBody = true;
      } else if (line.startsWith('From: ')) {
        from = line.substring(6);
      } else if (line.startsWith('To: ')) {
        to = line.substring(4);
      } else if (line.startsWith('Subject: ')) {
        subject = line.substring(9);
      }
    }
    if (inMessage) finish();
    return emails;
  }

  static String _unwrap(String line) {
    final m = _bytesRepr.firstMatch(line);
    if (m == null) return line;
    final bytes = <int>[];
    final src = m.group(2)!;
    for (var i = 0; i < src.length; i++) {
      final c = src[i];
      if (c != r'\' || i + 1 >= src.length) {
        bytes.addAll(utf8.encode(c));
        continue;
      }
      final n = src[++i];
      switch (n) {
        case 'n':
          bytes.add(10);
        case 'r':
          bytes.add(13);
        case 't':
          bytes.add(9);
        case 'x':
          final hex = i + 2 < src.length ? src.substring(i + 1, i + 3) : '';
          final v = int.tryParse(hex, radix: 16);
          if (v == null) {
            bytes.addAll(utf8.encode(r'\x'));
          } else {
            bytes.add(v);
            i += 2;
          }
        default:
          bytes.addAll(utf8.encode(n));
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
