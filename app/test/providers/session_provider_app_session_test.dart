import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/rdp_session.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/models/terminal_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh_rdp/yourssh_rdp.dart' show RdpClient, RdpConfig;

// port 1 on localhost → quick connection-refused (mirrors other provider tests)
Host _sshHost() => Host(
    id: 'ssh1', label: 'server', host: '127.0.0.1', port: 1, username: 'u');

Host _rdpHost() => Host(
    id: 'rdp1',
    label: 'win',
    host: '10.0.0.2',
    port: 3389,
    username: 'u',
    authType: AuthType.password,
    protocol: HostProtocol.rdp);

RdpClient _rdpClient() => RdpClient(RdpConfig(
    targetHost: '10.0.0.2',
    targetPort: 3389,
    username: 'u',
    password: '',
    domain: null,
    width: 1280,
    height: 800,
    security: 'auto'));

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

  group('AppSession type hierarchy', () {
    test('SshSession is a TerminalSession', () {
      final s = SshSession(host: _sshHost());
      expect(s, isA<TerminalSession>());
    });

    test('RdpSession is not a TerminalSession', () {
      final s = RdpSession(
          host: _rdpHost(), client: _rdpClient(), width: 1280, height: 800);
      expect(s is TerminalSession, isFalse);
    });
  });

  group('SessionProvider.activeSshSession with SSH session', () {
    late SessionProvider p;

    setUp(() {
      p = SessionProvider(SshService(StorageService()), TabMetadataService());
    });

    tearDown(() => p.dispose());

    test('activeSshSession returns active SSH session', () async {
      // connect() adds the session synchronously before the first internal
      // await; fire without awaiting and yield one microtask to let it land.
      final future = p.connect(_sshHost());
      await Future<void>.delayed(Duration.zero);

      expect(p.activeSession is TerminalSession, isTrue);
      expect(p.activeSshSession, isNotNull);

      // close the session so connect() can complete cleanly.
      p.closeSession(p.sessions.first.id);
      await expectLater(future, completes);
    });

    test('activeSshSession is null when no sessions', () {
      expect(p.activeSshSession, isNull);
    });
  });
}
