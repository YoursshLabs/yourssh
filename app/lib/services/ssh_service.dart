import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:yourssh_script_engine/yourssh_script_engine.dart';
import '../providers/shell_integration_provider.dart';
import '../models/host.dart';
import '../models/ssh_key.dart';
import '../models/ssh_session.dart';
import 'certificate_key_pair.dart';
import 'injection_gate.dart';
import 'notification_service.dart';
import 'shell_integration_service.dart';
import 'recording_service.dart';
import 'storage_service.dart';
import 'sudo_sftp.dart';
import 'system_agent_proxy.dart';

class SshService {
  final StorageService _storage;
  final HookBus? hookBus;
  final ShellIntegrationProvider? shellIntegration;

  /// Global on/off for shell integration, read from SettingsProvider in
  /// main.dart. null => treat as enabled.
  bool Function()? isShellIntegrationEnabled;
  final Map<String, SSHClient> _clients = {};
  final Map<String, SSHSession> _shells = {};
  final Map<String, String> _shellToHost = {}; // sessionId → hostId
  final Map<String, SystemAgentProxy> _agentProxies = {};
  final Map<String, SSHClient> _jumpClients = {};
  final Map<String, SystemAgentProxy> _jumpAgentProxies = {};
  final Map<String, String> _hostToJump = {}; // target hostId → jump hostId
  RecordingService? _recording;
  set recordingService(RecordingService? service) => _recording = service;

  /// Verifier used when [exec]/[openSftp] auto-connect without an explicit
  /// verifier (e.g., DevOps tools invoking a one-off command). Set from main.dart
  /// to KnownHostsProvider.verifyHostKey used by interactive connects;
  /// without this, auto-connect throws to prevent silent TOFU bypass.
  Future<bool> Function(String host, int port, String keyType, Uint8List fp)?
      defaultHostKeyVerifier;

  /// Optional Host.keyId → key entry resolver for auto-connect paths
  /// (exec, tunnels) — mirrors SessionProvider.keyLookup for shells.
  SshKeyEntry? Function(String keyId)? defaultKeyLookup;

  /// Prompts the user for a sudo password (elevated SFTP). Set from
  /// main.dart; returning null cancels the elevated SFTP attempt. The
  /// password is persisted (when `remember` is set) only after it validates —
  /// see [_openElevatedSftp].
  Future<({String password, bool remember})?> Function(Host host)?
      sudoPasswordPrompt;

  SshService(this._storage, {this.hookBus, this.shellIntegration});

  // ── Identity resolution ───────────────────────────────
  //
  // Resolves the SSH key material for a given host, keyed by [host.authType].
  // Centralised so connect / _ensureJumpClient / testConnection don't drift.
  // The caller owns the returned agentProxy: connect/jump store it on a long-
  // lived map; testConnection closes it in finally.

  Future<_IdentityResolution> _resolveIdentities(
    Host host,
    SshKeyEntry? keyEntry, {
    String? jumpHostLabel,
  }) async {
    switch (host.authType) {
      case AuthType.password:
        return const _IdentityResolution([]);
      case AuthType.privateKey:
        if (keyEntry == null) return const _IdentityResolution([]);
        final keyFile = File(keyEntry.privateKeyPath);
        if (!await keyFile.exists()) return const _IdentityResolution([]);
        final pem = await keyFile.readAsString();
        final passphrase = await _storage.loadPassphrase(keyEntry.id);
        final effectivePassphrase = passphrase?.isNotEmpty == true ? passphrase : null;
        return _IdentityResolution(SSHKeyPair.fromPem(pem, effectivePassphrase));
      case AuthType.certificate:
        if (keyEntry == null) {
          throw Exception(jumpHostLabel == null
              ? 'No key linked for certificate auth'
              : 'No key linked for jump host "$jumpHostLabel" certificate auth');
        }
        final certPath = keyEntry.certificatePath;
        if (certPath == null) {
          throw Exception(jumpHostLabel == null
              ? 'No certificate linked to key "${keyEntry.label}". Add one in Keychain.'
              : 'Jump host certificate file missing or not linked');
        }
        if (!await File(certPath).exists()) {
          throw Exception(jumpHostLabel == null
              ? 'Certificate file not found: $certPath'
              : 'Jump host certificate file not found: $certPath');
        }
        final passphrase = await _storage.loadPassphrase(keyEntry.id);
        return _IdentityResolution([
          await CertificateKeyPair.load(
            keyPath: keyEntry.privateKeyPath,
            certPath: certPath,
            passphrase: passphrase,
          ),
        ]);
      case AuthType.agent:
        final proxy = await SystemAgentProxy.connect();
        try {
          final identities = await proxy.getIdentities();
          if (identities.isEmpty) {
            await proxy.close();
            throw Exception(jumpHostLabel == null
                ? 'SSH agent has no identities. Run "ssh-add <private-key>" to add one.'
                : 'SSH agent has no identities for jump host. Run "ssh-add <private-key>" to add one.');
          }
          return _IdentityResolution(identities, proxy);
        } catch (_) {
          await proxy.close();
          rethrow;
        }
    }
  }

