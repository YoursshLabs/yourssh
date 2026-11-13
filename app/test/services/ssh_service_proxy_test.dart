import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/proxy_settings.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

class _FakeSocket implements SSHSocket {
  @override
  Stream<Uint8List> get stream => const Stream.empty();
  @override
  StreamSink<List<int>> get sink => throw UnimplementedError();
  @override
  Future<void> get done => Future.value();
  @override
  Future<void> close() async {
    closed = true;
  }
  @override
  void destroy() {
    closed = true;
  }
  bool closed = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('localDial uses the direct dialer when proxyType is none', () async {
    final svc = SshService(StorageService());
    final fake = _FakeSocket();
    String? dialedHost;
    int? dialedPort;
    svc.directDialer = (h, p, {timeout}) async {
      dialedHost = h;
      dialedPort = p;
      return fake;
    };
    svc.proxyDialer =
        ({required settings, required targetHost, required targetPort, timeout}) async =>
            throw StateError('proxy dialer must not be called');

    final host = Host(label: 'a', host: 'srv', port: 22, username: 'u');
    final s = await svc.localDial(host);

    expect(identical(s, fake), isTrue);
    expect(dialedHost, 'srv');
    expect(dialedPort, 22);
  });

  test('localDial uses the proxy dialer with resolved settings', () async {
    final svc = SshService(StorageService());
    final host = Host(
        label: 'a',
        host: 'target',
        port: 2222,
        username: 'u',
        proxyType: ProxyType.socks5,
        proxyHost: 'proxy',
        proxyPort: 1080,
        proxyUsername: 'pu');
    await svc.saveProxyPassword(host.id, 'secret');

    ProxySettings? got;
    String? gotTarget;
    int? gotPort;
    svc.proxyDialer =
        ({required settings, required targetHost, required targetPort, timeout}) async {
      got = settings;
      gotTarget = targetHost;
      gotPort = targetPort;
      return _FakeSocket();
    };

    await svc.localDial(host);

    expect(got!.type, ProxyType.socks5);
    expect(got!.host, 'proxy');
    expect(got!.port, 1080);
    expect(got!.username, 'pu');
    expect(got!.password, 'secret');
    expect(gotTarget, 'target');
    expect(gotPort, 2222);
  });

  test('localDial gives up on a dial that never completes (stalled DNS)',
      () async {
    final svc = SshService(StorageService())
      ;
    svc.directDialer = (h, p, {timeout}) => Completer<SSHSocket>().future;
    final host = Host(label: 'a', host: 'db-internal', port: 22, username: 'u');

    await expectLater(
      svc.localDial(host),
      throwsA(isA<TimeoutException>().having(
          (e) => e.message, 'message', contains('db-internal:22'))),
    );
  });

  test('a dial that completes after the timeout has its socket closed',
      () async {
    final svc = SshService(StorageService())
      ..connectTimeout = const Duration(milliseconds: 50);
    final late = Completer<SSHSocket>();
    svc.directDialer = (h, p, {timeout}) => late.future;
    final host = Host(label: 'a', host: 'slow', port: 22, username: 'u');

    await expectLater(svc.localDial(host), throwsA(isA<TimeoutException>()));
    final sock = _FakeSocket();
    late.complete(sock);
    await Future<void>.delayed(Duration.zero);

    expect(sock.closed, isTrue);
  });

  test('a dial that fails after the timeout raises no unhandled error',
      () async {
    final svc = SshService(StorageService())
      ..connectTimeout = const Duration(milliseconds: 50);
    final late = Completer<SSHSocket>();
    svc.directDialer = (h, p, {timeout}) => late.future;
    final host = Host(label: 'a', host: 'slow', port: 22, username: 'u');

    await expectLater(svc.localDial(host), throwsA(isA<TimeoutException>()));
    late.completeError(const SocketException('late failure'));
    await Future<void>.delayed(Duration.zero);
  });
}
