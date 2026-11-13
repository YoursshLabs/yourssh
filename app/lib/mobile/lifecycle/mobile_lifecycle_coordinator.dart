import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/port_forward.dart';
import '../../providers/port_forward_provider.dart';
import '../../providers/session_provider.dart';
import '../../services/port_forward_service.dart';
import 'background_tasks.dart';

/// iOS suspends the app soon after it leaves the foreground and kills its
/// sockets. This keeps a short, deliberate grace window (a quick app switch
/// changes nothing), then closes everything cleanly — port forwards first so
/// their reconnect backoff never starts — and reconnects on return.
///
/// `inactive` (Face ID sheet, Control Center) is never acted on: only the
/// paused/resumed lifecycle states call [onBackground]/[onForeground].
class MobileLifecycleCoordinator {
  MobileLifecycleCoordinator({
    required this.sessions,
    required this.forwards,
    required this.forwardRules,
    required this.tasks,
    this.stagger = const Duration(milliseconds: 300),
    this.maxGrace = const Duration(seconds: 25),
  });

  final SessionProvider sessions;
  final PortForwardService forwards;
  final PortForwardProvider forwardRules;
  final BackgroundTasks tasks;
  final Duration stagger;
  final Duration maxGrace;

  /// The OS keeps part of its allowance for its own expiration handling.
  static const _osMargin = Duration(seconds: 5);

  Timer? _graceTimer;
  BackgroundLease? _lease;
  List<PortForward> _stoppedForwards = const [];
  bool _background = false;
  bool _disposed = false;

  Duration _graceFor(BackgroundLease? lease) {
    if (lease == null) return Duration.zero;
    final remaining = lease.remaining;
    final byOs = remaining == null ? maxGrace : remaining - _osMargin;
    final grace = byOs < maxGrace ? byOs : maxGrace;
    return grace.isNegative ? Duration.zero : grace;
  }

  Future<void> onBackground() async {
    if (_disposed || _background) return;
    _background = true;
    final lease = await tasks.begin();
    if (!_background || _disposed) {
      // Foregrounded (or disposed) while the OS was answering.
      if (lease != null) unawaited(tasks.end(lease.id));
      return;
    }
    _lease = lease;
    _graceTimer?.cancel();
    final grace = _graceFor(lease);
    if (grace == Duration.zero) {
      await _onGraceExpired();
    } else {
      _graceTimer = Timer(grace, _onGraceExpired);
    }
  }

  Future<void> _onGraceExpired() async {
    _graceTimer = null;
    final lease = _lease;
    try {
      _stoppedForwards = forwardRules.forwards
          .where((f) => forwards.isRunning(f.id))
          .toList();
      await forwards.stopAll();
      sessions.pauseAll();
    } catch (e) {
      debugPrint('[MobileLifecycleCoordinator] pause failed: $e');
    } finally {
      if (lease != null && identical(_lease, lease)) {
        _lease = null;
        await tasks.end(lease.id);
      }
    }
  }

  Future<void> onForeground() async {
    if (_disposed) return;
    _background = false;
    _graceTimer?.cancel();
    _graceTimer = null;
    final lease = _lease;
    _lease = null;
    if (lease != null) await tasks.end(lease.id);
    final restart = _stoppedForwards;
    _stoppedForwards = const [];
    await sessions.resumePaused(stagger: stagger);
    await sessions.verifyLive();
    for (final f in restart) {
      if (_disposed) return;
      await forwards.start(f);
    }
  }

  void dispose() {
    _disposed = true;
    _graceTimer?.cancel();
    _graceTimer = null;
    final lease = _lease;
    _lease = null;
    if (lease != null) unawaited(tasks.end(lease.id));
  }
}
