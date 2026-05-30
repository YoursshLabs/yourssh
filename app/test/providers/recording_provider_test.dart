import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/services/recording_service.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('rp_test');
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  test('isRecording returns false initially', () {
    final provider = RecordingProvider(RecordingService(), getPath: () => tmpDir.path);
    expect(provider.isRecording('s1'), isFalse);
  });

  test('refreshLibrary finds .cast files', () async {
    final hostDir = Directory('${tmpDir.path}/ubuntu@prod')..createSync();
    File('${hostDir.path}/session_2026-05-30_10-00-00.cast').writeAsStringSync(
      '{"version":2,"width":80,"height":24,"timestamp":1}\n',
    );
    final provider = RecordingProvider(RecordingService(), getPath: () => tmpDir.path);
    await provider.refreshLibrary();
    expect(provider.recordings.length, 1);
    expect(provider.recordings.first.hostTitle, 'ubuntu@prod');
  });

  test('deleteRecording removes file and entry', () async {
    final hostDir = Directory('${tmpDir.path}/ubuntu@prod')..createSync();
    final f = File('${hostDir.path}/session_2026-05-30_10-00-00.cast')
      ..writeAsStringSync('{"version":2}\n');
    final provider = RecordingProvider(RecordingService(), getPath: () => tmpDir.path);
    await provider.refreshLibrary();
    expect(provider.recordings.length, 1);
    await provider.deleteRecording(f.path);
    expect(provider.recordings.isEmpty, isTrue);
    expect(f.existsSync(), isFalse);
  });
}
