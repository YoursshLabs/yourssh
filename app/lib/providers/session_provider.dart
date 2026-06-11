import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:yourssh_rdp/yourssh_rdp.dart';
import '../models/agent_forwarding_state.dart';
import '../models/audit_event.dart';
import '../models/host.dart';
import '../models/local_session.dart';
import '../models/rdp_session.dart';
import '../models/shell_profile.dart';
import '../models/ssh_key.dart';
import '../models/ssh_session.dart';
import '../models/app_session.dart';
import '../models/terminal_session.dart';
import '../services/audit_service.dart';
import '../services/local_shell_service.dart';
import '../services/rdp_tunnel_proxy.dart';
import '../services/ssh_service.dart';
import '../services/tab_metadata_service.dart';

class SessionProvider extends ChangeNotifier {
  final SshService _ssh;
  final TabMetadataService _tabMetadata;
  final List<AppSession> _sessions = [];
  final Map<String, Timer> _reconnectTimers = {};
  final Map<String, Timer> _countdownTimers = {};
  String? _activeSessionId;
  bool _disposed = false;
  SshKeyEntry? Function(String keyId)? keyLookup;
  Host? Function(String jumpHostId)? jumpHostLookup;
  bool Function()? autoReconnectEnabled;
  int Function()? reconnectAttempts;
  bool Function()? tmuxEnabled;
  String Function()? terminalType;
  Future<bool> Function(String host, int port, String keyType, Uint8List fp)? hostKeyVerifier;
  Future<void> Function(String hostId, String os)? onOsDetected;
  Future<void> Function(SshSession session)? recordingStart;

  /// Audit trail sink; null disables auditing.
  AuditService? audit;

  /// Returns the current RDP workspace size (logical pixels); wired in
  /// main.dart once the workspace widget has a measured size. Null falls back
  /// to 1280×800.
  Size Function()? rdpDesktopSize;

  /// RDP server certificate verifier; called with the SHA-256 fingerprint when
  /// a Connected event arrives. Returns true to proceed, false to reject and
  /// disconnect. Wired in main.dart to [KnownHostsProvider.challengeRdpCert].
  /// Null auto-trusts (dev/test fallback).
  Future<bool> Function(String host, int port, String fingerprint)? rdpCertVerifier;

  /// Returns the pinned RDP cert fingerprint for host:port, or null when not
  /// pinned. Passed to the Rust engine so a pin mismatch aborts the
  /// connection BEFORE any credentials are sent.
  String? Function(String host, int port)? rdpPinLookup;

  /// Fired when the server cert no longer matches the pin (connection was
  /// aborted pre-auth). Returns true when the user re-trusts the new cert —
  /// the session then reconnects automatically.
  Future<bool> Function(String host, int port, String fingerprint)?
      rdpCertMismatchHandler;

  /// Fired when a session drops without a pending auto-reconnect: shell
  /// closed (a graceful `exit` is indistinguishable here — see spec caveat)
  /// or reconnect attempts exhausted. Wired in main.dart to the
  /// notification center. Receives SSH and RDP sessions alike.
  void Function(AppSession session, String? reason)? onSessionDropped;

  /// Resolves the Settings default shell for new local terminals; wired by
  /// main.dart to SettingsProvider.resolveDefaultShell. Null (tests, early
  /// boot) behaves as platform default.
  ShellResolution Function()? defaultShellResolver;

  /// Set by main.dart; required for newLocalSession/restartLocalSession.
  /// The setter wires the service's out-of-band state changes (PTY exit,
  /// spawn failure) into this provider's notify, so panes rebuild into the
  /// "Shell exited / Restart shell" view without an unrelated trigger.
  LocalShellService? get localShell => _localShell;
  LocalShellService? _localShell;
  set localShell(LocalShellService? service) {
    _localShell = service;
    service?.onSessionStateChanged = _safeNotify;
  }

