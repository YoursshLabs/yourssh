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
}
