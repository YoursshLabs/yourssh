// Terminal rendering perf harness (measurement only; no app code changed).
// Boots the real app, opens a LOCAL shell tab, resizes the window to ~120x40
// cells, types `sh $BENCH/bench.sh yourssh`, and records FrameTimings per
// corpus phase (inferred from results-yourssh.txt line count).
//
//   cd app && flutter drive --profile -d macos \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/terminal_perf_test.dart
//
// Env (via --dart-define): BENCH_DIR, PERF_OUT, PHASE_CAP_S (default 300).
import 'dart:io';
import 'dart:ui' show FramePhase;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yourssh/main.dart' as app;
import 'package:yourssh/models/local_session.dart';
import 'package:yourssh/providers/session_provider.dart';

const _bench = String.fromEnvironment('BENCH_DIR');
const _phaseCap = int.fromEnvironment('PHASE_CAP_S', defaultValue: 300);
const _outPath = String.fromEnvironment('PERF_OUT',
    defaultValue: '/tmp/yourssh-perf-frames.json');
const _corpora = ['plain', 'color', 'unicode', 'tui'];

class _Frame {
  final double build, raster, total;

  /// vsync -> build start (UI thread busy) and build end -> raster start.
  final double vsyncLag, rasterWait;
  _Frame(this.build, this.raster, this.total, this.vsyncLag, this.rasterWait);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('terminal perf', (tester) async {
    final resultsFile = File('$_bench/results-yourssh.txt');
    if (resultsFile.existsSync()) resultsFile.deleteSync();

    String phase = 'boot';
    final frames = <String, List<_Frame>>{};
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        frames.putIfAbsent(phase, () => []).add(_Frame(
            t.buildDuration.inMicroseconds / 1000,
            t.rasterDuration.inMicroseconds / 1000,
            t.totalSpan.inMicroseconds / 1000,
            (t.timestampInMicroseconds(FramePhase.buildStart) -
                    t.timestampInMicroseconds(FramePhase.vsyncStart)) /
                1000,
            (t.timestampInMicroseconds(FramePhase.rasterStart) -
                    t.timestampInMicroseconds(FramePhase.buildFinish)) /
                1000));
      }
    });

    app.main(const <String>[]);
    Future<void> sleep(int ms) => Future.delayed(Duration(milliseconds: ms));
    await sleep(4000);

    // Find SessionProvider and open a local shell.
    final ctx = tester.element(find.byType(Scaffold).first);
    final sp = Provider.of<SessionProvider>(ctx, listen: false);
    await sp.newLocalSession(platformDefault: true);
    await sleep(2000);
    final local = sp.sessions.whereType<LocalSession>().last;
    final term = local.terminal;

    // Size window toward 120x40 cells.
    for (var i = 0; i < 6; i++) {
      final w = term.viewWidth, h = term.viewHeight;
      stdout.writeln('GRID ${w}x$h');
      if (w >= 120 && w <= 124 && h >= 40 && h <= 42) break;
      final size = await windowManager.getSize();
      final nw = (size.width * (121 / w)).clamp(800, 3000).toDouble();
      final nh = (size.height * (40.5 / h)).clamp(600, 2000).toDouble();
      await windowManager.setSize(Size(nw, nh));
      await sleep(1200);
    }
    final epoch = Stopwatch()..start();
    final writeBuckets = <int, int>{}; // 50 ms bucket -> Terminal change count
    term.addListener(() {
      final b = epoch.elapsedMilliseconds ~/ 50;
      writeBuckets[b] = (writeBuckets[b] ?? 0) + 1;
    });
    final lineTimes = <int, int>{}; // results line count -> ms since epoch
    final grid = '${term.viewWidth}x${term.viewHeight}';
    final winSize = await windowManager.getSize();
    stdout.writeln('FINAL GRID $grid window ${winSize.width}x${winSize.height}');

    // Idle baseline then run bench.
    phase = 'idle';
    await sleep(1500);
    phase = 'startup';
    term.textInput('sh $_bench/bench.sh yourssh\r');

    int lines() => resultsFile.existsSync()
        ? resultsFile.readAsLinesSync().where((l) => l.trim().isNotEmpty).length
        : 0;
    final phaseStart = <String, DateTime>{};
    final capped = <String>[];
    var last = -1;
    final deadline = DateTime.now().add(const Duration(minutes: 20));
    while (lines() < 12 && DateTime.now().isBefore(deadline)) {
      final n = lines();
      if (n != last) {
        last = n;
        lineTimes[n] = epoch.elapsedMilliseconds;
        // The corpus being run now is index n~/3 (3 runs per corpus).
        phase = n >= 12 ? 'done' : _corpora[n ~/ 3];
        phaseStart[phase] = DateTime.now();
        stdout.writeln('PHASE $phase (lines=$n)');
      }
      if (phaseStart[phase] != null &&
          DateTime.now().difference(phaseStart[phase]!).inSeconds >
              _phaseCap * 3) {
        // Cannot skip a corpus without changing the script; record and keep
        // waiting until global deadline.
        if (!capped.contains(phase)) capped.add(phase);
      }
      await sleep(50);
    }
    phase = 'done';
    await sleep(500);

    // Ctrl+C during a flood: how long until the terminal stops changing.
    var lastChange = 0;
    void onChange() => lastChange = epoch.elapsedMilliseconds;
    term.addListener(onChange);
    term.textInput('cat $_bench/plain.txt\r');
    await sleep(400);
    final ctrlCAt = epoch.elapsedMilliseconds;
    term.textInput('\x03');
    await sleep(1500);
    term.removeListener(onChange);
    final ctrlCStopMs = lastChange - ctrlCAt;
    stdout.writeln('CTRLC output stopped $ctrlCStopMs ms after ^C');

    final json = StringBuffer('{"grid":"$grid","window":"${winSize.width}x${winSize.height}",'
        '"completedLines":${lines()},"lineTimesMs":{${lineTimes.entries.map((e) => '"${e.key}":${e.value}').join(',')}},"writeBuckets50ms":{${writeBuckets.entries.map((e) => '"${e.key}":${e.value}').join(',')}},"capped":${capped.map((e) => '"$e"').toList()},"ctrlCStopMs":$ctrlCStopMs,"phases":{');
    var first = true;
    frames.forEach((k, v) {
      if (!first) json.write(',');
      first = false;
      json.write('"$k":[${v.map((f) => '[${f.build.toStringAsFixed(3)},${f.raster.toStringAsFixed(3)},${f.total.toStringAsFixed(3)},${f.vsyncLag.toStringAsFixed(3)},${f.rasterWait.toStringAsFixed(3)}]').join(',')}]');
    });
    json.write('}}');
    File(_outPath).writeAsStringSync(json.toString());
    stdout.writeln('WROTE $_outPath');
    expect(lines(), 12);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