  // ── Connect ────────────────────────────────────────────

  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    Host? jumpHost,
    SshKeyEntry? jumpKeyEntry,
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    if (hookBus != null) {
      final result = hookBus!.fireInterceptable(
        'session.connect.before',
        TransformEvent(sessionId: host.id, data: host.host),
      );
      if (result == null) {
        throw Exception('Connection cancelled by plugin');
      }
    }

    final password = await _storage.loadPassword(host.id);
    final resolution = await _resolveIdentities(host, keyEntry);
    if (resolution.agentProxy != null) {
      _agentProxies[host.id] = resolution.agentProxy!;
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
        identities: resolution.identities.isNotEmpty ? resolution.identities : null,
        onVerifyHostKey: (type, fp) async {
          if (verifyHostKey != null) return verifyHostKey(type.toString(), fp);
          return true;
        },
        // Built-in keepalive is disabled: HealthMonitorService is the sole
        // pinger (it both keeps the connection alive and measures latency),
        // avoiding a race on the shared global-request reply queue.
        keepAliveInterval: null,
      );
      await client.authenticated;
    } catch (e) {
      if (resolution.agentProxy != null) {
        unawaited(_agentProxies[host.id]?.close() ?? Future.value());
        _agentProxies.remove(host.id);
      }
      final jumpId = _hostToJump.remove(host.id);
      if (jumpId != null && !_hostToJump.values.contains(jumpId)) {
        _jumpClients[jumpId]?.close();
        _jumpClients.remove(jumpId);
        unawaited(_jumpAgentProxies[jumpId]?.close() ?? Future.value());
        _jumpAgentProxies.remove(jumpId);
      }
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
    final resolution = await _resolveIdentities(
      jumpHost,
      keyEntry,
      jumpHostLabel: jumpHost.label,
    );
    if (resolution.agentProxy != null) {
      _jumpAgentProxies[jumpHost.id] = resolution.agentProxy!;
    }

    final jumpClient = SSHClient(
      await SSHSocket.connect(jumpHost.host, jumpHost.port),
      username: jumpHost.username,
      onPasswordRequest: () => password ?? '',
      identities: resolution.identities.isNotEmpty ? resolution.identities : null,
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
    SystemAgentProxy? jumpAgentProxyForTest;
    try {
      SSHSocket socket;
      if (jumpHost != null) {
        final jumpPassword = await _storage.loadPassword(jumpHost.id);
        final jumpResolution = await _resolveIdentities(
          jumpHost,
          jumpKeyEntry,
          jumpHostLabel: jumpHost.label,
        );
        // Track for cleanup; closed in `finally` below.
        jumpAgentProxyForTest = jumpResolution.agentProxy;
        jumpClient = SSHClient(
          await SSHSocket.connect(jumpHost.host, jumpHost.port)
              .timeout(const Duration(seconds: 10)),
          username: jumpHost.username,
          onPasswordRequest: () => jumpPassword ?? '',
          identities:
              jumpResolution.identities.isNotEmpty ? jumpResolution.identities : null,
          onVerifyHostKey: (_, _) async => true,
        );
        await jumpClient.authenticated.timeout(const Duration(seconds: 10));
        socket = await jumpClient.forwardLocal(host.host, host.port)
            .timeout(const Duration(seconds: 10));
      } else {
        socket = await SSHSocket.connect(host.host, host.port)
            .timeout(const Duration(seconds: 10));
      }

      final resolution = await _resolveIdentities(host, keyEntry);
      agentProxy = resolution.agentProxy;
      client = SSHClient(
        socket,
        username: host.username,
        onPasswordRequest: () => password ?? '',
        identities: resolution.identities.isNotEmpty ? resolution.identities : null,
        onVerifyHostKey: (_, _) async => true,
      );
      await client.authenticated.timeout(const Duration(seconds: 10));
      stopwatch.stop();
      return (success: true, latencyMs: stopwatch.elapsedMilliseconds, error: null);
    } on SSHAgentUnavailableException catch (e) {
      return (success: false, latencyMs: 0, error: e.message);
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
      await jumpAgentProxyForTest?.close();
    }
  }

  // ── Health monitoring ─────────────────────────────────

  /// Host ids with a live client. Used by HealthMonitorService to know which
  /// connections to ping.
  Iterable<String> get connectedHostIds => _clients.keys;

  /// Round-trip latency (ms) of a keepalive ping over [hostId]'s live client,
  /// or null when there is no client or the ping fails / times out. The timeout
  /// is what surfaces half-open connections (the channel has not closed yet).
  Future<int?> measureLatency(String hostId) async {
    final client = _clients[hostId];
    if (client == null) return null;
    final sw = Stopwatch()..start();
    try {
      await client.ping().timeout(const Duration(seconds: 5));
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
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
    _shellToHost[session.id] = session.host.id;

    // Shell integration (OSC 7/133): route private OSC into the provider before
    // any output arrives, so the first prompt cycle is captured.
    final siOn = shellIntegration != null &&
        session.host.shellIntegration &&
        (isShellIntegrationEnabled?.call() ?? true);
    if (siOn) {
      session.terminal.onPrivateOSC = (code, args) => shellIntegration!.handleOsc(
            session.id,
            code,
            args,
            session.terminal.buffer.absoluteCursorY,
          );
    }

    hookBus?.fireObserve('session.connect', ObserveEvent(
      sessionId: session.id,
      payload: {
        'host': session.host.host,
        'username': session.host.username,
        'port': session.host.port,
      },
    ));

    if (useTmux) {
      shell.write(Uint8List.fromList('tmux new-session -A -s yourssh\n'.codeUnits));
    }

    final initialCommand = session.initialCommand;
    if (initialCommand != null && initialCommand.isNotEmpty) {
      shell.write(Uint8List.fromList('$initialCommand\n'.codeUnits));
    }

    // Invisible shell-integration injection (two-phase handshake; see
    // docs/superpowers/specs/2026-06-03-invisible-shell-integration-design.md).
    // Readiness → bootstrap → RDY → payload (never echoed via read -rs) →
    // DONE → discard the withheld bootstrap echo. Readiness is the bracketed-
    // paste toggle (line editor reading) + a settle period; shells without it
    // (bash ≤ 5.0) get a bare-\n probe answered by a prompt-like tail. If
    // readiness is never confirmed the injection is skipped entirely — a
    // missing integration beats junk typed into a half-initialized session.
    InjectionGate? gate;
    final readiness = InjectionReadiness();
    Timer? settleTimer;
    Timer? quietTimer;
    Timer? probeWindowTimer;
    Timer? doneTimer;
    var awaitingProbe = false;
    var sinceProbe = '';
    var probesLeft = 4;
    var injectionAborted = false;
    DateTime? firstOutputAt;

    void cancelReadinessTimers() {
      settleTimer?.cancel();
      quietTimer?.cancel();
      probeWindowTimer?.cancel();
    }

    void launchInjection() {
      if (!siOn || gate != null || injectionAborted) return;
      cancelReadinessTimers();
      awaitingProbe = false;
      final bootstrap = shellIntegration!.buildBootstrapLine();
      gate = InjectionGate(
        readySentinel: ShellIntegrationService.kReadySentinel,
        doneSentinel: ShellIntegrationService.kDoneSentinel,
        // Generous: the head is echo + line-editor redraw noise; only a
        // genuinely streaming command produces more, and that must be shown.
        maxHold: 16384,
      );
      shell.write(Uint8List.fromList(bootstrap.codeUnits));
      doneTimer = Timer(const Duration(seconds: 2), () {
        final g = gate;
        if (g == null || !g.isHolding) return;
        final out = g.flush(); // degrade: show as-is
        if (out.isNotEmpty) session.terminal.write(out);
      });
    }

    // Probe fallback scheduler: after 1.2 s of silence (and a 2.5 s floor so
    // instant-prompt frameworks have revealed their bracketed paste), send a
    // bare "\n". A real prompt answers it; MOTD-in-progress only produces a
    // kernel echo. Out of probes → give up cleanly.
    void armQuietProbe() {
      if (!siOn ||
          gate != null ||
          injectionAborted ||
          awaitingProbe ||
          readiness.bpEver) {
        return;
      }
      quietTimer?.cancel();
      quietTimer = Timer(const Duration(milliseconds: 1200), () {
        if (gate != null || injectionAborted || readiness.bpEver) return;
        final first = firstOutputAt;
        if (first == null ||
            DateTime.now().difference(first) <
                const Duration(milliseconds: 2500)) {
          armQuietProbe(); // too early; keep waiting
          return;
        }
        if (probesLeft <= 0) {
          injectionAborted = true; // never confirmed: skip, stay clean
          return;
        }
        probesLeft--;
        awaitingProbe = true;
        sinceProbe = '';
        shell.write(Uint8List.fromList('\n'.codeUnits));
        probeWindowTimer = Timer(const Duration(seconds: 1), () {
          awaitingProbe = false;
          armQuietProbe();
        });
      });
    }

    if (siOn) armQuietProbe();

    final done = Completer<void>();
    const utf8 = Utf8Decoder(allowMalformed: true);

    // Pipe SSH output → xterm terminal; complete when shell closes
    final sessionLabel =
        '${session.host.label} (${session.host.username}@${session.host.host})';
    shell.stdout.cast<List<int>>().listen(
      (data) {
        var text = utf8.convert(data);
        if (hookBus != null) {
          text = hookBus!.fireTransform(
              'terminal.output', TransformEvent(sessionId: session.id, data: text));
        }

        if (siOn && gate == null && !injectionAborted) {
          firstOutputAt ??= DateTime.now();
          final sig = readiness.onChunk(text);
          if (sig == ReadinessSignal.altScreen) {
            injectionAborted = true; // vim/less owns the tty — never inject
            cancelReadinessTimers();
          } else if (readiness.bpOn) {
            // Line editor is reading: inject once the redraw burst settles.
            settleTimer?.cancel();
            settleTimer =
                Timer(const Duration(milliseconds: 250), launchInjection);
          } else {
            settleTimer?.cancel();
            if (awaitingProbe) {
              sinceProbe += text;
              if (!readiness.bpEver &&
                  InjectionReadiness.promptLikeTail(sinceProbe)) {
                // Probe answered with a prompt-looking tail (old bash).
                settleTimer =
                    Timer(const Duration(milliseconds: 250), launchInjection);
              }
            } else {
              armQuietProbe();
            }
          }
        }

        final g = gate;
        if (g != null) {
          final wasHolding = g.isHolding;
          final r = g.feed(text);
          if (r.sendPayload) {
            shell.write(Uint8List.fromList(
                shellIntegration!.buildPayloadLine().codeUnits));
          }
          if (r.emit == null) return; // withheld until DONE / timeout
          if (wasHolding && !g.isHolding) doneTimer?.cancel();
          text = r.emit!;
          if (text.isEmpty) return; // echo head discarded, nothing to show
        }
        session.terminal.write(text);
        _recording?.writeOutput(session.id, text);
        try {
          NotificationService.instance.onTerminalData(
            text,
            sessionId: session.id,
            sessionLabel: sessionLabel,
          );
        } catch (e) {
          // Notifications must never break TTY output — log and move on.
          debugPrint('[SshService] notification handler threw: $e');
        }
      },
      onDone: () {
        cancelReadinessTimers();
        doneTimer?.cancel();
        final g = gate;
        if (g != null && g.isHolding) {
          final out = g.flush();
          if (out.isNotEmpty) session.terminal.write(out);
        }
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
      // A user keystroke before the handshake starts cancels the injection:
      // a queued probe "\n" would execute their half-typed command, and the
      // bootstrap would be appended to whatever they are typing.
      if (siOn && gate == null && !injectionAborted) {
        injectionAborted = true;
        cancelReadinessTimers();
      }
      if (hookBus != null) {
        final result = hookBus!.fireInterceptable(
            'terminal.input', TransformEvent(sessionId: session.id, data: data));
        if (result == null) return; // cancelled by plugin
        shell.write(Uint8List.fromList(result.codeUnits));
      } else {
        shell.write(Uint8List.fromList(data.codeUnits));
      }
    };

    // Handle terminal resize
    session.terminal.onResize = (w, h, pw, ph) {
      shell.resizeTerminal(w, h);
    };

    // Wait until the remote shell actually closes
    await done.future;
  }

  void _onShellClosed(SshSession session) {
    hookBus?.fireObserve('session.disconnect',
        ObserveEvent(sessionId: session.id, payload: {}));
    _shells.remove(session.id);
    _shellToHost.remove(session.id);
    session.terminal.write('\r\n\x1b[31m[Connection closed]\x1b[0m\r\n');
    // Drop the closures that pin the closed shell — otherwise it lingers in
    // memory until the widget tree releases the terminal.
    session.terminal.onOutput = null;
    session.terminal.onResize = null;
    session.terminal.onPrivateOSC = null;
    shellIntegration?.clear(session.id);
    NotificationService.instance.removeSession(session.id);
    _recording?.onShellClosed(session.id);
  }

  /// Returns the open client for [host], reconnecting with stored
  /// credentials when there is none or the cached one is already dead.
  Future<SSHClient> ensureClient(Host host) => _ensureClient(host);

  Future<SSHClient> _ensureClient(Host host) async {
    final existing = _clients[host.id];
    if (existing != null && !existing.isClosed) return existing;
    if (existing != null) _clients.remove(host.id); // dropped link — evict
    final verifier = defaultHostKeyVerifier;
    if (verifier == null) {
      throw StateError(
        'Not connected to ${host.host}. Call connect() first, or wire '
        'SshService.defaultHostKeyVerifier to allow auto-connect.',
      );
    }
    final keyId = host.keyId;
    final keyEntry = keyId == null ? null : defaultKeyLookup?.call(keyId);
    return connect(
      host,
      keyEntry: keyEntry,
      verifyHostKey: (keyType, fp) => verifier(host.host, host.port, keyType, fp),
    );
  }

  // ── Exec ───────────────────────────────────────────────

  Future<({String stdout, String stderr, int exitCode})> exec(
    Host host,
    String command,
  ) async {
    var cmd = command;

    if (hookBus != null) {
      final transformed = hookBus!.fireInterceptable(
        'command.before',
        TransformEvent(sessionId: host.id, data: cmd),
      );
      if (transformed == null) {
        return (stdout: '', stderr: 'Command cancelled by plugin', exitCode: -1);
      }
      cmd = transformed;
    }

    final originalCommand = cmd;
    final client = await _ensureClient(host);
    final result = await client.runWithResult(cmd);
    final execResult = (
      stdout: String.fromCharCodes(result.stdout),
      stderr: String.fromCharCodes(result.stderr),
      exitCode: result.exitCode ?? -1,
    );

    hookBus?.fireObserve(
      'command.after',
      ObserveEvent(
        sessionId: host.id,
        payload: {
          'command': originalCommand,
          'stdout': execResult.stdout,
          'stderr': execResult.stderr,
          'exitCode': execResult.exitCode,
        },
      ),
    );

    return execResult;
  }

  // ── SFTP ───────────────────────────────────────────────

  Future<SftpClient> openSftp(Host host, {bool interactive = true}) async {
    final client = await _ensureClient(host);
    if (host.sftpMode == SftpMode.normal) return client.sftp();
    return _openElevatedSftp(client, host, interactive: interactive);
  }

  /// Elevated SFTP (sudo / custom command). Probe and validation execs talk
  /// to the SSHClient directly — they intentionally bypass the plugin
  /// HookBus, and the sudo password only ever travels via stdin.
  Future<SftpClient> _openElevatedSftp(
    SSHClient client,
    Host host, {
    required bool interactive,
  }) async {
    // Persisted only after the orchestrator confirms the password validated.
    String? validatedToPersist;
    final probeCommand = buildPathProbeCommand();
    final orchestrator = SudoSftpOrchestrator<SftpClient>(
      runExec: (cmd) async {
        // The sftp-server path is static for a host; cache the probe result so
        // every file op / transfer doesn't pay an extra round-trip for it.
        if (cmd == probeCommand) {
          final cached = _sudoServerPath[host.id];
          if (cached != null) {
            return (stdout: cached, stderr: '', exitCode: 0);
          }
        }
        try {
          final r = await client
              .runWithResult(cmd)
              .timeout(const Duration(seconds: 15));
          final out = utf8.decode(r.stdout, allowMalformed: true);
          final result = (
            stdout: out,
            stderr: utf8.decode(r.stderr, allowMalformed: true),
            exitCode: r.exitCode ?? -1,
          );
          if (cmd == probeCommand && result.exitCode == 0) {
            final p = out.trim();
            if (p.isNotEmpty) _sudoServerPath[host.id] = p;
          }
          return result;
        } on TimeoutException {
          throw SudoSftpException(SudoSftpFailureReason.handshakeFailed,
              detail: 'Timed out running: $cmd');
        }
      },
      runExecWithStdin: (cmd, stdinData) async {
        final session = await client.execute(cmd);
        final stderrBuf = StringBuffer();
        final stdoutDone = Completer<void>();
        final stderrDone = Completer<void>();
        session.stdout.listen((_) {},
            onDone: stdoutDone.complete,
            onError: (_) => stdoutDone.complete());
        session.stderr.cast<List<int>>().listen(
            (d) => stderrBuf.write(utf8.decode(d, allowMalformed: true)),
            onDone: stderrDone.complete,
            onError: (_) => stderrDone.complete());
        session.stdin.add(Uint8List.fromList(stdinData));
        await session.stdin.close(); // EOF: a wrong password fails fast
        try {
          await Future.wait(
                  [stdoutDone.future, stderrDone.future, session.done])
              .timeout(const Duration(seconds: 15));
        } on TimeoutException {
          session.close();
          throw SudoSftpException(SudoSftpFailureReason.handshakeFailed,
              detail:
                  'sudo validation timed out (check requiretty / PAM): $cmd');
        }
        return (stderr: stderrBuf.toString(), exitCode: session.exitCode ?? -1);
      },
      openSftpExec: (cmd, {stdinPreamble}) async {
        final sftp = await client.sftpOnExec(cmd, stdinPreamble: stdinPreamble);
        try {
          await sftp.handshake.timeout(const Duration(seconds: 15));
        } catch (_) {
          sftp.close();
          rethrow;
        }
        return sftp;
      },
    );
    final sftp = await orchestrator.openForHost(
      host,
      interactive: interactive,
      getPassword: ({required bool interactive, required int attempt}) async {
        final r = await _sudoPasswordFor(host,
            interactive: interactive, attempt: attempt);
        if (r == null) return null;
        // A prompted password with "remember" is only persisted below, after
        // openForHost confirms it validated — never speculatively.
        if (r.persist) validatedToPersist = r.password;
        return r.password;
      },
    );
    if (validatedToPersist != null) {
      try {
        await _storage.saveSudoPassword(host.id, validatedToPersist!);
      } catch (_) {
        // Keychain unavailable — the password still works for this session.
      }
    }
    return sftp;
  }

  /// Candidate chain: stored sudopw secret → login password (password auth)
  /// → interactive prompt. The explicitly-saved sudo password wins over the
  /// login-password heuristic. `persist` is true only for a prompted password
  /// the user asked to remember; the caller persists it after it validates.
  /// attempt 1 (wrong password) skips straight to the prompt so the bad stored
  /// candidate isn't reused.
  Future<({String password, bool persist})?> _sudoPasswordFor(
    Host host, {
    required bool interactive,
    required int attempt,
  }) async {
    if (attempt == 0) {
      final stored = await _storage.loadSudoPassword(host.id);
      if (stored != null && stored.isNotEmpty) {
        return (password: stored, persist: false);
      }
      if (host.authType == AuthType.password) {
        final pw = await _storage.loadPassword(host.id);
        if (pw != null && pw.isNotEmpty) return (password: pw, persist: false);
      }
    }
    if (!interactive) return null;
    final prompted = await sudoPasswordPrompt?.call(host);
    if (prompted == null) return null;
    return (password: prompted.password, persist: prompted.remember);
  }

  // Cached SFTP client per host, reused for path autocomplete listings.
  final Map<String, SftpClient> _completionSftp = {};

  // Cached sftp-server path per host (elevated SFTP), so each operation skips
  // re-probing. Cleared on disconnect.
  final Map<String, String> _sudoServerPath = {};

  /// List a remote directory for path autocomplete. Reuses a cached SFTP
  /// client per host. Returns entry names (directories carry a trailing '/').
  /// Never throws — returns an empty list on any failure and drops the cached
  /// client so a later call can reopen it (self-heals after reconnect).
  Future<List<String>> listDirectory(Host host, String path) async {
    try {
      final sftp =
          _completionSftp[host.id] ??= await openSftp(host, interactive: false);
      final items = await sftp.listdir(path.isEmpty ? '.' : path);
      return items
          .map((e) => e.filename + (e.attr.isDirectory ? '/' : ''))
          .where((n) => n != './' && n != '../')
          .toList();
    } catch (e) {
      _completionSftp.remove(host.id);
      debugPrint('[SshService] listDirectory failed for $path: $e');
      return const [];
    }
  }

  // ── Send input to shell ────────────────────────────────

  /// Sends [text] directly to the shell of [sessionId].
  ///
  /// Returns false when the session has no live shell (e.g. it closed
  /// mid-disconnect) so callers don't show success feedback for input that
  /// never reached the server.
  bool sendInput(String sessionId, String text) {
    final shell = _shells[sessionId];
    if (shell == null) return false;
    shell.write(Uint8List.fromList(text.codeUnits));
    return true;
  }

  // ── Disconnect ─────────────────────────────────────────

  void disconnect(String hostId) {
    final jumpHostId = _hostToJump.remove(hostId);

    final sessionIds = _shellToHost.entries
        .where((e) => e.value == hostId)
        .map((e) => e.key)
        .toList();
    for (final id in sessionIds) {
      _shells.remove(id);
      _shellToHost.remove(id);
      NotificationService.instance.removeSession(id);
      shellIntegration?.clear(id);
    }
    _clients[hostId]?.close();
    _clients.remove(hostId);
    // The SFTP completion client rides the SSHClient just closed; drop it so a
    // reconnect opens a fresh one instead of reusing the dead channel.
    _completionSftp.remove(hostId);
    _sudoServerPath.remove(hostId);
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
    _shellToHost.remove(sessionId);
    NotificationService.instance.removeSession(sessionId);
    shellIntegration?.clear(sessionId);
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
    } catch (e) {
      debugPrint('[SshService] OS detect failed for ${host.host}: $e');
      return null;
    }
  }
}

/// Return value of [_SshService._resolveIdentities]. The optional [agentProxy]
/// must stay open until SSH authentication completes — agent-backed identities
/// need the socket to sign challenges.
class _IdentityResolution {
  final List<SSHKeyPair> identities;
  final SystemAgentProxy? agentProxy;

  const _IdentityResolution(this.identities, [this.agentProxy]);
}
