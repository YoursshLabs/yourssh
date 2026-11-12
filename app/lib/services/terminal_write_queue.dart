// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' show max;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Per-session, time-sliced queue between a byte source (PTY / SSH channel)
/// and `Terminal.write`.
///
/// Heavy output (`cat bigfile`) used to be parsed synchronously chunk by
/// chunk on the UI isolate, starving frames for tens of seconds. The queue
/// instead drains in short slices bounded by [budget]; between slices the
/// event loop is released (zero-delay timer) so frames, input and PTY/SSH data
/// events interleave with parsing. Parsing therefore runs as fast as the
/// source delivers, while the terminal is told to repaint ([commit]) at a
/// steady, throttled rate: at most once per [commitInterval], or once per
/// [floodInterval] when more than [floodChars] arrive within a window (a
/// repaint re-records every visible line, so rendering a flood at full frame
/// rate only steals parse time).
///
/// Backpressure: [onPressure] fires `true` when [pendingChars] reaches
/// [highWater] and `false` once it falls to [lowWater]; callers pause/resume
/// the source (SSH stream subscription). [add]'s `onTaken` fires when a chunk
/// starts being consumed (PTY `ackRead`).
///
/// Chunks may be text ([add]) or raw UTF-8 bytes ([addBytes], fed to
/// `writeBytes` without any String round trip). [onBatch] always receives
/// text: byte pieces are decoded for it with one stateful decoder, so it sees
/// exactly the text a stream decoder would produce. [onConsumed] reports, once
/// per slice, how many units (chars / bytes) were parsed so a source with
/// credit based flow control can return credit in batches.
///
/// Ordering is exact (FIFO, never reordered). When idle for at least
/// [idleThreshold] a chunk is processed synchronously, so single keystroke
/// echoes keep their latency.
class TerminalWriteQueue {
  TerminalWriteQueue({
    required void Function(String data) write,
    void Function(Uint8List data)? writeBytes,
    void Function(int units)? onConsumed,
    void Function()? commit,
    void Function(String batch)? onBatch,
    void Function(bool paused)? onPressure,
    this.budget = const Duration(milliseconds: 4),
    this.commitInterval = const Duration(milliseconds: 16),
    this.floodInterval = const Duration(milliseconds: 33),
    this.floodChars = 32 * 1024,
    this.pieceSize = 16 * 1024,
    this.highWater = 1024 * 1024,
    this.lowWater = 256 * 1024,
    this.idleThreshold = const Duration(milliseconds: 16),
    int Function()? clockMicros,
    void Function(void Function() run)? scheduleNext,
    void Function(Duration delay, void Function() run)? scheduleAfter,
  })  : _write = write,
        _writeBytes = writeBytes,
        _onConsumed = onConsumed,
        _commit = commit,
        _onBatch = onBatch,
        _onPressure = onPressure,
        _clockMicros = clockMicros ?? _defaultClock(),
        _scheduleNext = scheduleNext ?? _yieldToEventLoop,
        _scheduleAfter = scheduleAfter ?? _timerAfter {
    assert(pieceSize >= 2);
    _lastCommitMicros = _clockMicros() - idleThreshold.inMicroseconds - 1;
  }

  /// Max time one slice may spend writing (checked between pieces). Kept well
  /// under a frame so a vsync is never delayed by more than this.
  final Duration budget;

  /// Minimum spacing between repaints during sustained output.
  final Duration commitInterval;

  /// Spacing used instead while a flood (>= [floodChars] per window) lasts.
  /// Never above ~33 ms (30 fps).
  final Duration floodInterval;
  final int floodChars;

  /// Largest string handed to a single `write` call.
  final int pieceSize;
  final int highWater;
  final int lowWater;
  final Duration idleThreshold;

  final void Function(String) _write;
  final void Function(Uint8List)? _writeBytes;
  final void Function(int)? _onConsumed;
  final void Function()? _commit;
  final void Function(String)? _onBatch;
  final void Function(bool)? _onPressure;
  final int Function() _clockMicros;
  final void Function(void Function()) _scheduleNext;
  final void Function(Duration, void Function()) _scheduleAfter;

