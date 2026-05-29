import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/host.dart';
import '../models/ssh_key.dart';
import '../models/ssh_session.dart';
import 'storage_service.dart';

class SshService {
  final StorageService _storage;
  final Map<String, SSHClient> _clients = {};
  final Map<String, SSHSession> _shells = {};

  SshService(this._storage);

  // ── Connect ────────────────────────────────────────────

  Future<SSHClient> connect(Host host, {SshKeyEntry? keyEntry}) async {
    final password = await _storage.loadPassword(host.id);

    List<SSHKeyPair> identities = [];
    if (host.authType == AuthType.privateKey && keyEntry != null) {
      final keyFile = File(keyEntry.privateKeyPath);
      if (await keyFile.exists()) {
        final pem = await keyFile.readAsString();
        final passphrase = await _storage.loadPassphrase(keyEntry.id);
        identities = SSHKeyPair.fromPem(pem, passphrase ?? '');
      }
    }

    final client = SSHClient(
      await SSHSocket.connect(host.host, host.port),
      username: host.username,
      onPasswordRequest: () => password ?? '',
      identities: identities.isNotEmpty ? identities : null,
      onVerifyHostKey: (type, fingerprint) => true,
    );

    await client.authenticated;
    _clients[host.id] = client;
    return client;
  }

  // ── Shell session (feeds into xterm Terminal) ──────────

  Future<void> openShell(SshSession session) async {
    final client = _clients[session.host.id];
    if (client == null) throw Exception('Not connected');

    final shell = await client.shell(
      pty: SSHPtyConfig(
        width: 80,
        height: 24,
        type: 'xterm-256color',
      ),
    );

    _shells[session.id] = shell;

    // Pipe SSH output → xterm terminal
    shell.stdout.cast<List<int>>().listen(
      (data) => session.terminal.write(String.fromCharCodes(data)),
      onDone: () => _onShellClosed(session),
    );
    shell.stderr.cast<List<int>>().listen(
      (data) => session.terminal.write(String.fromCharCodes(data)),
    );

    // Pipe xterm input → SSH shell
    session.terminal.onOutput = (data) {
      shell.write(Uint8List.fromList(data.codeUnits));
    };

    // Handle terminal resize
    session.terminal.onResize = (w, h, pw, ph) {
      shell.resizeTerminal(w, h);
    };
  }

  void _onShellClosed(SshSession session) {
    _shells.remove(session.id);
    session.terminal.write('\r\n\x1b[31m[Connection closed]\x1b[0m\r\n');
  }

  // ── Exec ───────────────────────────────────────────────

  Future<({String stdout, String stderr, int exitCode})> exec(
    Host host,
    String command,
  ) async {
    final client = _clients[host.id] ?? await connect(host);
    final result = await client.run(command);
    return (
      stdout: String.fromCharCodes(result),
      stderr: '',
      exitCode: 0,
    );
  }

  // ── SFTP ───────────────────────────────────────────────

  Future<SftpClient> openSftp(Host host) async {
    final client = _clients[host.id] ?? await connect(host);
    return client.sftp();
  }

  // ── Disconnect ─────────────────────────────────────────

  void disconnect(String hostId) {
    _shells.removeWhere((k, _) => k.startsWith(hostId));
    _clients[hostId]?.close();
    _clients.remove(hostId);
  }

  void disconnectSession(String sessionId) {
    _shells[sessionId]?.close();
    _shells.remove(sessionId);
  }

  bool isConnected(String hostId) => _clients.containsKey(hostId);
}
