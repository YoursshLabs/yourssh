import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/terminal_write_queue.dart';

void main() {
  late int now; // microseconds, advanced by fake writes
  late List<void Function()> scheduled;
  late List<({Duration delay, void Function() run})> timers;
  late List<String> written;
  late int commits;
  late List<String> batches;
  late List<bool> pressure;

  TerminalWriteQueue make({
    int pieceSize = 10,
    Duration budget = const Duration(milliseconds: 3),
    int high = 100,
    int low = 30,
    int writeCostMicros = 1000,
    Duration commitInterval = Duration.zero,
    Duration floodInterval = Duration.zero,
    int floodChars = 1 << 30,
  }) {
    return TerminalWriteQueue(
      write: (s) {
        written.add(s);
        now += writeCostMicros;
      },
      commit: () => commits++,
      onBatch: batches.add,
      onPressure: pressure.add,
      budget: budget,
      pieceSize: pieceSize,
      highWater: high,
      lowWater: low,
      idleThreshold: const Duration(milliseconds: 16),
      commitInterval: commitInterval,
      floodInterval: floodInterval,
      floodChars: floodChars,
      clockMicros: () => now,
      scheduleNext: scheduled.add,
      scheduleAfter: (d, run) => timers.add((delay: d, run: run)),
    );
  }

  void runScheduled() {
    final run = scheduled.removeAt(0);
    run();
  }

  setUp(() {
    now = 1000000;
    scheduled = [];
    timers = [];
    written = [];
    commits = 0;
    batches = [];
    pressure = [];
  });

  test('idle queue writes the first chunk synchronously', () {
    final q = make();
    q.add('abc');
    expect(written, ['abc']);
    expect(commits, 1);
    expect(scheduled, isEmpty);
  });

  test('chunk right after a commit is queued, not written inline', () {
    final q = make();
    q.add('abc');
    q.add('def');
    expect(written, ['abc']);
    expect(scheduled, hasLength(1));
    runScheduled();
    expect(written, ['abc', 'def']);
  });

  test('ordering is exact across chunks and pieces', () {
    final q = make(pieceSize: 4, budget: const Duration(milliseconds: 2));
    final chunks = List.generate(20, (i) => 'chunk-$i;' * 3);
    for (final c in chunks) {
      q.add(c);
    }
    while (scheduled.isNotEmpty) {
      runScheduled();
    }
    expect(written.join(), chunks.join());
    expect(q.pendingChars, 0);
  });

  test('a slice stops at the time budget and commits once', () {
    final q = make(pieceSize: 10, budget: const Duration(milliseconds: 3));
    q.add('x'); // inline write (consumes idle state)
    commits = 0;
    written.clear();
    q.add('a' * 100);
    runScheduled();
    // 1 ms per write, 3 ms budget -> 3 pieces in the slice.
    expect(written, hasLength(3));
    expect(commits, 1);
    expect(scheduled, hasLength(1)); // remainder scheduled
    expect(batches.last, 'a' * 30);
  });

  test('many small chunks cause one commit per slice', () {
    final q = make(pieceSize: 100, budget: const Duration(milliseconds: 50));
    q.add('first');
    commits = 0;
    for (var i = 0; i < 30; i++) {
      q.add('c$i');
    }
    runScheduled();
    expect(commits, 1);
    expect(written.skip(1).join(), List.generate(30, (i) => 'c$i').join());
  });

  test('flush drains synchronously in order with a single commit', () {
    final q = make();
    q.add('one');
    commits = 0;
    q.add('two');
    q.add('three' * 10);
    q.flush();
    expect(written.join(), 'one' 'two' + 'three' * 10);
    expect(commits, 1);
    expect(q.pendingChars, 0);
    // the scheduled slice is invalidated
    final run = scheduled.removeAt(0);
    written.clear();
    run();
    expect(written, isEmpty);
  });

  test('surrogate pairs are never split between writes', () {
    final q = make(pieceSize: 3);
    q.add('x');
    final s = 'ab\u{1F600}cd\u{1F600}ef';
    q.add(s);
    q.flush();
    for (final piece in written) {
      final units = piece.codeUnits;
      if (units.isEmpty) continue;
      expect(units.last >= 0xD800 && units.last <= 0xDBFF, isFalse,
          reason: 'piece ends with a lone high surrogate: $piece');
    }
    expect(written.join(), 'x$s');
  });

  test('backpressure pauses at high water and resumes at low water', () {
    final q = make(pieceSize: 10, budget: const Duration(milliseconds: 2));
    q.add('x');
    q.add('a' * 60);
    expect(pressure, isEmpty);
    q.add('b' * 60); // 120 >= 100
    expect(pressure, [true]);
    expect(q.isPaused, isTrue);
    runScheduled(); // drains ~20 -> 100 pending, still above low
    expect(pressure, [true]);
    while (q.pendingChars > 30 && scheduled.isNotEmpty) {
      runScheduled();
    }
    expect(pressure, [true, false]);
    expect(q.isPaused, isFalse);
  });

  test('pausing a stream subscription via onPressure stops delivery', () async {
    final controller = StreamController<String>();
    late StreamSubscription<String> sub;
    final q = TerminalWriteQueue(
      write: (_) {},
      highWater: 10,
      lowWater: 2,
      pieceSize: 4,
      budget: Duration.zero,
      clockMicros: () => now,
      scheduleNext: scheduled.add,
      onPressure: (p) => p ? sub.pause() : sub.resume(),
    );
    sub = controller.stream.listen(q.add);
    q.add('seed');
    controller.add('0123456789ABCDEF');
    await Future<void>.delayed(Duration.zero);
    expect(sub.isPaused, isTrue);
    while (scheduled.isNotEmpty) {
      runScheduled();
    }
    expect(sub.isPaused, isFalse);
    await controller.close();
  });

  test('onTaken fires once per chunk, in order, when consumption starts', () {
    final q = make(pieceSize: 5, budget: const Duration(milliseconds: 1));
    final taken = <int>[];
    q.add('x');
    q.add('a' * 12, onTaken: () => taken.add(1));
    q.add('b' * 3, onTaken: () => taken.add(2));
    q.add('', onTaken: () => taken.add(3)); // empty: immediate
    expect(taken, [3]);
    runScheduled();
    expect(taken, [3, 1]);
    while (scheduled.isNotEmpty) {
      runScheduled();
    }
    expect(taken, [3, 1, 2]);
  });

  test('dispose releases pending acks and drops data', () {
    final q = make();
    q.add('x');
    var acked = 0;
    q.add('y' * 5, onTaken: () => acked++);
    q.dispose();
    expect(acked, 1);
    expect(q.pendingChars, 0);
    written.clear();
    scheduled.removeAt(0)();
    expect(written, isEmpty);
    q.add('z');
    expect(written, isEmpty);
  });

  test('a throwing writer does not wedge the queue', () {
    var calls = 0;
    final q = TerminalWriteQueue(
      write: (s) {
        calls++;
        if (calls == 2) throw StateError('boom');
      },
      clockMicros: () => now,
      scheduleNext: scheduled.add,
    );
    q.add('a');
    q.add('b');
    q.add('c');
    q.flush();
    expect(calls, 3);
    expect(q.pendingChars, 0);
  });

  group('commit throttling', () {
    test('sustained output commits at most once per commitInterval', () {
      final q = make(
        pieceSize: 10,
        budget: const Duration(milliseconds: 3),
        commitInterval: const Duration(milliseconds: 16),
      );
      q.add('x');
      commits = 0;
      written.clear();
      q.add('a' * 400); // 40 pieces, 1 ms each -> ~14 slices of 3 ms
      var slices = 0;
      while (scheduled.isNotEmpty) {
        runScheduled();
        slices++;
      }
      expect(slices, greaterThan(10));
      expect(written.join(), 'a' * 400);
      // 40 ms of writing at 16 ms spacing: a handful of commits, not one per
      // slice.
      expect(commits, lessThanOrEqualTo(3));
      expect(commits, greaterThanOrEqualTo(1));
    });

    test('a trailing commit is scheduled when the queue empties early', () {
      final q = make(commitInterval: const Duration(milliseconds: 16));
      q.add('x');
      commits = 0;
      q.add('abc'); // queued: inside the interval after the last commit
      runScheduled(); // writes abc, only 1 ms after the last commit
      expect(written, ['x', 'abc']);
      expect(commits, 0);
      expect(timers, hasLength(1));
      expect(timers.single.delay.inMilliseconds, inInclusiveRange(10, 16));
      now += 16000;
      timers.removeAt(0).run();
      expect(commits, 1);
    });

    test('new data arriving before the trailing commit shares one commit', () {
      final q = make(commitInterval: const Duration(milliseconds: 16));
      q.add('x');
      commits = 0;
      q.add('a');
      runScheduled();
      q.add('b');
      runScheduled();
      now += 20000;
      while (timers.isNotEmpty) {
        timers.removeAt(0).run();
      }
      expect(commits, 1);
      expect(q.isIdle, isTrue);
    });

    test('flood volume switches to the slower floodInterval', () {
      final q = make(
        pieceSize: 10,
        budget: const Duration(milliseconds: 3),
        commitInterval: const Duration(milliseconds: 16),
        floodInterval: const Duration(milliseconds: 33),
        floodChars: 100,
        writeCostMicros: 2000,
      );
      q.add('x');
      commits = 0;
      final commitTimes = <int>[];
      final base = now;
      q.add('a' * 1000);
      while (scheduled.isNotEmpty) {
        final before = commits;
        runScheduled();
        if (commits > before) commitTimes.add(now - base);
      }
      expect(commitTimes.length, greaterThan(2));
      for (var i = 1; i < commitTimes.length; i++) {
        expect(commitTimes[i] - commitTimes[i - 1], greaterThanOrEqualTo(33000));
      }
    });

    test('supply-bound flood (queue keeps emptying) still renders at 30 fps', () {
      final q = make(
        pieceSize: 1000,
        budget: const Duration(milliseconds: 3),
        commitInterval: const Duration(milliseconds: 16),
        floodInterval: const Duration(milliseconds: 33),
        floodChars: 500,
        writeCostMicros: 100,
      );
      final base = now;
      final commitTimes = <int>[];
      var lastCommits = 0;
      // 300 ms of 100-char chunks every 1 ms: the queue empties after every
      // chunk, so only the volume per window reveals the flood.
      for (var t = 0; t < 300; t++) {
        q.add('c' * 100);
        while (scheduled.isNotEmpty) {
          runScheduled();
        }
        now += 1000;
        if (timers.isNotEmpty && timers.first.delay.inMicroseconds <= 1000) {
          timers.removeAt(0).run();
        } else if (timers.isNotEmpty) {
          final first = timers.removeAt(0);
          timers.insert(
              0,
              (
                delay: first.delay - const Duration(milliseconds: 1),
                run: first.run
              ));
        }
        if (commits > lastCommits) {
          lastCommits = commits;
          commitTimes.add(now - base);
        }
      }
      // After the first (cold) windows every gap must be the flood interval.
      final tail = commitTimes.skip(3).toList();
      expect(tail.length, greaterThan(3));
      for (var i = 1; i < tail.length; i++) {
        expect(tail[i] - tail[i - 1], greaterThanOrEqualTo(32000));
      }
    });

    test('flush commits uncommitted data even inside the interval', () {
      final q = make(commitInterval: const Duration(milliseconds: 16));
      q.add('x');
      commits = 0;
      q.add('abc');
      runScheduled();
      expect(commits, 0);
      q.flush();
      expect(commits, 1);
      expect(q.isIdle, isTrue);
    });

    test('an idle queue still writes and commits synchronously', () {
      final q = make(commitInterval: const Duration(milliseconds: 16));
      now += 100000;
      q.add('k');
      expect(written, ['k']);
      expect(commits, 1);
    });
  });

  group('bytes entries', () {
    test('addBytes feeds writeBytes in order, pieces split by pieceSize', () {
      final got = <List<int>>[];
      final q = TerminalWriteQueue(
        write: (_) => fail('text path unused'),
        writeBytes: (b) => got.add(List<int>.of(b)),
        pieceSize: 4,
        clockMicros: () => now,
        scheduleNext: scheduled.add,
        scheduleAfter: (d, run) => timers.add((delay: d, run: run)),
      );
      q.addBytes(Uint8List.fromList(List.generate(10, (i) => i)));
      q.flush();
      expect(got, [
        [0, 1, 2, 3],
        [4, 5, 6, 7],
        [8, 9],
      ]);
    });

    test('onConsumed reports every unit exactly once, batched per slice', () {
      final consumed = <int>[];
      final q = TerminalWriteQueue(
        write: (_) {},
        writeBytes: (_) => now += 1000,
        onConsumed: consumed.add,
        pieceSize: 10,
        budget: const Duration(milliseconds: 3),
        clockMicros: () => now,
        scheduleNext: scheduled.add,
        scheduleAfter: (d, run) => timers.add((delay: d, run: run)),
      );
      q.addBytes(Uint8List(100)); // idle: first slice runs inline
      while (scheduled.isNotEmpty) {
        runScheduled();
      }
      q.flush();
      expect(consumed.fold<int>(0, (a, b) => a + b), 100);
      expect(consumed.length, lessThan(10), reason: 'batched, not per piece');
      expect(q.pendingChars, 0);
    });

    test('onBatch sees the exact text even when a character is split', () {
      final text = <String>[];
      final bytes = utf8.encode('aé日😀b' * 7);
      final q = TerminalWriteQueue(
        write: (_) {},
        writeBytes: (_) {},
        onBatch: text.add,
        pieceSize: 3, // splits multi-byte sequences
        clockMicros: () => now,
        scheduleNext: scheduled.add,
        scheduleAfter: (d, run) => timers.add((delay: d, run: run)),
      );
      q.addBytes(Uint8List.fromList(bytes));
      q.flush();
      expect(text.join(), 'aé日😀b' * 7);
    });

    test('dispose returns the credit of everything still queued', () {
      final consumed = <int>[];
      final q = TerminalWriteQueue(
        write: (_) {},
        writeBytes: (_) {},
        onConsumed: consumed.add,
        clockMicros: () => now,
        scheduleNext: scheduled.add,
        scheduleAfter: (d, run) => timers.add((delay: d, run: run)),
      );
      q.addBytes(Uint8List(50)); // inline (idle)
      q.addBytes(Uint8List(70)); // queued behind the schedule
      final before = consumed.fold<int>(0, (a, b) => a + b);
      q.dispose();
      expect(consumed.fold<int>(0, (a, b) => a + b), 120);
      expect(before, lessThanOrEqualTo(120));
    });
  });
}
