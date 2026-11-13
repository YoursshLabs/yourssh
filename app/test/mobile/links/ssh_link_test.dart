import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/links/ssh_link.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/cli/cli_server.dart';

void main() {
  test('parseSshLink accepts user@host[:port] and nothing else', () {
    final t = parseSshLink('ssh://alice@10.0.0.5:2222')!;
    expect([t.user, t.host, t.port], ['alice', '10.0.0.5', 2222]);
    expect(t.query, 'alice@10.0.0.5:2222');
    expect(parseSshLink('ssh://alice@[fe80::1]/')!.port, 22);
    expect(parseSshLink('SSH://alice@example.com')!.host, 'example.com');
    for (final u in [
      'ssh://10.0.0.5',
      'ssh://a:pw@h',
      'ssh://a;fingerprint=x@h',
      'ssh://a@h/path',
      'ssh://a@h?x=1',
      'ssh://a@h#f',
      'ssh://-oProxyCommand=x@h',
      'ssh://a@-h',
      'ssh://a@h:0',
      'ssh://a@h:70000',
      'ssh://a@${'h' * 3000}',
      'ssh://a@h\u202e',
      'ssh://a@h\n',
      'ssh://a%40b@h',
      'yourssh://connect/a',
      '',
    ]) {
      expect(parseSshLink(u), isNull, reason: u);
    }
  });

  group('SshLinkHandler', () {
    late List<Host> hosts;
    late bool enabled;
    late bool confirmAnswer;
    late List<String> log;
    late DateTime clock;

    SshLinkHandler build() => SshLinkHandler(
          hosts: () => hosts,
          enabled: () async => enabled,
          openSaved: (h) async => log.add('open:${h.label}'),
          confirm: (t) async {
            log.add('confirm:${t.query}');
            return confirmAnswer;
          },
          addHost: (h) =>
              log.add('add:${h.username}@${h.host}:${h.port}:${h.label}'),
          refused: (m) => log.add('refused:$m'),
          now: () => clock,
        );

    setUp(() {
      hosts = [Host(id: 'a', label: 'Prod', host: '10.0.0.5', username: 'alice', port: 2222)];
      enabled = true;
      confirmAnswer = false;
      log = [];
      clock = DateTime(2026);
    });

    test('is refused while the setting is off', () async {
      enabled = false;
      await build().handle('ssh://alice@10.0.0.5:2222');
      expect(log, ['refused:ssh:// links are off (Settings › Security)']);
    });

    test('unparsable links are refused', () async {
      await build().handle('ssh://a@h/path');
      expect(log, hasLength(1));
      expect(log.single, startsWith('refused:'));
    });

    test('a saved user@host:port opens that host without asking', () async {
      await build().handle('ssh://alice@10.0.0.5:2222');
      expect(log, ['open:Prod']);
    });

    test('an unknown target asks first and only prefills Add Host', () async {
      final h = build();
      await h.handle('ssh://alice@203.0.113.7');
      expect(log, ['confirm:alice@203.0.113.7:22']);
      log.clear();
      confirmAnswer = true;
      clock = clock.add(CliServer.dedupeWindow);
      await h.handle('ssh://alice@203.0.113.7');
      expect(log, [
        'confirm:alice@203.0.113.7:22',
        'add:alice@203.0.113.7:22:alice@203.0.113.7',
      ]);
      expect(log.any((l) => l.startsWith('open:')), isFalse);
    });

    test('an ambiguous saved target is refused', () async {
      hosts.add(Host(id: 'b', label: 'Prod2', host: '10.0.0.5', username: 'alice', port: 2222));
      await build().handle('ssh://alice@10.0.0.5:2222');
      expect(log.single, startsWith('refused:'));
    });

    test('the same link (any case) within the window is ignored', () async {
      final h = build();
      await h.handle('ssh://alice@10.0.0.5:2222');
      await h.handle('SSH://ALICE@10.0.0.5:2222');
      expect(log, ['open:Prod']);
      clock = clock.add(CliServer.dedupeWindow);
      await h.handle('ssh://alice@10.0.0.5:2222');
      expect(log, ['open:Prod', 'open:Prod']);
    });
  });
}
