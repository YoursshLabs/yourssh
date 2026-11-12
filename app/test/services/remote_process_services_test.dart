import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/cloudflare_tunnel_service.dart';
import 'package:yourssh/services/mail_catcher_service.dart';
import 'package:yourssh/services/mcp_gateway_service.dart';

import 'fake_ssh_for_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final host = Host(label: 'h', host: 'srv', port: 22, username: 'u');

  group('McpGatewayService', () {
    test('start records the PID and stop kills exactly that PID', () async {
      final ssh = RecordingSsh()
        ..execStub = (cmd) => (stdout: '4242\n', stderr: '', exitCode: 0);
      final svc = McpGatewayService(ssh);
      final r = await svc.start(McpEndpoint(
          host: host, localPort: 5, mcpCommand: 'node server.js'));
      expect(r.ok, isTrue);
      expect(ssh.execCmds.single, contains(r'echo $!'));

      await svc.stop(host);
      final stopCmd = ssh.execCmds.last;
      expect(stopCmd, contains('kill 4242'));
      expect(stopCmd, isNot(contains('pkill')));
    });

    test('start fails when no PID is returned', () async {
      final ssh = RecordingSsh()
        ..execStub = (cmd) => (stdout: '', stderr: 'boom', exitCode: 1);
      final r = await McpGatewayService(ssh).start(McpEndpoint(
          host: host, localPort: 5, mcpCommand: 'node server.js'));
      expect(r.ok, isFalse);
    });
  });

  group('CloudflareTunnelService', () {
    test('uses mktemp, records PID, parses URL and stops by PID', () async {
      final ssh = RecordingSsh()
        ..execStub = (cmd) => (
              stdout: 'DIR:/tmp/tmp.AbC\nhttps://x.trycloudflare.com\n',
              stderr: '',
              exitCode: 0
            );
      final svc = CloudflareTunnelService(ssh);
      final r = await svc.startQuickTunnel(host, 3000);
      expect(r.url, 'https://x.trycloudflare.com');
      expect(ssh.execCmds.single, contains('mktemp'));
      expect(ssh.execCmds.single, isNot(contains('/tmp/cf_tunnel_')));

      // A fresh instance (as the screen creates) must still find the state.
      await CloudflareTunnelService(ssh).stopTunnel(host, 3000);
      final stopCmd = ssh.execCmds.last;
      expect(stopCmd, contains("/tmp/tmp.AbC/pid"));
      expect(stopCmd, isNot(contains("pkill -f 'cloudflared.*")));
    });

    test('stop fallback pattern cannot match its own shell', () async {
      final ssh = RecordingSsh();
      await CloudflareTunnelService(ssh).stopTunnel(host, 4111);
      final cmd = ssh.execCmds.single;
      expect(cmd, contains('pkill -f'));
      expect(cmd, contains('[c]loudflared'));
      expect(cmd, contains('^'));
    });
  });

  group('MailCatcherService', () {
    test('start uses mktemp, no fixed log, aiosmtpd fallback, PID', () async {
      final ssh = RecordingSsh()
        ..execStub = (cmd) => (stdout: 'started:/tmp/tmp.Mail\n', stderr: '', exitCode: 0);
      final svc = MailCatcherService(ssh);
      expect(await svc.start(host), isTrue);
      final cmd = ssh.execCmds.single;
      expect(cmd, contains('mktemp'));
      expect(cmd, contains('aiosmtpd'));
      expect(cmd, contains(r'echo $!'));
      expect(cmd, isNot(contains('/tmp/mailcatcher.log')));
      expect(cmd, isNot(contains('pkill')));

      await svc.fetchEmails(host);
      expect(ssh.execCmds.last, contains('/tmp/tmp.Mail/log'));
      await svc.stop(host);
      expect(ssh.execCmds.last, contains('/tmp/tmp.Mail/pid'));
    });

    test('start surfaces a clear error when no SMTP server is available',
        () async {
      final ssh = RecordingSsh()
        ..execStub = (cmd) => (stdout: 'ERR:no-smtp-server\n', stderr: '', exitCode: 0);
      final svc = MailCatcherService(ssh);
      expect(await svc.start(host), isFalse);
      expect(svc.lastError, contains('aiosmtpd'));
    });
  });
}
