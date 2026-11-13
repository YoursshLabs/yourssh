// 17 DevOps tools on the demo host.
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'nav.dart';
import 'sections.dart';

const s = '17-devops';

Future<void> runDevops(JourneyContext c) async {
  final t = c.t;
  // Make the Demo Server session the active one so tools have a target.
  await t.tap(find.textContaining('Demo Server · demo').first, warnIfMissed: false);
  await sleepPump(t, 600);
  await navTo(t, 'DevOps Hub', wait: 1000);
  await c.snap('$s/01-hub', 'DevOps hub: tool list on the left');
  Future<void> nav(String name) => tapKey(t, 'devops-nav-$name', wait: 900);
  await step(c.notes, 'containers', () async {
    await nav('containers');
    await c.snap('$s/02-containers', 'Containers tool before scanning');
    await tapText(t, 'Scan', wait: 3500).catchError((_) {});
    await sleepPump(t, 2000);
    await c.snap('$s/03-containers-no-docker', 'Containers: Docker is not installed on this host (empty/error state)');
  });
  await step(c.notes, 'network tools', () async {
    await nav('networkTools');
    await c.snap('$s/04-network-tools', 'Network tools: ping, DNS lookup, traceroute, port scan, whois, netstat, disk usage, ...');
    await tapText(t, 'Ping', wait: 500);
    await typeKey(t, 'devops-input', '127.0.0.1');
    await tapKey(t, 'devops-run', wait: 300);
    await sleepPump(t, 5000);
    await c.snap('$s/05-ping-result', 'Ping 127.0.0.1 run on the host; result in a tab');
    await tapText(t, 'DNS Lookup', wait: 500);
    await typeKey(t, 'devops-input', 'localhost');
    await tapKey(t, 'devops-run', wait: 300);
    await sleepPump(t, 4000);
    await c.snap('$s/06-dns-result', 'DNS lookup result (second result tab)');
  });
  await step(c.notes, 'cloudflare', () async {
    await nav('cloudflare');
    await c.snap('$s/07-cloudflare-empty', 'Cloudflare tunnels: empty state');
    await tapKey(t, 'tunnel-new', wait: 700);
    await c.snap('$s/08-cloudflare-new-panel', 'New tunnel panel');
    await typeKey(t, 'tunnel-label', '');
    await typeKey(t, 'tunnel-port', '');
    await tapKey(t, 'tunnel-add', wait: 600);
    await c.snap('$s/09-cloudflare-validation', 'Add tunnel with empty fields: validation errors');
    await typeKey(t, 'tunnel-label', 'docs tunnel');
    await typeKey(t, 'tunnel-port', '8080');
    await tapKey(t, 'tunnel-add', wait: 800);
    await c.snap('$s/10-cloudflare-rule', 'Tunnel added to the list');
    await tapTooltip(t, 'Start tunnel', wait: 2500);
    await sleepPump(t, 2500);
    await c.snap('$s/11-cloudflare-no-cloudflared', 'Starting a tunnel without cloudflared installed: error state');
  });
  await step(c.notes, 'lan share', () async {
    await nav('lanShare');
    await c.snap('$s/12-lan-share', 'LAN Share tool');
  });
  await step(c.notes, 'mail catcher', () async {
    await nav('mailCatcher');
    await c.snap('$s/13-mail-catcher-idle', 'Mail catcher before starting');
    await tapTooltip(t, 'Start on port 1025', wait: 1500);
    await sleepPump(t, 4000);
    await c.snap('$s/14-mail-catcher-running', 'Mail catcher running (SMTP on port 1025 of the host)');
    final host = c.sessions.sshSessions.firstWhere((x) => x.host.label == 'Demo Server').host;
    final r = await c.read<SshService>().exec(host,
        "python3 -c \"import smtplib;from email.message import EmailMessage;m=EmailMessage();m['From']='docs@example.test';m['To']='you@example.test';m['Subject']='Welcome to YourSSH docs';m.set_content('Hello!\\nThis message was caught by the YourSSH mail catcher.');s=smtplib.SMTP('127.0.0.1',1025);s.send_message(m);s.quit()\"");
    stdout_(r.stdout + r.stderr);
    await sleepPump(t, 3500);
    await c.snap('$s/15-mail-list', 'A test mail (sent with python smtplib over SSH) appears in the list');
    await t.tap(find.textContaining('Welcome to YourSSH docs').first, warnIfMissed: false);
    await sleepPump(t, 900);
    await c.snap('$s/16-mail-detail', 'Mail detail: headers and body');
    await tapTooltip(t, 'Clear all', wait: 700);
    await c.snap('$s/17-mail-clear-confirm', 'Clear all asks first: "Clear captured mail?" (Cancel focused, Clear destructive)');
    // The dialog is the topmost route, so its "Clear" is the last match.
    await t.tap(find.text('Clear').last, warnIfMissed: false);
    await sleepPump(t, 900);
    await c.snap('$s/17b-mail-cleared', 'After Clear: list and catcher log on the host emptied');
    await tapTooltip(t, 'Stop', wait: 800).catchError((_) {});
  });
  await step(c.notes, 'mcp', () async {
    await nav('mcpServer');
    await c.snap('$s/18-mcp-server', 'MCP server screen: command, port, toggle');
  });
  await step(c.notes, 's3', () async {
    await nav('s3Browser');
    await c.snap('$s/19-s3-browser', 'S3 browser with no buckets configured');
  });
}

void stdout_(String s) => print('EXEC: $s');