  SessionProvider(this._ssh, this._tabMetadata);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final t in _reconnectTimers.values) {
      t.cancel();
    }
    _reconnectTimers.clear();
    for (final t in _countdownTimers.values) {
      t.cancel();
    }
    _countdownTimers.clear();
    super.dispose();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  List<AppSession> get sessions => _sessions;

  /// SSH-only consumers (plugin context, devops tools, sync, workspace save).
  List<SshSession> get sshSessions =>
      _sessions.whereType<SshSession>().toList();

  Host? hostForSession(String sessionId) {
    final session = _sessionById(sessionId);
    return switch (session) {
      SshSession s => s.host,
      RdpSession s => s.host,
      _ => null,
    };
  }

  AppSession? get activeSession => _sessions.isEmpty
      ? null
      : _sessions.firstWhere(
          (s) => s.id == _activeSessionId,
          orElse: () => _sessions.last,
        );

  /// The active session when it is SSH, else the most recent SSH session.
  /// Used by screens that need *an* SSH target (devops tools, MCP, share).
  SshSession? get activeSshSession {
    final active = activeSession;
    if (active is SshSession) return active;
    return sshSessions.lastOrNull;
  }

  void setActive(String sessionId) {
    if (_activeSessionId == sessionId) return; // re-clicking the active tab
    _activeSessionId = sessionId;
    _safeNotify();
  }

  Future<void> connect(Host host, {String? initialCommand}) async {
    final session = SshSession(host: host, initialCommand: initialCommand);
    _sessions.add(session);
    _activeSessionId = session.id;
    _safeNotify();

    // Load persisted tab metadata (label, color, pin) for this host.
    // The user may have closed the tab during the async load — don't mutate,
    // sort, or connect a session that's no longer tracked.
    final applied = await _applyTabMetadata(session, host.id);
    if (!_sessions.contains(session)) return;
    if (applied) {
      if (session.isPinned) _sortSessions();
      _safeNotify();
    }

    await _doConnect(session, host, attempt: 1);
  }

  /// Loads persisted tab metadata (label, color, pin) for [hostId] onto
  /// [session]. Returns true when a record existed. Shared by the SSH and
  /// RDP connect paths so the load logic can't drift between them.
  Future<bool> _applyTabMetadata(AppSession session, String hostId) async {
    final meta = await _tabMetadata.loadMetadata(hostId);
    if (meta == null) return false;
    session.customLabel = meta['label'] as String?;
    session.colorTag = meta['color'] as String?;
    session.isPinned = (meta['pinned'] as bool?) ?? false;
    return true;
  }

  /// Routes to [connectRdp] or [connect] based on [host.protocol].
  Future<AppSession?> connectAny(Host host, {String? initialCommand}) {
    if (host.protocol == HostProtocol.rdp) return connectRdp(host);
    return connect(host, initialCommand: initialCommand).then((_) => null);
  }

  Future<RdpSession?> connectRdp(Host host) async {
    final password = await _ssh.loadPassword(host.id) ?? '';
    final size = rdpDesktopSize?.call() ?? const Size(1280, 800);

    var targetHost = host.host;
    var targetPort = host.port;
    RdpTunnelProxy? proxy;
    RdpSession? session;
    String? setupError;

    try {
      // Lazy bridge init: loads the native library on the first RDP connect.
      // A failure (missing/corrupt dylib) surfaces as an error tab instead of
      // an uncatchable LateInitializationError inside the generated bindings.
      await RdpClient.ensureInitialized();

      if (host.jumpHostId != null) {
        proxy = RdpTunnelProxy(onClosed: () => session?.markTunnelClosed());
        final port = await proxy.start(() async {
          final sshSocket = await _ssh.openTunnelSocket(
              host.jumpHostId!, host.host, host.port, host.id);
          return TunnelEnd(
              stream: sshSocket.stream,
              sink: sshSocket.sink,
              close: sshSocket.destroy);
        });
        targetHost = '127.0.0.1';
        targetPort = port;
      }
    } catch (e) {
      setupError = '$e';
    }

    final config = RdpConfig(
      targetHost: targetHost,
      targetPort: targetPort,
      username: host.username,
      password: password,
      domain: host.domain,
      width: size.width.round().clamp(800, 7680),
      height: size.height.round().clamp(600, 4320),
      security: host.rdpSecurity.name,
      // With a pinned cert the Rust engine verifies it post-TLS, pre-CredSSP:
      // a mismatch aborts before any credentials are transmitted.
      expectedFingerprint: rdpPinLookup?.call(host.host, host.port),
    );
    final client = RdpClient(config);
    session = RdpSession(
        host: host,
        client: client,
        width: config.width,
        height: config.height,
        tunnelProxy: proxy);
    session.onRemoteClipboardText =
        (t) => Clipboard.setData(ClipboardData(text: t));
    final verifier = rdpCertVerifier;
    if (verifier != null) {
      session.certCheckCallback =
          (fp) => verifier(host.host, host.port, fp);
    }
    final mismatchHandler = rdpCertMismatchHandler;
    if (mismatchHandler != null) {
      final s = session;
      session.onCertMismatch = (fp) {
        unawaited(mismatchHandler(host.host, host.port, fp).then((trusted) {
          if (trusted && _sessions.contains(s)) {
            unawaited(reconnectRdp(s));
          }
        }));
      };
    }

    await _applyTabMetadata(session, host.id);

    if (setupError != null) {
      session.status = RdpSessionStatus.error;
      session.lastMessage = setupError;
    } else {
      session.attach(client.events);
      // Failures surface through the event stream (status/lastMessage);
      // swallow the future's mirror error so it can't hit the root zone.
      unawaited(client.connect().then((_) {}, onError: (_) {}));
    }

    _watchRdpStatus(session);
    session.addListener(_safeNotify);
    _sessions.add(session);
    _activeSessionId = session.id;
    if (session.isPinned) _sortSessions();
    _safeNotify();
    return session;
  }

  /// Audits RDP connect/disconnect transitions and feeds the notification
  /// bell — parity with the SSH paths in [_doConnect]/[closeSession].
  void _watchRdpStatus(RdpSession session) {
    var last = session.status;
    session.addListener(() {
      final now = session.status;
      if (now == last) return;
      final was = last;
      last = now;
      final host = session.host;
      if (was == RdpSessionStatus.connecting &&
          now == RdpSessionStatus.connected) {
        audit?.record(AuditEvent.now(
            type: AuditEventType.connect,
            host: host,
            sessionId: session.id,
            meta: const {'source': 'rdp'}));
      } else if (was == RdpSessionStatus.connecting &&
          (now == RdpSessionStatus.error ||
              now == RdpSessionStatus.disconnected)) {
        audit?.record(AuditEvent.now(
            type: AuditEventType.connect,
            host: host,
            sessionId: session.id,
            meta: {
              'source': 'rdp',
              'error': session.lastMessage ?? 'connection failed',
            }));
        // Cert flows (mismatch abort, user rejection) have their own dialogs;
        // a bell entry on top would be noise.
        final msg = (session.lastMessage ?? '').toLowerCase();
        if (!msg.contains('certificate')) {
          onSessionDropped?.call(session, session.lastMessage);
        }
      } else if (was == RdpSessionStatus.connected) {
        final userClosed = session.lastMessage == 'disconnected by user';
        audit?.record(AuditEvent.now(
            type: AuditEventType.disconnect,
            host: host,
            sessionId: session.id,
            meta: {
              'source': 'rdp',
              'reason': userClosed ? 'user-closed' : 'dropped',
            }));
        if (!userClosed) {
          onSessionDropped?.call(session, session.lastMessage);
        }
      }
    });
  }

  Future<void> reconnectRdp(RdpSession old) async {
    // Label/color/pin are persisted on every edit and reloaded by connectRdp's
    // tab-metadata pass — no manual carry-over needed.
    closeSession(old.id);
    await connectRdp(old.host);
  }

  Future<void> _doConnect(SshSession session, Host host, {required int attempt}) async {
    try {
      final keyEntry = host.keyId != null ? keyLookup?.call(host.keyId!) : null;
      final jumpChain = SshService.resolveJumpChain(
        host,
        jumpLookup: (id) => jumpHostLookup?.call(id),
        keyLookup: (id) => keyLookup?.call(id),
      );
      await _ssh.connect(
        host,
        keyEntry: keyEntry,
        jumpChain: jumpChain,
        verifyHostKey: hostKeyVerifier != null
            ? (keyType, fp) => hostKeyVerifier!(host.host, host.port, keyType, fp)
            : null,
        verifyHopHostKey: hostKeyVerifier != null
            ? (hop, keyType, fp) =>
                hostKeyVerifier!(hop.host, hop.port, keyType, fp)
            : null,
      );
      session.status = SessionStatus.connected;
      audit?.record(AuditEvent.now(
          type: AuditEventType.connect, host: host, sessionId: session.id));
      // Fire-and-forget: detect when OS is unknown, or known only as generic
      // 'linux' (pre-distro-detection hosts upgrade to a distro id on the
      // next connect; genuinely unknown distros re-probe — one cheap exec).
      if (host.detectedOs == null || host.detectedOs == 'linux') {
        _ssh.detectOs(host).then((os) {
          if (os != null) onOsDetected?.call(host.id, os);
        });
      }
      session.errorMessage = null;
      _safeNotify();

      if (host.autoRecord) {
        unawaited(recordingStart?.call(session) ?? Future.value());
      }

      await _ssh.openShell(
        session,
        useTmux: host.tmuxOverride ?? tmuxEnabled?.call() ?? false,
        termType: host.termType ?? terminalType?.call() ?? 'xterm-256color',
      );
      _safeNotify();

      // Shell closed — try auto-reconnect
      if (_sessions.contains(session) && (autoReconnectEnabled?.call() ?? false)) {
        // Paired logging: a flapping host must show its disconnects, not an
        // unexplained run of connect rows.
        audit?.record(AuditEvent.now(
            type: AuditEventType.disconnect,
            host: host,
            sessionId: session.id,
            meta: const {'reason': 'dropped', 'reconnecting': true}));
        _scheduleReconnect(session, host, attempt: 1);
      } else if (_sessions.contains(session)) {
        session.status = SessionStatus.disconnected;
        audit?.record(AuditEvent.now(
            type: AuditEventType.disconnect,
            host: host,
            sessionId: session.id,
            meta: const {'reason': 'dropped'}));
        onSessionDropped?.call(session, null);
        _safeNotify();
      }
    } catch (e) {
      if (!_sessions.contains(session)) return;
      final maxAttempts = reconnectAttempts?.call() ?? 0;
      final isUnlimited = maxAttempts == 0;
      // A jump-chain config error (deleted bastion, cycle) can never succeed
      // on retry — don't loop on it, surface it immediately.
      final isConfigError = e is JumpChainException;
      final shouldRetry = !isConfigError &&
          (autoReconnectEnabled?.call() ?? false) &&
          (isUnlimited || attempt < maxAttempts);
      if (shouldRetry) {
        _scheduleReconnect(session, host, attempt: attempt + 1);
      } else {
        session.status = SessionStatus.error;
        session.errorMessage = attempt > 1
            ? 'Failed after $attempt attempts: $e'
            : e.toString();
        // Final failure only — an unlimited-retry outage must not write
        // one audit row per attempt tick.
        audit?.record(AuditEvent.now(
          type: AuditEventType.connect,
          host: host,
          sessionId: session.id,
          meta: {'error': '$e', 'attempts': attempt},
        ));
        onSessionDropped?.call(session, session.errorMessage);
        _safeNotify();
      }
    }
  }

  void _scheduleReconnect(SshSession session, Host host, {required int attempt}) {
    session.reconnectCount++;
    final delay = (attempt * 2).clamp(2, 60);
    session.status = SessionStatus.connecting;
    _safeNotify();

    _startCountdown(session, delay, attempt);

    _reconnectTimers[session.id]?.cancel();
    _reconnectTimers[session.id] = Timer(Duration(seconds: delay), () {
      _reconnectTimers.remove(session.id);
      if (_disposed || !_sessions.contains(session)) return;
      _doConnect(session, host, attempt: attempt);
    });
  }

  void _startCountdown(SshSession session, int totalSeconds, int attempt) {
    _countdownTimers[session.id]?.cancel();
    var remaining = totalSeconds;

    session.terminal.write(
      '\r\n\x1b[33m[Reconnecting in ${remaining}s... (attempt $attempt)]\x1b[0m',
    );

    _countdownTimers[session.id] = Timer.periodic(const Duration(seconds: 1), (t) {
      remaining--;
      if (!_sessions.contains(session)) {
        t.cancel();
        _countdownTimers.remove(session.id);
        return;
      }
      if (remaining <= 0) {
        t.cancel();
        _countdownTimers.remove(session.id);
        session.terminal.write(
          '\r\x1b[2K\x1b[33m[Reconnecting now... (attempt $attempt)]\x1b[0m\r\n',
        );
      } else {
        session.terminal.write(
          '\r\x1b[2K\x1b[33m[Reconnecting in ${remaining}s... (attempt $attempt)]\x1b[0m',
        );
      }
    });
  }

  Future<void> newLocalSession({
    ShellProfile? profile,
    bool platformDefault = false,
  }) async {
    final shell = localShell;
    if (shell == null) return;
    var chosen = profile;
    var dangling = false;
    if (chosen == null && !platformDefault) {
      final res = defaultShellResolver?.call();
      chosen = res?.profile;
      dangling = res?.dangling ?? false;
    }
    final session = await shell.openShell(profile: chosen);
    if (dangling) {
      session.terminal.write(
          '\x1b[33m[Default shell not found — using platform default. '
          'Check Settings → Terminal.]\x1b[0m\r\n');
    }
    _sessions.add(session);
    _activeSessionId = session.id;
    _safeNotify();
  }

  Future<void> restartLocalSession(String sessionId) async {
    final session = _sessionById(sessionId);
    if (session is! LocalSession) return;
    await localShell?.restartShell(session);
    _safeNotify();
  }

  void closeSession(String sessionId) {
    final session = _sessions.where((s) => s.id == sessionId).firstOrNull;
    if (session is RdpSession) {
      final hostId = session.host.id;
      // Mirror the SSH path: a live tab the user closes gets its own row
      // (a dead tab was already audited on the drop/error transition).
      if (session.status == RdpSessionStatus.connected) {
        audit?.record(AuditEvent.now(
            type: AuditEventType.disconnect,
            host: session.host,
            sessionId: sessionId,
            meta: const {'source': 'rdp', 'reason': 'user-closed'}));
      }
      session.removeListener(_safeNotify);
      unawaited(session.close());
      _sessions.remove(session);
      if (_activeSessionId == sessionId) {
        _activeSessionId = _sessions.isNotEmpty ? _sessions.last.id : null;
      }
      // Last session for this host gone — release the SSH tunnel client
      // (jump-chain refcount) that openTunnelSocket registered. No-op for
      // direct (untunneled) RDP hosts.
      if (!_sessions.any((s) => s is RdpSession && s.host.id == hostId)) {
        _ssh.disconnect(hostId);
      }
      _safeNotify();
      return;
    }
    if (session is LocalSession) {
      localShell?.closeSession(sessionId);
      _sessions.remove(session);
      if (_activeSessionId == sessionId) {
        _activeSessionId = _sessions.isNotEmpty ? _sessions.last.id : null;
      }
      _safeNotify();
      return;
    }

    _reconnectTimers.remove(sessionId)?.cancel();
    _countdownTimers.remove(sessionId)?.cancel();
    final ssh = sshSessions.where((s) => s.id == sessionId).firstOrNull;
    final hostId = ssh?.host.id;
    // Only a LIVE session gets a user-closed row — a dead tab already had
    // its disconnect recorded on the drop/error path (no double-counting).
    if (ssh != null && ssh.status == SessionStatus.connected) {
      audit?.record(AuditEvent.now(
          type: AuditEventType.disconnect,
          host: ssh.host,
          sessionId: sessionId,
          meta: const {'reason': 'user-closed'}));
    }

    _ssh.disconnectSession(sessionId);
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.last.id : null;
    }

    // If no more sessions for this host remain, tear down the SSH client and jump client.
    if (hostId != null && !sshSessions.any((s) => s.host.id == hostId)) {
      _ssh.disconnect(hostId);
    }

    _safeNotify();
  }

  void closeActive() {
    final active = activeSession;
    if (active != null) closeSession(active.id);
  }

  void addWatchSession(SshSession session) {
    _sessions.add(session);
    _activeSessionId = session.id;
    _safeNotify();
  }

  void removeWatchSession(String sessionId) {
    _sessions.removeWhere(
        (s) => s.id == sessionId && s is SshSession && s.isWatch);
    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.last.id : null;
    }
    _safeNotify();
  }

  void activateNext() {
    if (_sessions.isEmpty) return;
    final idx = _sessions.indexWhere((s) => s.id == _activeSessionId);
    final nextIdx = (idx + 1) % _sessions.length;
    _activeSessionId = _sessions[nextIdx].id;
    _safeNotify();
  }

  void activatePrev() {
    if (_sessions.isEmpty) return;
    final idx = _sessions.indexWhere((s) => s.id == _activeSessionId);
    final prevIdx = (idx - 1 + _sessions.length) % _sessions.length;
    _activeSessionId = _sessions[prevIdx].id;
    _safeNotify();
  }

  AppSession? _sessionById(String id) =>
      _sessions.where((s) => s.id == id).firstOrNull;

  /// Host id used as the tab-metadata key, or null for sessions whose
  /// metadata is not persisted (local shells, watch sessions).
  String? _metadataHostId(AppSession s) => switch (s) {
        SshSession ssh => ssh.isWatch ? null : ssh.host.id,
        RdpSession rdp => rdp.host.id,
        _ => null,
      };

  /// Persists a session's tab metadata and mirrors it onto any other live
  /// tabs of the same host. Tab metadata is keyed per host, so all tabs of a
  /// host share one label/color/pin — keeping the live sessions in sync avoids
  /// them silently diverging and then stomping each other's persisted record.
  void _persistTabMetadata(AppSession session) {
    final hostId = _metadataHostId(session);
    if (hostId == null) return;
    _tabMetadata.saveMetadata(hostId,
        label: session.customLabel,
        color: session.colorTag,
        pinned: session.isPinned);
    for (final s in _sessions) {
      if (!identical(s, session) && _metadataHostId(s) == hostId) {
        s.customLabel = session.customLabel;
        s.colorTag = session.colorTag;
        s.isPinned = session.isPinned;
      }
    }
  }

  void renameSession(String sessionId, String? label) {
    final session = _sessionById(sessionId);
    if (session == null) return;
    session.customLabel = label;
    _persistTabMetadata(session);
    _safeNotify();
  }

  void setSessionColor(String sessionId, String? colorHex) {
    final session = _sessionById(sessionId);
    if (session == null) return;
    session.colorTag = colorHex;
    _persistTabMetadata(session);
    _safeNotify();
  }

  /// Routes agent-forwarding events from SshService into session state.
  /// [sessionId] == null targets every session on [hostId] (served requests
  /// go through the client-wide handler); host-scoped events never overwrite
  /// a per-shell [AgentForwardingState.refused] — only a session-scoped event
  /// (e.g. a reconnect firing [AgentForwardingState.ready]) can reset it.
  void handleAgentForwardingEvent(
      String hostId, String? sessionId, AgentForwardingState state) {
    var changed = false;
    for (final s in sshSessions) {
      // Watch sessions carry a synthetic host id that never matches a real
      // one; skip them explicitly so that invariant isn't load-bearing here.
      if (s.isWatch) continue;
      final match =
          sessionId != null ? s.id == sessionId : s.host.id == hostId;
      if (!match) continue;
      if (sessionId == null &&
          s.agentForwardingState == AgentForwardingState.refused) {
        continue;
      }
      if (s.agentForwardingState != state) {
        s.agentForwardingState = state;
        changed = true;
      }
    }
    if (changed) _safeNotify();
  }

  void togglePin(String sessionId) {
    final session = _sessionById(sessionId);
    if (session == null) return;
    session.isPinned = !session.isPinned;
    _persistTabMetadata(session);
    _sortSessions();
    _safeNotify();
  }

  /// Used by [ReorderableListView.onReorderItem] — index is already adjusted.
  void reorderSessionItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _sessions.length) return;
    final session = _sessions[oldIndex];
    final pinnedCount = _sessions.where((s) => s.isPinned).length;
    if (session.isPinned) {
      newIndex = newIndex.clamp(0, (pinnedCount - 1).clamp(0, _sessions.length - 1));
    } else {
      newIndex = newIndex.clamp(pinnedCount, _sessions.length - 1);
    }
    // No movement — return without a spurious rebuild.
    if (newIndex == oldIndex) return;
    _sessions.removeAt(oldIndex);
    _sessions.insert(newIndex, session);
    _safeNotify();
  }

  void _sortSessions() {
    final pinned = _sessions.where((s) => s.isPinned).toList();
    final unpinned = _sessions.where((s) => !s.isPinned).toList();
    _sessions
      ..clear()
      ..addAll(pinned)
      ..addAll(unpinned);
  }
}
