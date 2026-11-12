import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/cli/cli_handlers.dart';
import 'package:yourssh/services/cli/cli_server.dart';
import 'package:yourssh/services/cli/host_resolver.dart';
import 'package:yourssh/services/cli/single_instance.dart' show kForwardReplyTimeout;
import 'package:yourssh_cli/yourssh_cli.dart';

class FakeHandlers implements CliHandlers {
  FakeHandlers(this._hosts);
  @override
  List<Host> get hosts => hostsGetter != null ? hostsGetter!() : _hosts;
  final List<Host> _hosts;
  List<Host> Function()? hostsGetter;
  final calls = <String>[];
  Object? connectError;

  @override
  Future<void> connect(Host host, {required String source}) async {
    if (connectError != null) throw connectError!;
    calls.add('connect:${host.label}:$source');
  }

  @override
  Future<void> connectAdHoc(AdHocTarget t) async =>
      calls.add('adhoc:${t.user}@${t.hostname}:${t.port}');

  @override
  Future<void> focusWindow() async => calls.add('focus');

  @override
  String get appVersion => '9.9.9';
}

Host h(String label, {String? id, String user = 'u', String host = 'h', List<String> tags = const []}) =>
    Host(id: id, label: label, host: host, username: user, tags: tags);

const tok = 'secret-token';

String req(String cmd, Map<String, Object?> args, {String token = tok}) =>
    CliRequest(id: 'r1', token: token, cmd: cmd, args: args).encode();

