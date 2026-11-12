// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Per-session, time-sliced queue between a byte source (PTY / SSH channel)
/// and `Terminal.write`.
///
/// Heavy output (`cat bigfile`) used to be parsed synchronously chunk by
/// chunk on the UI isolate, starving frames for tens of seconds. The queue
/// instead drains in slices bounded by [budget]; between slices the event loop
/// is released and the next slice is scheduled *after the next frame* so the
/// UI keeps rendering. The terminal is told to repaint once per slice
/// ([commit]), not once per chunk.
///
/// Backpressure: [onPressure] fires `true` when [pendingChars] reaches
/// [highWater] and `false` once it falls to [lowWater]; callers pause/resume
/// the source (SSH stream subscription). [add]'s `onTaken` fires when a chunk
/// starts being consumed (PTY `ackRead`).
///
/// Ordering is exact (FIFO, never reordered). When idle for at least
/// [idleThreshold] a chunk is processed synchronously, so single keystroke
/// echoes keep their latency.
class TerminalWriteQueue {
  TerminalWriteQueue({
    required void Function(String data) write,
    void Function()? commit,
    void Function(String batch)? onBatch,
    void Function(bool paused)? onPressure,
    this.budget = const Duration(milliseconds: 8),
    this.pieceSize = 16 * 1024,
    this.highWater = 1024 * 1024,
    this.lowWater = 256 * 1024,
    this.idleThreshold = const Duration(milliseconds: 16),
    int Function()? clockMicros,
    void Function(void Function() run)? scheduleNext,
  })  : _write = write,
        _commit = commit,
        _onBatch = onBatch,
        _onPressure = onPressure,
        _clockMicros = clockMicros ?? _defaultClock(),
        _scheduleNext = scheduleNext ?? _afterFrame {
    assert(pieceSize >= 2);
    _lastCommitMicros = _clockMicros() - idleThreshold.inMicroseconds - 1;
  }

  /// Max time one slice may spend writing (checked between pieces).
  final Duration budget;

  /// Largest string handed to a single `write` call.
  final int pieceSize;
  final int highWater;
  final int lowWater;
  final Duration idleThreshold;

  final void Function(String) _write;
  final void Function()? _commit;
  final void Function(String)? _onBatch;
  final void Function(bool)? _onPressure;
  final int Function() _clockMicros;
  final void Function(void Function()) _scheduleNext;

  final Queue<_Entry> _queue = Queue<_Entry>();
  int _pending = 0;
  bool _paused = false;
  bool _scheduled = false;
  bool _disposed = false;
  bool _draining = false;
  int _token = 0;
  late int _lastCommitMicros;

  /// Characters queued and not yet written.
  int get pendingChars => _pending;

  /// Whether [onPressure] last signalled "pause".
  bool get isPaused => _paused;

  bool get isIdle => _queue.isEmpty && !_scheduled;

  static int Function() _defaultClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsedMicroseconds;
  }

  /// Schedules [run] right after the next rendered frame, with a timer
  /// fallback for when no frame is produced (hidden tab / minimised window /
  /// repaint suppressed by synchronized output).
  static void _afterFrame(void Function() run) {
    var fired = false;
    void once() {
      if (fired) return;
      fired = true;
      run();
    }

    Timer(const Duration(milliseconds: 24), once);
    try {
      SchedulerBinding.instance.addPostFrameCallback((_) => once());
    } catch (_) {
      // No binding (plain Dart test): the timer alone drives the queue.
    }
  }

  /// Queues [data]. [onTaken] runs once, when the first piece of this chunk is
  /// about to be consumed (immediately for empty strings).
  void add(String data, {void Function()? onTaken}) {
    if (_disposed) return;
    if (data.isEmpty) {
      onTaken?.call();
      return;
    }
    final wasIdle = _queue.isEmpty;
    _queue.add(_Entry(data, onTaken));
    _pending += data.length;
    if (!_paused && _pending >= highWater) {
      _paused = true;
      _onPressure?.call(true);
    }
    if (_draining) return; // re-entrant add from a callback: slice continues
    if (wasIdle &&
        !_scheduled &&
        _clockMicros() - _lastCommitMicros >=
            idleThreshold.inMicroseconds) {
      _drainSlice();
    } else {
      _ensureScheduled();
    }
  }

  void _ensureScheduled() {
    if (_scheduled || _disposed || _queue.isEmpty) return;
    _scheduled = true;
    final token = ++_token;
    _scheduleNext(() {
      if (token != _token || _disposed) return;
      _scheduled = false;
      _drainSlice();
    });
  }

  /// Synchronously drains everything queued (one [commit], one [onBatch]).
  /// Use where ordering with out-of-band terminal writes matters (session
  /// close, tests).
  void flush() {
    if (_disposed || _draining) return;
    _token++; // invalidate any scheduled slice
    _scheduled = false;
    if (_queue.isEmpty) return;
    _drain(unlimited: true);
  }

  void dispose() {
    _disposed = true;
    _token++;
    _scheduled = false;
    // Release anyone waiting on acks so a native read thread never blocks.
    while (_queue.isNotEmpty) {
      final e = _queue.removeFirst();
      if (!e.taken) {
        e.taken = true;
        e.onTaken?.call();
      }
    }
    _pending = 0;
  }

  void _drainSlice() => _drain(unlimited: false);

  void _drain({required bool unlimited}) {
    _draining = true;
    final batch = _onBatch == null ? null : StringBuffer();
    final startMicros = _clockMicros();
    final budgetMicros = budget.inMicroseconds;
    try {
      while (_queue.isNotEmpty) {
        final e = _queue.first;
        if (!e.taken) {
          e.taken = true;
          e.onTaken?.call();
        }
        final text = e.text;
        var end = e.offset + pieceSize;
        if (end >= text.length) {
          end = text.length;
        } else if (_isHighSurrogate(text.codeUnitAt(end - 1))) {
          end--; // never split a surrogate pair across writes
        }
        final piece = (e.offset == 0 && end == text.length)
            ? text
            : text.substring(e.offset, end);
        _pending -= end - e.offset;
        if (end == text.length) {
          _queue.removeFirst();
        } else {
          e.offset = end;
        }
        try {
          _write(piece);
        } catch (err, st) {
          debugPrint('[TerminalWriteQueue] write threw: $err\n$st');
        }
        batch?.write(piece);
        if (!unlimited && _clockMicros() - startMicros >= budgetMicros) break;
      }
    } finally {
      _draining = false;
      _lastCommitMicros = _clockMicros();
    }
    try {
      _commit?.call();
    } catch (err, st) {
      debugPrint('[TerminalWriteQueue] commit threw: $err\n$st');
    }
    if (batch != null && batch.isNotEmpty) {
      try {
        _onBatch!(batch.toString());
      } catch (err, st) {
        debugPrint('[TerminalWriteQueue] onBatch threw: $err\n$st');
      }
    }
    if (_paused && _pending <= lowWater) {
      _paused = false;
      _onPressure?.call(false);
    }
    _ensureScheduled();
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
}

class _Entry {
  _Entry(this.text, this.onTaken);
  final String text;
  final void Function()? onTaken;
  int offset = 0;
  bool taken = false;
}
