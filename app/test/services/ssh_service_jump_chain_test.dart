import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

/// Fake client: forwardLocal logs `<label>><host>` and returns a fake
/// socket; close() flips [closed].
class _FakeClient implements SSHClient {
  _FakeClient(this.label, this._log);
  final String label;
  final List<String> _log;
  bool closed = false;

  @override
  Future<SSHForwardChannel> forwardLocal(String host, int port,
      {String? localHost, int? localPort}) async {
    _log.add('$label>$host');
    return _FakeChannel();
  }

  @override
  void close() => closed = true;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeChannel implements SSHForwardChannel {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Overrides only the per-hop dial primitive so no real socket/auth runs;
/// the prefix-cache + ordering logic in debugDialChain is what's tested.
class _ProbeSshService extends SshService {
  _ProbeSshService(super.storage, this.log);
  final List<String> log;
  final Map<String, _FakeClient> dialed = {};

  @override
  Future<SSHClient> debugDialHop(
    Host hop,
    SSHSocket? over, {
    SshKeyEntry? keyEntry,
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    log.add(over == null ? 'dial:${hop.host}' : 'tunnel-dial:${hop.host}');
    final c = _FakeClient(hop.host, log);
    dialed[hop.host] = c;
    return c;
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
    final last = await svc.debugDialChain(
      target: h('t', '10.0.0.9'),
      chain: [hop('a', '10.0.0.1'), hop('b', '10.0.0.2')],
      verifyHostKey: null,
    );
    // connect() opens the target socket over the returned (last) client.
    await last.forwardLocal('10.0.0.9', 22);
    expect(log, [
      'dial:10.0.0.1', // hop0 direct
      '10.0.0.1>10.0.0.2', // hop0 forwards to hop1
      'tunnel-dial:10.0.0.2', // hop1 dialed over that socket
      '10.0.0.2>10.0.0.9', // hop1 forwards to the target
    ]);
  });

  test('cycle guard: target id inside the chain throws', () async {
    final svc = _ProbeSshService(StorageService(), []);
    await expectLater(
      svc.debugDialChain(
          target: h('t', '10.0.0.9'),
          chain: [hop('t', '10.0.0.9')],
          verifyHostKey: null),
      throwsArgumentError,
    );
  });

  test('cycle guard: duplicate hop ids throw', () async {
    final svc = _ProbeSshService(StorageService(), []);
    await expectLater(
      svc.debugDialChain(
          target: h('t', '10.0.0.9'),
          chain: [hop('a', '10.0.0.1'), hop('a', '10.0.0.1')],
          verifyHostKey: null),
      throwsArgumentError,
    );
  });

  test('prefix cache: two targets sharing hop0 reuse one hop0 client',
      () async {
    final log = <String>[];
    final svc = _ProbeSshService(StorageService(), log);
    final chain = [hop('a', '10.0.0.1')];

    final c1 = await svc.debugDialChain(
        target: h('t1', '10.0.0.8'), chain: chain, verifyHostKey: null);
    await c1.forwardLocal('10.0.0.8', 22);
    final c2 = await svc.debugDialChain(
        target: h('t2', '10.0.0.9'), chain: chain, verifyHostKey: null);
    await c2.forwardLocal('10.0.0.9', 22);

    expect(identical(c1, c2), isTrue, reason: 'hop0 client reused');
    expect(log.where((l) => l == 'dial:10.0.0.1').length, 1);
    expect(log.where((l) => l.startsWith('10.0.0.1>')).length, 2);
  });
}
