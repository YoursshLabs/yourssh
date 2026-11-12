import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/terminal_write_queue.dart';

void main() {
  late int now; // microseconds, advanced by fake writes
  late List<void Function()> scheduled;
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
      clockMicros: () => now,
      scheduleNext: scheduled.add,
    );
  }

  void runScheduled() {
    final run = scheduled.removeAt(0);
    run();
  }

  setUp(() {
    now = 1000000;
    scheduled = [];
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
}
