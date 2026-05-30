import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/host.dart';
import '../models/ssh_key.dart';
import '../models/ssh_session.dart';
import 'certificate_key_pair.dart';
import 'storage_service.dart';
import 'system_agent_proxy.dart';

class SshService {
  final StorageService _storage;
  final Map<String, SSHClient> _clients = {};
  final Map<String, SSHSession> _shells = {};
  final Map<String, SystemAgentProxy> _agentProxies = {};

  SshService(this._storage);

  // ── Connect ────────────────────────────────────────────

  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    final password = await _storage.loadPassword(host.id);

    List<SSHKeyPair> identities = [];
    if (host.authType == AuthType.privateKey && keyEntry != null) {
      final keyFile = File(keyEntry.privateKeyPath);
      if (await keyFile.exists()) {
        final pem = await keyFile.readAsString();
        final passphrase = await _storage.loadPassphrase(keyEntry.id);
        identities = SSHKeyPair.fromPem(pem, passphrase ?? '');
      }
    } else if (host.authType == AuthType.certificate && keyEntry != null) {
      final certPath = keyEntry.certificatePath;
      if (certPath == null) {
        throw Exception('No certificate linked to key "${keyEntry.label}". Add one in Keychain.');
      }
      if (!await File(certPath).exists()) {
        throw Exception('Certificate file not found: $certPath');
      }
      final passphrase = await _storage.loadPassphrase(keyEntry.id);
      identities = [
        await CertificateKeyPair.load(
          keyPath: keyEntry.privateKeyPath,
          certPath: certPath,
          passphrase: passphrase,
        ),
      ];
    } else if (host.authType == AuthType.agent) {
      final proxy = await SystemAgentProxy.connect();
      _agentProxies[host.id] = proxy;
      try {
        identities = await proxy.getIdentities();
      } catch (e) {
        _agentProxies.remove(host.id);
        await proxy.close();
        rethrow;
      }
      if (identities.isEmpty) {
        _agentProxies.remove(host.id);
        await proxy.close();
        throw Exception(
          'SSH agent has no identities. Run "ssh-add <private-key>" to add one.',
        );
      }
    }

    final SSHClient client;
    try {
      client = SSHClient(
        await SSHSocket.connect(host.host, host.port),
        username: host.username,
        onPasswordRequest: () => password ?? '',
        identities: identities.isNotEmpty ? identities : null,
        onVerifyHostKey: (type, fp) async {
          if (verifyHostKey != null) return verifyHostKey(type.toString(), fp);
          return true;
        },
      );
      await client.authenticated;
    } catch (e) {
      if (host.authType == AuthType.agent) {
        unawaited(_agentProxies[host.id]?.close() ?? Future.value());
        _agentProxies.remove(host.id);
      }
      rethrow;
    }
    _clients[host.id] = client;
    return client;
  }

  // ── Test connection (TCP + auth, no shell) ────────────

  Future<({bool success, int latencyMs, String? error})> testConnection(
    Host host, {
    String? password,
    SshKeyEntry? keyEntry,
  }) async {
    final stopwatch = Stopwatch()..start();
    SSHClient? client;
    SystemAgentProxy? agentProxy;
    try {
      final socket = await SSHSocket.connect(host.host, host.port)
          .timeout(const Duration(seconds: 10));

      List<SSHKeyPair> identities = [];
      if (host.authType == AuthType.privateKey && keyEntry != null) {
        final keyFile = File(keyEntry.privateKeyPath);
        if (await keyFile.exists()) {
          final pem = await keyFile.readAsString();
          final passphrase = await _storage.loadPassphrase(keyEntry.id);
          identities = SSHKeyPair.fromPem(pem, passphrase ?? '');
        }
      } else if (host.authType == AuthType.certificate && keyEntry != null) {
        final certPath = keyEntry.certificatePath;
        if (certPath == null || !await File(certPath).exists()) {
          return (success: false, latencyMs: 0, error: 'Certificate file missing or not linked');
        }
        final passphrase = await _storage.loadPassphrase(keyEntry.id);
        identities = [
          await CertificateKeyPair.load(
            keyPath: keyEntry.privateKeyPath,
            certPath: certPath,
            passphrase: passphrase,
          ),
        ];
      } else if (host.authType == AuthType.agent) {
        try {
          agentProxy = await SystemAgentProxy.connect();
          identities = await agentProxy.getIdentities();
          // Keep proxy alive until after client.authenticated — agent keys
          // need the socket open to sign the challenge.
        } on SSHAgentUnavailableException catch (e) {
          return (success: false, latencyMs: 0, error: e.message);
        }
      }

      client = SSHClient(
        socket,
        username: host.username,
        onPasswordRequest: () => password ?? '',
        identities: identities.isNotEmpty ? identities : null,
        onVerifyHostKey: (_, _) async => true,
      );
      await client.authenticated.timeout(const Duration(seconds: 10));
      stopwatch.stop();
      return (success: true, latencyMs: stopwatch.elapsedMilliseconds, error: null);
    } on TimeoutException {
      return (success: false, latencyMs: 0, error: 'Host unreachable');
    } on SocketException {
      return (success: false, latencyMs: 0, error: 'Host unreachable');
    } catch (e) {
      final msg = e.toString();
      final isAuth = msg.toLowerCase().contains('auth') ||
          msg.toLowerCase().contains('permission denied') ||
          msg.toLowerCase().contains('userauth');
      return (
        success: false,
        latencyMs: 0,
        error: isAuth
            ? 'Authentication failed'
            : (msg.length > 80 ? '${msg.substring(0, 80)}…' : msg),
      );
    } finally {
      client?.close();
      await agentProxy?.close();
    }
  }

  // ── Shell session (feeds into xterm Terminal) ──────────

  Future<void> openShell(SshSession session, {bool useTmux = false}) async {
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

    if (useTmux) {
      shell.write(Uint8List.fromList('tmux new-session -A -s yourssh\n'.codeUnits));
    }

    final done = Completer<void>();
    const utf8 = Utf8Decoder(allowMalformed: true);

    // Pipe SSH output → xterm terminal; complete when shell closes
    shell.stdout.cast<List<int>>().listen(
      (data) => session.terminal.write(utf8.convert(data)),
      onDone: () {
        _onShellClosed(session);
        if (!done.isCompleted) done.complete();
      },
      onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      },
      cancelOnError: true,
    );
    shell.stderr.cast<List<int>>().listen(
      (data) => session.terminal.write(utf8.convert(data)),
    );

    // Pipe xterm input → SSH shell
    session.terminal.onOutput = (data) {
      shell.write(Uint8List.fromList(data.codeUnits));
    };

    // Handle terminal resize
    session.terminal.onResize = (w, h, pw, ph) {
      shell.resizeTerminal(w, h);
    };

    // Wait until the remote shell actually closes
    await done.future;
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
    unawaited(_agentProxies[hostId]?.close() ?? Future.value());
    _agentProxies.remove(hostId);
  }

  void disconnectSession(String sessionId) {
    _shells[sessionId]?.close();
    _shells.remove(sessionId);
  }

  bool isConnected(String hostId) => _clients.containsKey(hostId);
}
