import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

class _NullClient implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Captures what _doConnect resolves; never touches the network.
class _CapturingSsh extends SshService {
  _CapturingSsh() : super(StorageService());

  bool? capturedUseTmux;
  String? capturedTermType;

  @override
  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    Host? jumpHost,
    SshKeyEntry? jumpKeyEntry,
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async =>
      _NullClient();

  @override
  Future<void> openShell(
    SshSession session, {
    bool useTmux = false,
    String termType = 'xterm-256color',
  }) async {
    capturedUseTmux = useTmux;
    capturedTermType = termType;
  }
}

// detectedOs set so _doConnect skips the detectOs probe (would hit the
// _NullClient and throw).
Host _host({String? termType, bool? tmuxOverride}) => Host(
      label: 'h',
      host: 'h.com',
      username: 'u',
      detectedOs: 'ubuntu',
      termType: termType,
      tmuxOverride: tmuxOverride,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('per-host TERM/tmux overrides beat the global callbacks', () async {
    final ssh = _CapturingSsh();
    final p = SessionProvider(ssh, TabMetadataService());
    p.tmuxEnabled = () => false;
    p.terminalType = () => 'xterm-256color';

    await p.connect(_host(termType: 'vt100', tmuxOverride: true));

    expect(ssh.capturedTermType, 'vt100');
    expect(ssh.capturedUseTmux, isTrue);
    p.dispose();
  });

  test('null overrides follow the globals', () async {
    final ssh = _CapturingSsh();
    final p = SessionProvider(ssh, TabMetadataService());
    p.tmuxEnabled = () => true;
    p.terminalType = () => 'linux';

    await p.connect(_host());

    expect(ssh.capturedTermType, 'linux');
    expect(ssh.capturedUseTmux, isTrue);
    p.dispose();
  });
}
