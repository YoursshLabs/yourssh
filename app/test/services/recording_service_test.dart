import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/recording_service.dart';

void main() {
  late RecordingService service;
  late Directory tmpDir;

  setUp(() async {
    service = RecordingService();
    tmpDir = await Directory.systemTemp.createTemp('rec_test');
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  test('isRecording returns false initially', () {
    expect(service.isRecording('s1'), isFalse);
  });

  test('startRecording creates file with asciicast header', () async {
    final path = '${tmpDir.path}/test.cast';
    await service.startRecording('s1', filePath: path, width: 80, height: 24, title: 'test');
    expect(service.isRecording('s1'), isTrue);
    // Close the sink before reading — Windows locks the open file, which
    // breaks both the read and tearDown's directory delete.
    await service.stopRecording('s1');
    final lines = await File(path).readAsLines();
    expect(lines.first, contains('"version":2'));
    expect(lines.first, contains('"width":80'));
  });

  test('writeOutput appends event line', () async {
    final path = '${tmpDir.path}/test2.cast';
    await service.startRecording('s1', filePath: path, width: 80, height: 24, title: 't');
    service.writeOutput('s1', 'hello');
    final stopped = await service.stopRecording('s1');
    expect(stopped, path);
    final lines = await File(path).readAsLines();
    expect(lines.length, 2); // header + 1 event
    expect(lines[1], contains('"o"'));
    expect(lines[1], contains('hello'));
  });

  test('writeOutput is no-op when not recording', () {
    expect(() => service.writeOutput('s1', 'data'), returnsNormally);
  });

  test('stopRecording returns null when not recording', () async {
    final result = await service.stopRecording('s1');
    expect(result, isNull);
  });

  test('onShellClosed stops active recording', () async {
    final path = '${tmpDir.path}/test3.cast';
    await service.startRecording('s1', filePath: path, width: 80, height: 24, title: 't');
    expect(service.isRecording('s1'), isTrue);
    service.onShellClosed('s1');
    await Future.delayed(const Duration(milliseconds: 50));
    expect(service.isRecording('s1'), isFalse);
  });

  group('redaction', () {
    // Events only (header line skipped). Always stopRecording before calling
    // this — Windows locks the open file, which breaks the read and tearDown.
    Future<List<String>> eventsOf(String path) async =>
        (await File(path).readAsLines()).skip(1).toList();

    Future<void> start(RecordingService s, String path,
            {bool redact = true}) =>
        s.startRecording('s1',
            filePath: path, width: 80, height: 24, title: 't', redact: redact);

    test('secret split across two chunks is masked', () async {
      final path = '${tmpDir.path}/r1.cast';
      await start(service, path);
      service.writeOutput('s1', 'export PGPASS');
      service.writeOutput('s1', 'WORD=hunter2\n');
      await service.stopRecording('s1');
      final events = await eventsOf(path);
      expect(events, hasLength(1));
      expect(events.single, contains('[REDACTED]'));
      expect(events.single, isNot(contains('hunter2')));
    });

    test('keystroke echo (one char per chunk) is masked', () async {
      final path = '${tmpDir.path}/r2.cast';
      await start(service, path);
      for (final ch in 'token=abc123\n'.split('')) {
        service.writeOutput('s1', ch);
      }
      await service.stopRecording('s1');
      final events = await eventsOf(path);
      expect(events, hasLength(1));
      expect(events.single, isNot(contains('abc123')));
    });

    test('multi-newline chunk written as one redacted event', () async {
      final path = '${tmpDir.path}/r3.cast';
      await start(service, path);
      service.writeOutput('s1', 'a\npassword=x\nb\n');
      await service.stopRecording('s1');
      final events = await eventsOf(path);
      expect(events, hasLength(1));
      expect(events.single, isNot(contains('password=x')));
    });

    test('partial line flushes redacted after flushDelay', () async {
      final s = RecordingService(flushDelay: const Duration(milliseconds: 20));
      final path = '${tmpDir.path}/r4.cast';
      await start(s, path);
      s.writeOutput('s1', 'secret=abc'); // no newline
      await Future<void>.delayed(const Duration(milliseconds: 500));
      s.writeOutput('s1', 'later\n'); // separate event ⇒ timer fired earlier
      await s.stopRecording('s1');
      final events = await eventsOf(path);
      expect(events, hasLength(2));
      expect(events[0], contains('[REDACTED]'));
      expect(events[1], contains('later'));
      // Timestamps stay non-decreasing across buffered flushes.
      final t0 = (jsonDecode(events[0]) as List).first as num;
      final t1 = (jsonDecode(events[1]) as List).first as num;
      expect(t1, greaterThanOrEqualTo(t0));
    });

    test('stopRecording flushes a pending partial line', () async {
      final path = '${tmpDir.path}/r5.cast';
      await start(service, path);
      service.writeOutput('s1', 'api_key=tail-no-newline');
      await service.stopRecording('s1');
      final events = await eventsOf(path);
      expect(events, hasLength(1));
      expect(events.single, isNot(contains('tail-no-newline')));
    });

    test('redact:false keeps one raw event per chunk (legacy path)', () async {
      final path = '${tmpDir.path}/r6.cast';
      await start(service, path, redact: false);
      service.writeOutput('s1', 'password=plain');
      service.writeOutput('s1', 'second\n');
      await service.stopRecording('s1');
      final events = await eventsOf(path);
      expect(events, hasLength(2));
      expect(events[0], contains('password=plain'));
    });
  });
}
