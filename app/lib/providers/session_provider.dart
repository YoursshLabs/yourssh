import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/host.dart';
import '../models/ssh_key.dart';
import '../models/ssh_session.dart';
import '../services/ssh_service.dart';

class SessionProvider extends ChangeNotifier {
  final SshService _ssh;
  final List<SshSession> _sessions = [];
  String? _activeSessionId;
  SshKeyEntry? Function(String keyId)? keyLookup;
  bool Function()? autoReconnectEnabled;
  int Function()? reconnectAttempts;
  bool Function()? tmuxEnabled;
  Future<bool> Function(String host, int port, String keyType, Uint8List fp)? hostKeyVerifier;
  Future<void> Function(String hostId, String os)? onOsDetected;

  SessionProvider(this._ssh);

  List<SshSession> get sessions => _sessions;

  SshSession? get activeSession => _sessions.isEmpty
      ? null
      : _sessions.firstWhere(
          (s) => s.id == _activeSessionId,
          orElse: () => _sessions.last,
        );

  void setActive(String sessionId) {
    _activeSessionId = sessionId;
    notifyListeners();
  }

  Future<void> connect(Host host) async {
    final session = SshSession(host: host);
    _sessions.add(session);
    _activeSessionId = session.id;
    notifyListeners();

    await _doConnect(session, host, attempt: 1);
  }

  Future<void> _doConnect(SshSession session, Host host, {required int attempt}) async {
    final maxAttempts = reconnectAttempts?.call() ?? 3;
    try {
      final keyEntry = host.keyId != null ? keyLookup?.call(host.keyId!) : null;
      await _ssh.connect(
        host,
        keyEntry: keyEntry,
        verifyHostKey: hostKeyVerifier != null
            ? (keyType, fp) => hostKeyVerifier!(host.host, host.port, keyType, fp)
            : null,
      );
      session.status = SessionStatus.connected;
      // Fire-and-forget: only detect if OS not yet known
      if (host.detectedOs == null) {
        _ssh.detectOs(host).then((os) {
          if (os != null) onOsDetected?.call(host.id, os);
        });
      }
      session.errorMessage = null;
      notifyListeners();

      await _ssh.openShell(session, useTmux: tmuxEnabled?.call() ?? false);
      notifyListeners();

      // Shell closed — try auto-reconnect
      if (_sessions.contains(session) && (autoReconnectEnabled?.call() ?? false)) {
        _scheduleReconnect(session, host, attempt: 1);
      } else if (_sessions.contains(session)) {
        session.status = SessionStatus.disconnected;
        notifyListeners();
      }
    } catch (e) {
      if (!_sessions.contains(session)) return;
      final shouldRetry = (autoReconnectEnabled?.call() ?? false) && attempt < maxAttempts;
      if (shouldRetry) {
        _scheduleReconnect(session, host, attempt: attempt + 1);
      } else {
        session.status = SessionStatus.error;
        session.errorMessage = attempt > 1
            ? 'Failed after $attempt attempts: $e'
            : e.toString();
        notifyListeners();
      }
    }
  }

  void _scheduleReconnect(SshSession session, Host host, {required int attempt}) {
    session.status = SessionStatus.connecting;
    final msg = attempt > 1 ? 'Reconnecting (attempt $attempt)…' : 'Reconnecting…';
    session.terminal.write('\r\n\x1b[33m[$msg]\x1b[0m\r\n');
    notifyListeners();

    Timer(Duration(seconds: attempt * 2), () {
      if (_sessions.contains(session)) {
        _doConnect(session, host, attempt: attempt);
      }
    });
  }

  void closeSession(String sessionId) {
    _ssh.disconnectSession(sessionId);
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.last.id : null;
    }
    notifyListeners();
  }

  void closeActive() {
    final active = activeSession;
    if (active != null) closeSession(active.id);
  }

  void activateNext() {
    if (_sessions.isEmpty) return;
    final idx = _sessions.indexWhere((s) => s.id == _activeSessionId);
    final nextIdx = (idx + 1) % _sessions.length;
    _activeSessionId = _sessions[nextIdx].id;
    notifyListeners();
  }

  void activatePrev() {
    if (_sessions.isEmpty) return;
    final idx = _sessions.indexWhere((s) => s.id == _activeSessionId);
    final prevIdx = (idx - 1 + _sessions.length) % _sessions.length;
    _activeSessionId = _sessions[prevIdx].id;
    notifyListeners();
  }
}