  // Stateful: a multi-byte sequence split across pieces / slices is joined.
  StringBuffer? _batchOut;
  late final ByteConversionSink _decoder = const Utf8Decoder(
    allowMalformed: true,
  ).startChunkedConversion(_StringSink((s) => _batchOut?.write(s)));

  final Queue<_Entry> _queue = Queue<_Entry>();
  int _pending = 0;
  bool _paused = false;
  bool _scheduled = false;
  bool _disposed = false;
  bool _draining = false;
  int _token = 0;
  late int _lastCommitMicros;
  bool _uncommitted = false;
  bool _commitTimerPending = false;
  int _commitTimerGen = 0;
  int _charsSinceCommit = 0;
  int _prevWindowChars = 0;

  /// Characters queued and not yet written.
  int get pendingChars => _pending;

  /// Whether [onPressure] last signalled "pause".
  bool get isPaused => _paused;

  bool get isIdle => _queue.isEmpty && !_scheduled && !_commitTimerPending;

  static int Function() _defaultClock() {
    final sw = Stopwatch()..start();
    return () => sw.elapsedMicroseconds;
  }

  /// Runs [run] on a later event-loop turn: everything already queued
  /// (vsync, PTY / socket data, input) is handled first.
  static void _yieldToEventLoop(void Function() run) {
    Timer(Duration.zero, run);
  }

  static void _timerAfter(Duration delay, void Function() run) {
    Timer(delay, run);
  }

  /// Queues raw UTF-8 [data] (needs a `writeBytes` callback). The queue keeps
  /// a reference: the caller must not mutate [data] afterwards. A multi-byte
  /// sequence may be split across chunks. Don't mix with [add] on a stream
  /// whose chunks can split a sequence: text pieces are parsed as is.
  void addBytes(Uint8List data, {void Function()? onTaken}) {
    assert(_writeBytes != null, 'addBytes needs a writeBytes callback');
    _enqueue(_Entry.bytes(data, onTaken));
  }

  /// Queues [data]. [onTaken] runs once, when the first piece of this chunk is
  /// about to be consumed (immediately for empty strings).
  void add(String data, {void Function()? onTaken}) {
    if (_disposed) return;
    if (data.isEmpty) {
      onTaken?.call();
      return;
    }
    _enqueue(_Entry(data, onTaken));
  }

