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

class _CapturingSsh extends SshService {
  _CapturingSsh() : super(StorageService());
  List<JumpHop>? capturedChain;

  @override
  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    List<JumpHop> jumpChain = const [],
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
    Future<bool> Function(Host hop, String keyType, Uint8List fp)?
        verifyHopHostKey,
  }) async {
    capturedChain = jumpChain;
    throw Exception('stop-before-shell');
  }
}

Host _bastion(String id) => Host(
    id: id, label: id, host: '$id.com', username: 'u', detectedOs: 'ubuntu');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('_doConnect resolves the full chain in order', () async {
    final ssh = _CapturingSsh();
    final p = SessionProvider(ssh, TabMetadataService());
    final a = _bastion('a'), b = _bastion('b');
    p.jumpHostLookup = (id) => {'a': a, 'b': b}[id];

    await p.connect(Host(
        label: 't',
        host: 't.com',
        username: 'u',
        detectedOs: 'ubuntu',
        jumpHostIds: ['a', 'b']));

    expect(ssh.capturedChain?.map((h) => h.host.id), ['a', 'b']);
    p.dispose();
  });

  test('an unresolved hop fails the connect (no silent skip)', () async {
    final ssh = _CapturingSsh();
    final p = SessionProvider(ssh, TabMetadataService());
    p.jumpHostLookup = (_) => null; // hop missing

    await p.connect(Host(
        label: 't',
        host: 't.com',
        username: 'u',
        detectedOs: 'ubuntu',
        jumpHostIds: ['gone']));

    // connect never reached: chain resolution threw first.
    expect(ssh.capturedChain, isNull);
    expect(p.sshSessions.single.status, SessionStatus.error);
    p.dispose();
  });
}