void main() {
  late FakeHandlers fake;
  late CliServer server;

  setUp(() {
    fake = FakeHandlers([
      h('web-1', id: 'a', tags: ['prod']),
      h('db', id: 'b', tags: ['dev']),
      h('dup', id: 'c'),
      h('dup', id: 'd'),
    ]);
    server = CliServer(handlers: fake, token: tok);
  });

  Future<CliResponse> call(String line, {bool trusted = false, String source = 'cli'}) async =>
      CliResponse.decode(await server.handleLine(line, trusted: trusted, source: source));

  test('wrong token is denied (code 4) and nothing runs', () async {
    final r = await call(req('connect', {'host': 'web-1'}, token: 'nope'));
    expect(r.ok, isFalse);
    expect(r.code, CliExit.denied);
    expect(fake.calls, isEmpty);
  });

  test('trusted call ignores the token', () async {
    final r = await call(req('open', {'url': 'yourssh://connect/web-1'}, token: ''), trusted: true);
    expect(r.ok, isTrue);
    expect(fake.calls, ['connect:web-1:url']);
  });

  test('connect via socket path passes source cli', () async {
    final r = await call(req('connect', {'host': 'web-1'}));
    expect(r.ok, isTrue);
    expect((r.result as Map)['host'], containsPair('label', 'web-1'));
    expect(fake.calls, ['connect:web-1:cli']);
  });

  test('ambiguous label gives code 2 with candidates', () async {
    final r = await call(req('connect', {'host': 'dup'}));
    expect(r.code, CliExit.usage);
    expect(r.candidates, hasLength(2));
    expect(fake.calls, isEmpty);
  });

  test('unknown host gives code 2', () async {
    final r = await call(req('connect', {'host': 'nope'}));
    expect(r.code, CliExit.usage);
    expect(fake.calls, isEmpty);
  });

  test('ad hoc target calls connectAdHoc', () async {
    final r = await call(req('connect', {'host': 'root@1.2.3.4:22'}));
    expect(r.ok, isTrue);
    expect(fake.calls, ['adhoc:root@1.2.3.4:22']);
  });

  test('handler failure becomes a runtime error', () async {
    fake.connectError = StateError('boom');
    final r = await call(req('connect', {'host': 'web-1'}));
    expect(r.code, CliExit.runtime);
  });

  test('open yourssh://connect/web-1 connects with source url', () async {
    final r = await call(req('open', {'url': 'yourssh://connect/web-1'}), source: 'url');
    expect(r.ok, isTrue);
    expect(fake.calls, ['connect:web-1:url']);
  });

  test('open via socket still reports source url', () async {
    await call(req('open', {'url': 'yourssh://connect/web-1'}));
    expect(fake.calls, ['connect:web-1:url']);
  });

  test('open percent-decodes once', () async {
    fake._hosts.add(h('Prod DB', id: 'p'));
    final r = await call(req('open', {'url': 'yourssh://connect/Prod%20DB'}));
    expect(r.ok, isTrue);
    expect(fake.calls, ['connect:Prod DB:url']);
  });

  for (final url in [
    'yourssh://connect/..%2F..',
    'yourssh://connect/',
    'yourssh://connect',
    'yourssh://exec/x',
    'yourssh://connect/root@1.2.3.4',
    'yourssh://connect/web-1/extra',
    'yourssh://connect/web-1?x=1',
    'https://example.com/connect/web-1',
    'not a url',
  ]) {
    test('open rejects $url', () async {
      final r = await call(req('open', {'url': url}));
      expect(r.ok, isFalse);
      expect(r.code, CliExit.usage);
      expect(fake.calls, isEmpty);
    });
  }

  test('bad input is rejected and the next request still works', () async {
    for (final bad in [
      '{',
      '{"v":1,"id":"x","token":"${'a' * (70 * 1024)}","cmd":"ls","args":{}}',
      req('rm', {}),
      req('connect', {}),
    ]) {
      final r = await call(bad);
      expect(r.ok, isFalse, reason: bad.substring(0, bad.length.clamp(0, 30)));
    }
    final ok = await call(req('version', {}));
    expect(ok.ok, isTrue);
  });

  test('version', () async {
    final r = await call(req('version', {}));
    expect(r.result, {'app': '9.9.9', 'protocol': 1});
  });

  test('activate focuses the window', () async {
    final r = await call(req('activate', {}));
    expect(r.ok, isTrue);
    expect(r.result, {});
    expect(fake.calls, ['focus']);
  });

  test('ls filters by tag and filter, with no secret keys', () async {
    final r = await call(req('ls', {'tag': 'prod'}));
    final hosts = (r.result as Map)['hosts'] as List;
    expect(hosts, hasLength(1));
    expect((hosts.first as Map)['label'], 'web-1');
    final all = await call(req('ls', {'filter': 'WEB'}));
    expect(((all.result as Map)['hosts'] as List), hasLength(1));
    final raw = jsonEncode((await call(req('ls', {}))).result);
    for (final k in ['password', 'keyId', 'passphrase', 'proxyPassword']) {
      expect(raw, isNot(contains(k)));
    }
  });

  test('handler exception text never reaches the response', () async {
    fake.connectError = Exception('secret /path/key');
    final line = await server.handleLine(req('connect', {'host': 'web-1'}), trusted: false);
    expect(line, isNot(contains('secret')));
    expect(line, isNot(contains('/path/key')));
    expect(CliResponse.decode(line).code, CliExit.runtime);
  });

  test('throwing hosts getter is contained', () async {
    fake.hostsGetter = () => throw StateError('secret hosts');
    for (final r in [req('ls', {}), req('connect', {'host': 'x'})]) {
      final line = await server.handleLine(r, trusted: false);
      expect(line, isNot(contains('secret')));
      expect(CliResponse.decode(line).code, CliExit.runtime);
    }
  });

  test('trusted path only allows open and activate', () async {
    for (final r in [
      req('connect', {'host': 'web-1'}),
      req('ls', {}),
      req('version', {}),
    ]) {
      expect((await call(r, trusted: true)).code, CliExit.denied);
    }
    expect(fake.calls, isEmpty);
    expect((await call(req('activate', {}), trusted: true)).ok, isTrue);
    expect((await call(req('open', {'url': 'yourssh://connect/web-1'}), trusted: true)).ok, isTrue);
  });

  test('invalid UTF-8 percent encoding is code 2', () async {
    final r = await call(req('open', {'url': 'yourssh://connect/%FF'}));
    expect(r.code, CliExit.usage);
    expect(r.error, contains('encoding'));
  });

  test('open accepts uppercase authority', () async {
    final r = await call(req('open', {'url': 'yourssh://CONNECT/web-1'}));
    expect(r.ok, isTrue);
  });

  test('open decodes only once', () async {
    fake._hosts.add(h('a%2Fb', id: 'z'));
    final r = await call(req('open', {'url': 'yourssh://connect/a%252Fb'}));
    expect(r.ok, isTrue);
    expect(fake.calls, ['connect:a%2Fb:url']);
  });

  for (final url in ['yourssh:connect/x', 'yourssh://connect/web-1/']) {
    test('open rejects $url', () async {
      final r = await call(req('open', {'url': url}));
      expect(r.code, CliExit.usage);
      expect(fake.calls, isEmpty);
    });
  }

  group('I3: providers-ready gate (every path)', () {
    test('ls, connect and open wait for it; version and activate do not',
        () async {
      final gate = Completer<void>();
      final server =
          CliServer(handlers: fake, token: tok, ready: gate.future);
      Future<CliResponse> send(String line, {bool trusted = false}) async =>
          CliResponse.decode(
              await server.handleLine(line, trusted: trusted));

      expect((await send(req('version', {}))).ok, isTrue);
      expect((await send(req('activate', {}))).ok, isTrue);
      expect(fake.calls, ['focus']);

      var lsDone = false;
      final ls = send(req('ls', {})).then((r) {
        lsDone = true;
        return r;
      });
      final connect = send(req('connect', {'host': 'web-1'}));
      final open = send(req('open', {'url': 'yourssh://connect/db'}),
          trusted: true);
      await pumpEventQueue();
      expect(lsDone, isFalse);
      expect(fake.calls, ['focus']);

      gate.complete();
      expect(((await ls).result as Map)['hosts'], hasLength(4));
      expect((await connect).ok, isTrue);
      expect((await open).ok, isTrue);
      expect(fake.calls, ['focus', 'connect:web-1:cli', 'connect:db:url']);
    });

    test('never ready within readyTimeout: code 3 (app not ready), nothing runs',
        () async {
      final server = CliServer(
          handlers: fake,
          token: tok,
          ready: Completer<void>().future,
          readyTimeout: const Duration(milliseconds: 50));
      final r = CliResponse.decode(await server.handleLine(
          req('connect', {'host': 'web-1'}),
          trusted: false));
      expect(r.code, CliExit.unreachable);
      expect(fake.calls, isEmpty);
    });

    test('a failing gate is a runtime error and opens nothing', () async {
      final server = CliServer(
          handlers: fake,
          token: tok,
          ready: Future<void>.error(StateError('load failed')));
      final r = CliResponse.decode(await server.handleLine(
          req('open', {'url': 'yourssh://connect/web-1'}),
          trusted: true));
      expect(r.code, CliExit.runtime);
      expect(r.error, isNot(contains('load failed')));
      expect(fake.calls, isEmpty);
    });
  });

  group('I3: same-URL debounce (every path)', () {
    test('a repeat open within 2 s is dropped on any path, then allowed',
        () async {
      var t = DateTime(2026, 1, 1);
      final server = CliServer(handlers: fake, token: tok, now: () => t);
      Future<CliResponse> open(String url, {bool trusted = false}) async =>
          CliResponse.decode(await server.handleLine(
              req('open', {'url': url}, token: trusted ? '' : tok),
              trusted: trusted));

      expect((await open('yourssh://connect/web-1', trusted: true)).ok,
          isTrue);
      t = t.add(const Duration(seconds: 1));
      // Same URL (any case) over the socket: answered, nothing opened.
      final again = await open('YOURSSH://connect/web-1');
      expect(again.ok, isTrue);
      expect(fake.calls, ['connect:web-1:url']);
      // Another URL is not affected.
      await open('yourssh://connect/db');
      expect(fake.calls, ['connect:web-1:url', 'connect:db:url']);
      t = t.add(const Duration(seconds: 2));
      await open('yourssh://connect/web-1');
      expect(fake.calls.where((c) => c == 'connect:web-1:url'), hasLength(2));
    });

    test('slow ready gate: a duplicate arriving during the wait opens nothing',
        () async {
      final gate = Completer<void>();
      final server = CliServer(
          handlers: fake, token: tok, ready: gate.future);
      Future<CliResponse> open() async =>
          CliResponse.decode(await server.handleLine(
              req('open', {'url': 'yourssh://connect/web-1'}, token: ''),
              trusted: true));
      final first = open();
      await pumpEventQueue();
      final second = open(); // arrives while the first still waits
      await pumpEventQueue();
      gate.complete();
      expect((await first).ok, isTrue);
      expect((await second).ok, isTrue);
      expect(fake.calls.where((c) => c == 'connect:web-1:url'), hasLength(1));
    });

    test('the forwarder waits longer than the server holds an open', () {
      expect(kForwardReplyTimeout, greaterThan(CliServer.defaultReadyTimeout));
      expect(CliServer(handlers: fake, token: tok).readyTimeout,
          CliServer.defaultReadyTimeout);
    });

    test('CLI connect is never debounced', () async {
      await call(req('connect', {'host': 'web-1'}));
      await call(req('connect', {'host': 'web-1'}));
      expect(fake.calls, ['connect:web-1:cli', 'connect:web-1:cli']);
    });
  });

  group('M6: refused links are reported', () {
    test('unknown host and bad shape are reported with the URL; '
        'a successful open is not', () async {
      final refused = <String>[];
      final server = CliServer(
          handlers: fake,
          token: tok,
          onUrlRefused: (url, reason) => refused.add('$url | $reason'));
      Future<void> open(String url) =>
          server.handleLine(req('open', {'url': url}, token: ''),
              trusted: true);

      await open('yourssh://connect/web-1');
      await open('yourssh://connect/nope');
      await open('yourssh://exec/rm');
      await open('yourssh://connect/dup');
      expect(refused, [
        'yourssh://connect/nope | unknown host: nope',
        'yourssh://exec/rm | unsupported URL (only yourssh://connect/<host>)',
        'yourssh://connect/dup | ambiguous host: dup',
      ]);
    });

    test('CLI connect failures and handler errors are not link refusals',
        () async {
      final refused = <String>[];
      final server = CliServer(
          handlers: fake,
          token: tok,
          onUrlRefused: (url, reason) => refused.add(url));
      await server.handleLine(req('connect', {'host': 'nope'}),
          trusted: false);
      fake.connectError = StateError('boom');
      await server.handleLine(req('open', {'url': 'yourssh://connect/web-1'}),
          trusted: false);
      expect(refused, isEmpty);
    });
  });
}
