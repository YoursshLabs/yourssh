import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/audit_service.dart';
import 'package:yourssh/services/cli/app_cli_handlers.dart';
import 'package:yourssh/services/cli/host_resolver.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

class _NullClient implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// connect() blocks on [gate], like a server waiting on a TOFU / password
/// prompt.
class _GatedSsh extends SshService {
  _GatedSsh() : super(StorageService());
  final gate = Completer<void>();

  @override
  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    List<JumpHop> jumpChain = const [],
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
    Future<bool> Function(Host hop, String keyType, Uint8List fp)?
        verifyHopHostKey,
  }) async {
    await gate.future;
    return _NullClient();
  }

  @override
  Future<void> openShell(session,
      {bool useTmux = false, String termType = 'xterm-256color'}) async {
    await Completer<void>().future; // shell stays open
  }

  @override
  void disconnectSession(String sessionId) {}

  @override
  void disconnect(String hostId) {}
}

Host _host() => Host(label: 'prod', host: 'p.com', username: 'root');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'connect returns once the tab exists, without awaiting authentication, '
      'then focuses', () async {
    final ssh = _GatedSsh();
    final sessions = SessionProvider(ssh, TabMetadataService());
    final focused = <String>[];
    final handlers = AppCliHandlers(
      sessions: sessions,
      hostProvider: HostProvider(StorageService()),
      focus: () async => focused.add('focus'),
      appVersion: '1.2.3',
    );

    // The gate is never opened: if connect() awaited auth this would hang.
    await handlers
        .connect(_host(), source: 'cli')
        .timeout(const Duration(seconds: 2));

    expect(sessions.sessions.length, 1);
    expect(focused, ['focus']);
    expect(handlers.appVersion, '1.2.3');
    ssh.gate.complete();
    sessions.dispose();
  });

  test('the connect audit row carries the CLI source', () async {
    final ssh = _GatedSsh();
    final audit = AuditService()..initInMemory();
    final sessions = SessionProvider(ssh, TabMetadataService())..audit = audit;
    final handlers = AppCliHandlers(
      sessions: sessions,
      hostProvider: HostProvider(StorageService()),
      focus: () async {},
      appVersion: '1',
    );

    await handlers.connect(_host(), source: 'url');
    ssh.gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final rows = audit.query(const AuditFilter(type: 'connect'));
    expect(rows.length, 1);
    expect(rows.single.meta['source'], 'url');
    sessions.dispose();
    audit.dispose();
  });

  test('connectAdHoc opens a transient host tab', () async {
    final ssh = _GatedSsh();
    final sessions = SessionProvider(ssh, TabMetadataService());
    final handlers = AppCliHandlers(
      sessions: sessions,
      hostProvider: HostProvider(StorageService()),
      focus: () async {},
      appVersion: '1',
    );
    await handlers.connectAdHoc(const AdHocTarget('me', 'h.example', 2222));
    final s = sessions.sshSessions.single;
    expect(s.host.username, 'me');
    expect(s.host.host, 'h.example');
    expect(s.host.port, 2222);
    ssh.gate.complete();
    sessions.dispose();
  });
}
