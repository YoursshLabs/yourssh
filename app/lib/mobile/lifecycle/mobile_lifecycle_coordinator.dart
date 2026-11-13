import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/port_forward.dart';
import '../../providers/port_forward_provider.dart';
import '../../providers/session_provider.dart';
import '../../services/p2p_sync_service.dart';
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
    Future<void> Function()? stopPairing,
  }) : stopPairing = stopPairing ?? P2PSyncService.stopAll;

  final SessionProvider sessions;
  final PortForwardService forwards;
  final PortForwardProvider forwardRules;
  final BackgroundTasks tasks;
  final Duration stagger;
  final Duration maxGrace;

  /// Closes the LAN pairing server (its socket dies with the suspension).
  final Future<void> Function() stopPairing;

  /// The OS keeps part of its allowance for its own expiration handling.
  static const _osMargin = Duration(seconds: 5);

  Timer? _graceTimer;
  BackgroundLease? _lease;
  List<PortForward> _stoppedForwards = const [];
  Future<void>? _expiry;
  final _open = <int>{};

  Future<void> _endLease(BackgroundLease lease) async {
    if (_open.remove(lease.id)) await tasks.end(lease.id);
  }
  bool _background = false;
  bool _disposed = false;

  /// Bumped on every background/foreground transition so an answer to an older
  /// `begin()` can tell it was superseded.
  int _epoch = 0;

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
    final epoch = ++_epoch;
    final lease = await tasks.begin();
    if (epoch != _epoch || _disposed) {
      // Foregrounded (or backgrounded again) while the OS was answering.
      if (lease != null) unawaited(tasks.end(lease.id));
      return;
    }
    if (lease != null) _open.add(lease.id);
    _lease = lease;
    _graceTimer?.cancel();
    final grace = _graceFor(lease);
    if (grace == Duration.zero) {
      await (_expiry = _onGraceExpired(epoch));
    } else {
      _graceTimer = Timer(grace, () => _expiry = _onGraceExpired(epoch));
    }
  }

  Future<void> _onGraceExpired(int epoch) async {
    _graceTimer = null;
    final lease = _lease;
    try {
      // Remember what ran, across several backgrounds before one foreground.
      final known = _stoppedForwards.map((f) => f.id).toSet();
      _stoppedForwards = [
        ..._stoppedForwards,
        ...forwardRules.forwards
            .where((f) => forwards.isRunning(f.id) && !known.contains(f.id)),
      ];
      await forwards.stopAll();
      // The app came back (or left again) while the tunnels were closing:
      // this expiry belongs to an older background and must not pause
      // anything.
      if (epoch == _epoch && !_disposed) {
        sessions.pauseAll();
        await stopPairing();
      }
    } catch (e) {
      debugPrint('[MobileLifecycleCoordinator] pause failed: $e');
    } finally {
      // Release our own lease even when a newer background already replaced
      // `_lease`; [_endLease] is idempotent against the foreground's release.
      if (lease != null) {
        if (identical(_lease, lease)) _lease = null;
        await _endLease(lease);
      }
    }
  }

  Future<void> onForeground() async {
    // `resumed` also follows an inactive-only transition (Face ID sheet,
    // Control Center): nothing was backgrounded, so there is nothing to do.
    if (_disposed || !_background) return;
    _background = false;
    final epoch = ++_epoch;
    _graceTimer?.cancel();
    _graceTimer = null;
    final expiry = _expiry;
    if (expiry != null) await expiry;
    // A newer background started while we waited: it owns the lease, the
    // recorded forwards and the next foreground.
    if (epoch != _epoch || _disposed) return;
    if (identical(_expiry, expiry)) _expiry = null;
    final lease = _lease;
    _lease = null;
    if (lease != null) await _endLease(lease);
    // Each step below can take seconds; a background that began meanwhile
    // owns the recorded forwards and the paused sessions.
    bool stale() => epoch != _epoch || _disposed;
    if (stale()) return;
    final restart = _stoppedForwards;
    _stoppedForwards = const [];
    await sessions.resumePaused(stagger: stagger);
    if (stale()) {
      _stoppedForwards = [..._stoppedForwards, ...restart];
      return;
    }
    await sessions.verifyLive();
    for (var i = 0; i < restart.length; i++) {
      if (stale()) {
        // Keep what was not restarted for the next foreground.
        _stoppedForwards = [..._stoppedForwards, ...restart.skip(i)];
        return;
      }
      await forwards.start(restart[i]);
    }
  }

  void dispose() {
    _disposed = true;
    _graceTimer?.cancel();
    _graceTimer = null;
    final lease = _lease;
    _lease = null;
    if (lease != null) unawaited(_endLease(lease));
  }
}
