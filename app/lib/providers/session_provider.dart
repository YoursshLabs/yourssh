import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/host.dart';
import '../models/ssh_key.dart';
import '../models/ssh_session.dart';
import '../services/ssh_service.dart';
import '../services/tab_metadata_service.dart';

class SessionProvider extends ChangeNotifier {
  final SshService _ssh;
  final TabMetadataService _tabMetadata;
  final List<SshSession> _sessions = [];
  final Map<String, Timer> _reconnectTimers = {};
  final Map<String, Timer> _countdownTimers = {};
  String? _activeSessionId;
  bool _disposed = false;
  SshKeyEntry? Function(String keyId)? keyLookup;
  Host? Function(String jumpHostId)? jumpHostLookup;
  bool Function()? autoReconnectEnabled;
  int Function()? reconnectAttempts;
  bool Function()? tmuxEnabled;
  Future<bool> Function(String host, int port, String keyType, Uint8List fp)? hostKeyVerifier;
  Future<void> Function(String hostId, String os)? onOsDetected;
  Future<void> Function(SshSession session)? recordingStart;

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

  List<SshSession> get sessions => _sessions;

  Host? hostForSession(String sessionId) =>
      _sessions.where((s) => s.id == sessionId).firstOrNull?.host;

  SshSession? get activeSession => _sessions.isEmpty
      ? null
      : _sessions.firstWhere(
          (s) => s.id == _activeSessionId,
          orElse: () => _sessions.last,
        );

  void setActive(String sessionId) {
    _activeSessionId = sessionId;
    _safeNotify();
  }

  Future<void> connect(Host host, {String? initialCommand}) async {
    final session = SshSession(host: host, initialCommand: initialCommand);
    _sessions.add(session);
    _activeSessionId = session.id;
    _safeNotify();

    // Load persisted tab metadata (label, color, pin) for this host.
    final meta = await _tabMetadata.loadMetadata(host.id);
    // The user may have closed the tab during the async load — don't mutate,
    // sort, or connect a session that's no longer tracked.
    if (!_sessions.contains(session)) return;
    if (meta != null) {
      session.customLabel = meta['label'] as String?;
      session.colorTag = meta['color'] as String?;
      session.isPinned = (meta['pinned'] as bool?) ?? false;
      if (session.isPinned) _sortSessions();
      _safeNotify();
    }

    await _doConnect(session, host, attempt: 1);
  }

  Future<void> _doConnect(SshSession session, Host host, {required int attempt}) async {
    try {
      final keyEntry = host.keyId != null ? keyLookup?.call(host.keyId!) : null;
      Host? jumpHost;
      SshKeyEntry? jumpKeyEntry;
      if (host.jumpHostId != null) {
        jumpHost = jumpHostLookup?.call(host.jumpHostId!);
        if (jumpHost != null && jumpHost.keyId != null) {
          jumpKeyEntry = keyLookup?.call(jumpHost.keyId!);
        }
      }
      await _ssh.connect(
        host,
        keyEntry: keyEntry,
        jumpHost: jumpHost,
        jumpKeyEntry: jumpKeyEntry,
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
      _safeNotify();

      if (host.autoRecord) {
        unawaited(recordingStart?.call(session) ?? Future.value());
      }

      await _ssh.openShell(session, useTmux: tmuxEnabled?.call() ?? false);
      _safeNotify();

      // Shell closed — try auto-reconnect
      if (_sessions.contains(session) && (autoReconnectEnabled?.call() ?? false)) {
        _scheduleReconnect(session, host, attempt: 1);
      } else if (_sessions.contains(session)) {
        session.status = SessionStatus.disconnected;
        _safeNotify();
      }
    } catch (e) {
      if (!_sessions.contains(session)) return;
      final maxAttempts = reconnectAttempts?.call() ?? 0;
      final isUnlimited = maxAttempts == 0;
      final shouldRetry = (autoReconnectEnabled?.call() ?? false) &&
          (isUnlimited || attempt < maxAttempts);
      if (shouldRetry) {
        _scheduleReconnect(session, host, attempt: attempt + 1);
      } else {
        session.status = SessionStatus.error;
        session.errorMessage = attempt > 1
            ? 'Failed after $attempt attempts: $e'
            : e.toString();
        _safeNotify();
      }
    }
  }

  void _scheduleReconnect(SshSession session, Host host, {required int attempt}) {
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

  void closeSession(String sessionId) {
    _reconnectTimers.remove(sessionId)?.cancel();
    _countdownTimers.remove(sessionId)?.cancel();
    final hostId = _sessions.where((s) => s.id == sessionId).firstOrNull?.host.id;

    _ssh.disconnectSession(sessionId);
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.isNotEmpty ? _sessions.last.id : null;
    }

    // If no more sessions for this host remain, tear down the SSH client and jump client.
    if (hostId != null && !_sessions.any((s) => s.host.id == hostId)) {
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
    _sessions.removeWhere((s) => s.id == sessionId && s.isWatch);
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

  SshSession? _sessionById(String id) =>
      _sessions.where((s) => s.id == id).firstOrNull;

  /// Persists a session's tab metadata and mirrors it onto any other live
  /// tabs of the same host. Tab metadata is keyed per host, so all tabs of a
  /// host share one label/color/pin — keeping the live sessions in sync avoids
  /// them silently diverging and then stomping each other's persisted record.
  void _persistTabMetadata(SshSession session) {
    _tabMetadata.saveMetadata(session.host.id,
        label: session.customLabel,
        color: session.colorTag,
        pinned: session.isPinned);
    for (final s in _sessions) {
      if (!identical(s, session) && s.host.id == session.host.id) {
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
