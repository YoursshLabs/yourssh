import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/system_agent_proxy.dart';

class _Channel implements SSHForwardChannel {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Socket implements SSHSocket {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Client implements SSHClient {
  _Client();
  final auth = Completer<void>();
  bool closed = false;

  @override
  bool get isClosed => closed;
  @override
  Future<void> get authenticated => auth.future;
  @override
  void close() => closed = true;
  @override
  Future<SSHForwardChannel> forwardLocal(String host, int port,
          {String? localHost, int? localPort}) async =>
      _Channel();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Hands out a scripted client per `connect` and a shared bastion client.
class _Svc extends SshService {
  _Svc() : super(StorageService());
  final built = <_Client>[];
  final hops = <String, _Client>{};

  @override
  Future<SSHSocket> localDial(Host host, {Duration? timeout}) async => _Socket();

  @override
  SSHClient buildConnectClient(SSHSocket socket,
      {required Host host,
      required String? password,
      required List<SSHKeyPair>? identities,
      required Future<bool> Function(String keyType, Uint8List fingerprint)?
          verifyHostKey}) {
    final c = _Client();
    built.add(c);
    return c;
  }

  @override
  Future<({SSHClient client, SystemAgentProxy? proxy})> dialHop(
    Host hop,
    SSHSocket? over, {
    SshKeyEntry? keyEntry,
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    final c = hops.putIfAbsent(hop.id, () => _Client()..auth.complete());
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

  final host = Host(id: 'H', label: 'H', host: 'h.com', username: 'u');
  final bastion = Host(id: 'B', label: 'B', host: 'b.com', username: 'u');

  test('a stale attempt that finishes after the resumed one keeps the live client',
      () async {
    final svc = _Svc();
    var staleCurrent = true;
    final stale = svc.connect(host, isCurrent: () => staleCurrent);
    await Future<void>.delayed(Duration.zero);
    final live = svc.connect(host);
    await Future<void>.delayed(Duration.zero);
    expect(svc.built, hasLength(2));
    svc.built[1].auth.complete();
    final liveClient = await live;

    staleCurrent = false;
    svc.built[0].auth.complete();
    await stale;

    expect(svc.built[0].closed, isTrue);
    expect(liveClient.isClosed, isFalse);
    expect(await svc.ensureClient(host), same(liveClient));
  });

  test('a stale attempt that fails leaves the resumed attempt\'s bastion open',
      () async {
    final svc = _Svc();
    final chain = [(host: bastion, keyEntry: null as SshKeyEntry?)];
    var staleCurrent = true;
    final stale = svc.connect(host, jumpChain: chain, isCurrent: () => staleCurrent);
    await Future<void>.delayed(Duration.zero);
    final live = svc.connect(host, jumpChain: chain);
    await Future<void>.delayed(Duration.zero);
    expect(svc.built, hasLength(2));

    staleCurrent = false;
    svc.built[0].auth.completeError(Exception('network down'));
    await expectLater(stale, throwsException);

    expect(svc.hops['B']!.closed, isFalse);
    svc.built[1].auth.complete();
    await live;
    expect(svc.hops['B']!.closed, isFalse);
  });

  test('without isCurrent a failed attempt still unwinds its jump chain',
      () async {
    final svc = _Svc();
    final chain = [(host: bastion, keyEntry: null as SshKeyEntry?)];
    final f = svc.connect(host, jumpChain: chain);
    await Future<void>.delayed(Duration.zero);
    svc.built[0].auth.completeError(Exception('boom'));
    await expectLater(f, throwsException);
    expect(svc.hops['B']!.closed, isTrue);
  });
}
