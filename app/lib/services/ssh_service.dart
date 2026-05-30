import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/host.dart';
import '../models/ssh_key.dart';
import '../models/ssh_session.dart';
import 'certificate_key_pair.dart';
import 'notification_service.dart';
import 'recording_service.dart';
import 'storage_service.dart';
import 'system_agent_proxy.dart';

class SshService {
  final StorageService _storage;
  final Map<String, SSHClient> _clients = {};
  final Map<String, SSHSession> _shells = {};
  final Map<String, SystemAgentProxy> _agentProxies = {};
  final Map<String, SSHClient> _jumpClients = {};
  final Map<String, SystemAgentProxy> _jumpAgentProxies = {};
  final Map<String, String> _hostToJump = {}; // target hostId → jump hostId
  RecordingService? _recording;
  set recordingService(RecordingService? service) => _recording = service;

  SshService(this._storage);

  // ── Connect ────────────────────────────────────────────

  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    Host? jumpHost,
    SshKeyEntry? jumpKeyEntry,
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
      final SSHSocket socket;
      if (jumpHost != null) {
        final jc = await _ensureJumpClient(
          jumpHost,
          keyEntry: jumpKeyEntry,
          verifyHostKey: verifyHostKey,
        );
        socket = await jc.forwardLocal(host.host, host.port);
        _hostToJump[host.id] = jumpHost.id;
      } else {
        socket = await SSHSocket.connect(host.host, host.port);
      }
      client = SSHClient(
        socket,
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
      _hostToJump.remove(host.id);
      rethrow;
    }
    _clients[host.id] = client;
    return client;
  }

  // ── Jump host helper ───────────────────────────────────

  Future<SSHClient> _ensureJumpClient(
    Host jumpHost, {
    SshKeyEntry? keyEntry,
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    if (_jumpClients.containsKey(jumpHost.id)) {
      return _jumpClients[jumpHost.id]!;
    }
    final password = await _storage.loadPassword(jumpHost.id);

    List<SSHKeyPair> identities = [];
    if (jumpHost.authType == AuthType.privateKey && keyEntry != null) {
      final keyFile = File(keyEntry.privateKeyPath);
      if (await keyFile.exists()) {
        final pem = await keyFile.readAsString();
        final passphrase = await _storage.loadPassphrase(keyEntry.id);
        identities = SSHKeyPair.fromPem(pem, passphrase ?? '');
      }
    } else if (jumpHost.authType == AuthType.certificate && keyEntry != null) {
      final certPath = keyEntry.certificatePath;
      if (certPath == null || !await File(certPath).exists()) {
        throw Exception('Jump host certificate file missing or not linked');
      }
      final passphrase = await _storage.loadPassphrase(keyEntry.id);
      identities = [
        await CertificateKeyPair.load(
          keyPath: keyEntry.privateKeyPath,
          certPath: certPath,
          passphrase: passphrase,
        ),
      ];
    } else if (jumpHost.authType == AuthType.agent) {
      final proxy = await SystemAgentProxy.connect();
      _jumpAgentProxies[jumpHost.id] = proxy;
      try {
        identities = await proxy.getIdentities();
      } catch (e) {
        _jumpAgentProxies.remove(jumpHost.id);
        await proxy.close();
        rethrow;
      }
      if (identities.isEmpty) {
        _jumpAgentProxies.remove(jumpHost.id);
        await proxy.close();
        throw Exception(
          'SSH agent has no identities for jump host. Run "ssh-add <private-key>" to add one.',
        );
      }
    }

    final jumpClient = SSHClient(
      await SSHSocket.connect(jumpHost.host, jumpHost.port),
      username: jumpHost.username,
      onPasswordRequest: () => password ?? '',
      identities: identities.isNotEmpty ? identities : null,
      onVerifyHostKey: (type, fp) async {
        if (verifyHostKey != null) return verifyHostKey(type.toString(), fp);
        return true;
      },
    );
    // Eagerly insert before awaiting auth so that a concurrent caller returns
    // this in-progress client rather than opening a duplicate connection.
    _jumpClients[jumpHost.id] = jumpClient;
    try {
      await jumpClient.authenticated;
    } catch (e) {
      _jumpClients.remove(jumpHost.id);
      unawaited(_jumpAgentProxies[jumpHost.id]?.close() ?? Future.value());
      _jumpAgentProxies.remove(jumpHost.id);
      jumpClient.close();
      rethrow;
    }
    return jumpClient;
  }

  // ── Test connection (TCP + auth, no shell) ────────────

  Future<({bool success, int latencyMs, String? error})> testConnection(
    Host host, {
    String? password,
    SshKeyEntry? keyEntry,
    Host? jumpHost,
    SshKeyEntry? jumpKeyEntry,
  }) async {
    final stopwatch = Stopwatch()..start();
    SSHClient? client;
    SSHClient? jumpClient;
    SystemAgentProxy? agentProxy;
    try {
      SSHSocket socket;
      if (jumpHost != null) {
        final jumpPassword = await _storage.loadPassword(jumpHost.id);
        List<SSHKeyPair> jumpIdentities = [];
        if (jumpHost.authType == AuthType.privateKey && jumpKeyEntry != null) {
          final keyFile = File(jumpKeyEntry.privateKeyPath);
          if (await keyFile.exists()) {
            final pem = await keyFile.readAsString();
            final passphrase = await _storage.loadPassphrase(jumpKeyEntry.id);
            jumpIdentities = SSHKeyPair.fromPem(pem, passphrase ?? '');
          }
        } else if (jumpHost.authType == AuthType.certificate && jumpKeyEntry != null) {
          final certPath = jumpKeyEntry.certificatePath;
          if (certPath == null || !await File(certPath).exists()) {
            return (success: false, latencyMs: 0, error: 'Jump host certificate file missing or not linked');
          }
          final passphrase = await _storage.loadPassphrase(jumpKeyEntry.id);
          jumpIdentities = [
            await CertificateKeyPair.load(
              keyPath: jumpKeyEntry.privateKeyPath,
              certPath: certPath,
              passphrase: passphrase,
            ),
          ];
        }
        jumpClient = SSHClient(
          await SSHSocket.connect(jumpHost.host, jumpHost.port)
              .timeout(const Duration(seconds: 10)),
          username: jumpHost.username,
          onPasswordRequest: () => jumpPassword ?? '',
          identities: jumpIdentities.isNotEmpty ? jumpIdentities : null,
          onVerifyHostKey: (_, _) async => true,
        );
        await jumpClient.authenticated.timeout(const Duration(seconds: 10));
        socket = await jumpClient.forwardLocal(host.host, host.port)
            .timeout(const Duration(seconds: 10));
      } else {
        socket = await SSHSocket.connect(host.host, host.port)
            .timeout(const Duration(seconds: 10));
      }

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
      jumpClient?.close();
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
    final sessionLabel =
        '${session.host.label} (${session.host.username}@${session.host.host})';
    shell.stdout.cast<List<int>>().listen(
      (data) {
        final text = utf8.convert(data);
        session.terminal.write(text);
        _recording?.writeOutput(session.id, text);
        try {
          NotificationService.instance.onTerminalData(
            text,
            sessionId: session.id,
            sessionLabel: sessionLabel,
          );
        } catch (_) {}
      },
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
    NotificationService.instance.removeSession(session.id);
    _recording?.onShellClosed(session.id);
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
    final jumpHostId = _hostToJump.remove(hostId);

    final removed = _shells.keys.where((k) => k.startsWith(hostId)).toList();
    _shells.removeWhere((k, _) => k.startsWith(hostId));
    for (final id in removed) {
      NotificationService.instance.removeSession(id);
    }
    _clients[hostId]?.close();
    _clients.remove(hostId);
    unawaited(_agentProxies[hostId]?.close() ?? Future.value());
    _agentProxies.remove(hostId);

    if (jumpHostId != null && !_hostToJump.values.contains(jumpHostId)) {
      _jumpClients[jumpHostId]?.close();
      _jumpClients.remove(jumpHostId);
      unawaited(_jumpAgentProxies[jumpHostId]?.close() ?? Future.value());
      _jumpAgentProxies.remove(jumpHostId);
    }
  }

  void disconnectSession(String sessionId) {
    _shells[sessionId]?.close();
    _shells.remove(sessionId);
    NotificationService.instance.removeSession(sessionId);
  }

  bool isConnected(String hostId) => _clients.containsKey(hostId);

  // ── OS Detection ────────────────────────────────────────

  static String? parseOsFromUname(String output) {
    final s = output.trim();
    if (s.contains('Linux')) return 'linux';
    if (s.contains('Darwin')) return 'macos';
    if (s.contains('Windows') || s.contains('MINGW') || s.contains('CYGWIN')) return 'windows';
    return null;
  }

  Future<String?> detectOs(Host host) async {
    try {
      final result = await exec(host, 'uname -s 2>/dev/null || ver');
      return parseOsFromUname(result.stdout);
    } catch (_) {
      return null;
    }
  }
}
