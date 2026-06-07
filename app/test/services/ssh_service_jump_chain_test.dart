import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/system_agent_proxy.dart';

/// Fake client: forwardLocal logs `<label>><host>` and returns a fake
/// channel; close() flips [closed] (read back via isClosed).
class _FakeClient implements SSHClient {
  _FakeClient(this.label, this._log);
  final String label;
  final List<String> _log;
  bool _closed = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<SSHForwardChannel> forwardLocal(String host, int port,
      {String? localHost, int? localPort}) async {
    _log.add('$label>$host');
    return _FakeChannel();
  }

  @override
  void close() => _closed = true;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeChannel implements SSHForwardChannel {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Stubs the per-hop dial primitive so no real socket/auth runs; the
/// caching / ordering / teardown logic in dialChain is what's tested.
/// [failHostAt] makes the dial of that host id throw, to exercise the
/// mid-chain failure path.
class _ProbeSshService extends SshService {
  _ProbeSshService(super.storage, this.log, {this.failHostId});
  final List<String> log;
  final String? failHostId;
  final Map<String, _FakeClient> dialed = {};

  @override
  Future<({SSHClient client, SystemAgentProxy? proxy})> dialHop(
    Host hop,
    SSHSocket? over, {
    SshKeyEntry? keyEntry,
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    log.add(over == null ? 'dial:${hop.host}' : 'tunnel-dial:${hop.host}');
    if (hop.id == failHostId) throw Exception('auth failed: ${hop.id}');
    final c = _FakeClient(hop.host, log);
    dialed[hop.id] = c;
    return (client: c, proxy: null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  Host h(String id, String host) =>
      Host(id: id, label: id, host: host, username: 'u');

  JumpHop hop(String id, String host) => (host: h(id, host), keyEntry: null);

  test('dials hop0 direct, each next over the previous, target over last',
      () async {
    final log = <String>[];
    final svc = _ProbeSshService(StorageService(), log);
    final last = await svc.dialChain(
      target: h('t', '10.0.0.9'),
      chain: [hop('a', '10.0.0.1'), hop('b', '10.0.0.2')],
    );
    await last.forwardLocal('10.0.0.9', 22);
    expect(log, [
      'dial:10.0.0.1', // hop0 direct
      '10.0.0.1>10.0.0.2', // hop0 forwards to hop1
      'tunnel-dial:10.0.0.2', // hop1 dialed over that socket
      '10.0.0.2>10.0.0.9', // hop1 forwards to the target
    ]);
  });

  test('cycle guard: target id inside the chain throws JumpChainException',
      () async {
    final svc = _ProbeSshService(StorageService(), []);
    await expectLater(
      svc.dialChain(
          target: h('t', '10.0.0.9'), chain: [hop('t', '10.0.0.9')]),
      throwsA(isA<JumpChainException>()),
    );
  });

  test('cycle guard: duplicate hop ids throw JumpChainException', () async {
    final svc = _ProbeSshService(StorageService(), []);
    await expectLater(
      svc.dialChain(
          target: h('t', '10.0.0.9'),
          chain: [hop('a', '10.0.0.1'), hop('a', '10.0.0.1')]),
      throwsA(isA<JumpChainException>()),
    );
  });

  test('prefix cache: two targets sharing hop0 reuse one hop0 client',
      () async {
    final log = <String>[];
    final svc = _ProbeSshService(StorageService(), log);
    final chain = [hop('a', '10.0.0.1')];

    final c1 =
        await svc.dialChain(target: h('t1', '10.0.0.8'), chain: chain);
    await c1.forwardLocal('10.0.0.8', 22);
    final c2 =
        await svc.dialChain(target: h('t2', '10.0.0.9'), chain: chain);
    await c2.forwardLocal('10.0.0.9', 22);

    expect(identical(c1, c2), isTrue, reason: 'hop0 client reused');
    expect(log.where((l) => l == 'dial:10.0.0.1').length, 1);
    expect(log.where((l) => l.startsWith('10.0.0.1>')).length, 2);
  });

  test('mid-chain failure closes the hops THIS dial opened (no leak)',
      () async {
    final log = <String>[];
    final svc = _ProbeSshService(StorageService(), log, failHostId: 'c');
    await expectLater(
      svc.dialChain(
        target: h('t', '10.0.0.9'),
        chain: [
          hop('a', '10.0.0.1'),
          hop('b', '10.0.0.2'),
          hop('c', '10.0.0.3'),
        ],
      ),
      throwsException,
    );
    // a and b were opened then must be closed; c never produced a client.
    expect(svc.dialed['a']!.isClosed, isTrue);
    expect(svc.dialed['b']!.isClosed, isTrue);
    expect(svc.dialed.containsKey('c'), isFalse);
  });

  test('shared hop0 survives a sibling target teardown, frees when last goes',
      () async {
    final log = <String>[];
    final svc = _ProbeSshService(StorageService(), log);
    final chain = [hop('a', '10.0.0.1')];
    final t1 = h('t1', '10.0.0.8');
    final t2 = h('t2', '10.0.0.9');
    final shared = await svc.dialChain(target: t1, chain: chain);
    await svc.dialChain(target: t2, chain: chain);

    svc.disconnect(t1.id);
    expect(shared.isClosed, isFalse, reason: 't2 still uses hop0');

    svc.disconnect(t2.id);
    expect(shared.isClosed, isTrue, reason: 'last user gone — hop0 closed');
  });

  test('re-targeting to a shorter chain frees the dropped deeper hop',
      () async {
    final log = <String>[];
    final svc = _ProbeSshService(StorageService(), log);
    final t = h('t', '10.0.0.9');
    await svc.dialChain(
        target: t, chain: [hop('a', '10.0.0.1'), hop('b', '10.0.0.2')]);
    final deepClient = svc.dialed['b']!;

    // Reconnect through just [a]; the 'a>b' prefix is no longer referenced.
    await svc.dialChain(target: t, chain: [hop('a', '10.0.0.1')]);
    expect(deepClient.isClosed, isTrue, reason: 'orphaned deep hop closed');
    expect(svc.dialed['a']!.isClosed, isFalse, reason: 'hop0 still in use');
  });

  test('dead cached hop client is evicted and re-dialed', () async {
    final log = <String>[];
    final svc = _ProbeSshService(StorageService(), log);
    final chain = [hop('a', '10.0.0.1')];
    final c1 = await svc.dialChain(target: h('t1', '10.0.0.8'), chain: chain);
    (c1 as _FakeClient).close(); // link dropped, still cached

    final c2 = await svc.dialChain(target: h('t2', '10.0.0.9'), chain: chain);
    expect(identical(c1, c2), isFalse, reason: 'dead client not reused');
    expect(log.where((l) => l == 'dial:10.0.0.1').length, 2);
  });
}