  void _enqueue(_Entry entry) {
    if (_disposed) return;
    if (entry.length == 0) {
      entry.onTaken?.call();
      return;
    }
    final wasIdle = _queue.isEmpty;
    _queue.add(entry);
    _pending += entry.length;
    if (!_paused && _pending >= highWater) {
      _paused = true;
      _onPressure?.call(true);
    }
    if (_draining) return; // re-entrant add from a callback: slice continues
    if (wasIdle &&
        !_scheduled &&
        _clockMicros() - _lastCommitMicros >=
            max(idleThreshold.inMicroseconds,
                _currentInterval.inMicroseconds)) {
      _drain(unlimited: false, forceCommit: true);
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
    if (_queue.isEmpty) {
      if (_uncommitted) _doCommit();
      return;
    }
    _drain(unlimited: true);
  }

  void dispose() {
    _disposed = true;
    _token++;
    _scheduled = false;
    _commitTimerPending = false;
    // Release anyone waiting on acks so a native read thread never blocks.
    while (_queue.isNotEmpty) {
      final e = _queue.removeFirst();
      if (!e.taken) {
        e.taken = true;
        e.onTaken?.call();
      }
    }
    final rest = _pending;
    _pending = 0;
    if (rest > 0) _onConsumed?.call(rest);
  }

  void _drainSlice() => _drain(unlimited: false);

  void _drain({required bool unlimited, bool forceCommit = false}) {
    _draining = true;
    final batch = _onBatch == null ? null : StringBuffer();
    _batchOut = batch;
    var consumed = 0;
    final startMicros = _clockMicros();
    final budgetMicros = budget.inMicroseconds;
    try {
      while (_queue.isNotEmpty) {
        final e = _queue.first;
        if (!e.taken) {
          e.taken = true;
          e.onTaken?.call();
        }
        final isBytes = e.bytes != null;
        final length = e.length;
        var end = e.offset + pieceSize;
        if (end >= length) {
          end = length;
        } else if (!isBytes && _isHighSurrogate(e.text!.codeUnitAt(end - 1))) {
          end--; // never split a surrogate pair across writes
        }
        final taken = end - e.offset;
        final Object piece;
        if (isBytes) {
          piece = (e.offset == 0 && end == length)
              ? e.bytes!
              : Uint8List.sublistView(e.bytes!, e.offset, end);
        } else {
          piece = (e.offset == 0 && end == length)
              ? e.text!
              : e.text!.substring(e.offset, end);
        }
        _pending -= taken;
        _charsSinceCommit += taken;
        consumed += taken;
        if (end == length) {
          _queue.removeFirst();
        } else {
          e.offset = end;
        }
        _uncommitted = true;
        try {
          if (isBytes) {
            _writeBytes!(piece as Uint8List);
          } else {
            _write(piece as String);
          }
        } catch (err, st) {
          debugPrint('[TerminalWriteQueue] write threw: $err\n$st');
        }
        if (batch != null) {
          if (isBytes) {
            _decoder.add(piece as Uint8List);
          } else {
            batch.write(piece);
          }
        }
        if (!unlimited && _clockMicros() - startMicros >= budgetMicros) break;
      }
    } finally {
      _draining = false;
    }
    if (consumed > 0) {
      try {
        _onConsumed?.call(consumed);
      } catch (err, st) {
        debugPrint('[TerminalWriteQueue] onConsumed threw: $err\n$st');
      }
    }
    if (unlimited || forceCommit) {
      _doCommit();
    } else {
      _maybeCommit();
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

  Duration get _currentInterval =>
      (_prevWindowChars >= floodChars ||
              _charsSinceCommit + _pending >= floodChars)
          ? floodInterval
          : commitInterval;

  /// Repaint now if the interval since the last one elapsed; otherwise leave
  /// it to a later slice, or to a trailing timer when the queue is empty.
  void _maybeCommit() {
    if (!_uncommitted) return;
    final interval = _currentInterval.inMicroseconds;
    final since = _clockMicros() - _lastCommitMicros;
    if (since >= interval) {
      _doCommit();
      return;
    }
    if (_queue.isNotEmpty || _commitTimerPending) return;
    _commitTimerPending = true;
    final gen = ++_commitTimerGen;
    _scheduleAfter(Duration(microseconds: interval - since), () {
      // A stale timer (its window was already committed) must not fire early
      // for the next window.
      if (gen != _commitTimerGen || !_commitTimerPending || _disposed) return;
      _commitTimerPending = false;
      if (_queue.isNotEmpty) return; // the next slice decides
      if (_uncommitted) _doCommit();
    });
  }

  void _doCommit() {
    _commitTimerPending = false; // a pending trailing timer becomes a no-op
    _uncommitted = false;
    final now = _clockMicros();
    // The previous window's volume keeps the flood interval in force while
    // the queue repeatedly empties (supply-bound floods); a long quiet gap
    // forgets it.
    _prevWindowChars =
        now - _lastCommitMicros > 4 * floodInterval.inMicroseconds
            ? 0
            : _charsSinceCommit;
    _charsSinceCommit = 0;
    _lastCommitMicros = now;
    try {
      _commit?.call();
    } catch (err, st) {
      debugPrint('[TerminalWriteQueue] commit threw: $err\n$st');
    }
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
}

class _StringSink implements Sink<String> {
  _StringSink(this._onData);
  final void Function(String) _onData;
  @override
  void add(String data) => _onData(data);
  @override
  void close() {}
}

class _Entry {
  _Entry(String this.text, this.onTaken) : bytes = null;
  _Entry.bytes(Uint8List this.bytes, this.onTaken) : text = null;
  final String? text;
  final Uint8List? bytes;
  int get length => bytes?.length ?? text!.length;
  final void Function()? onTaken;
  int offset = 0;
  bool taken = false;
}
