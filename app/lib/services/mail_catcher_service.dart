import '../models/host.dart';
import 'ssh_service.dart';

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

  MailCatcherService(this._sshService);

  Future<bool> start(Host host) async {
    const cmd = '''
      pkill -f "smtpd.*$_smtpPort" 2>/dev/null
      python3 -m smtpd -n -c DebuggingServer localhost:$_smtpPort > /tmp/mailcatcher.log 2>&1 &
      sleep 1
      pgrep -f "smtpd.*$_smtpPort" > /dev/null 2>&1 && echo "started"
    ''';
    final result = await _sshService.exec(host, cmd, auditSource: 'devops');
    return result.stdout.trim() == 'started';
  }

  Future<void> stop(Host host) async {
    await _sshService.exec(host, "pkill -f 'smtpd.*$_smtpPort' 2>/dev/null", auditSource: 'devops');
  }

  Future<List<CaughtEmail>> fetchEmails(Host host) async {
    final result = await _sshService.exec(host, 'cat /tmp/mailcatcher.log 2>/dev/null', auditSource: 'devops');
    final output = result.stdout;
    if (output.isEmpty) return [];
    return _parseSmtpdLog(output);
  }

  Future<void> clearLog(Host host) async {
    await _sshService.exec(host, '> /tmp/mailcatcher.log', auditSource: 'devops');
  }

  List<CaughtEmail> _parseSmtpdLog(String log) {
    final emails = <CaughtEmail>[];
    final blocks = log.split(RegExp(r'-{10,}'));

    for (final block in blocks) {
      if (block.trim().isEmpty) continue;
      final lines = block.split('\n').where((l) => l.isNotEmpty).toList();
      String from = '', to = '', subject = '';
      final bodyLines = <String>[];
      bool inBody = false;

      for (final line in lines) {
        if (line.startsWith('From: ')) {
          from = line.substring(6);
        } else if (line.startsWith('To: ')) {
          to = line.substring(4);
        } else if (line.startsWith('Subject: ')) {
          subject = line.substring(9);
        } else if (line.isEmpty) {
          inBody = true;
        } else if (inBody) {
          bodyLines.add(line);
        }
      }

      if (from.isNotEmpty || to.isNotEmpty) {
        emails.add(CaughtEmail(
          from: from,
          to: to,
          subject: subject,
          body: bodyLines.join('\n'),
          receivedAt: DateTime.now(),
        ));
      }
    }
    return emails;
  }
}
