import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/local_session.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/services/recording_service.dart';

class _CapturingService extends RecordingService {
  bool? capturedRedact;

  @override
  Future<void> startRecording(
    String sessionId, {
    required String filePath,
    required int width,
    required int height,
    required String title,
    bool redact = false,
  }) async {
    capturedRedact = redact;
  }
}

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

  test('local session records into local/ folder', () async {
    final provider =
        RecordingProvider(RecordingService(), getPath: () => tmpDir.path);
    final session = LocalSession(terminal: Terminal());

    await provider.startRecording(session);
    expect(provider.isRecording(session.id), isTrue);

    final files = tmpDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.cast'))
        .toList();
    expect(files, hasLength(1));
    expect(
      files.single.path,
      contains('${Platform.pathSeparator}local${Platform.pathSeparator}'),
    );

    await provider.stopRecording(session.id);
    expect(provider.isRecording(session.id), isFalse);
  });

  test('shell exit (onShellClosed) clears the provider recording state',
      () async {
    final service = RecordingService();
    final provider = RecordingProvider(service, getPath: () => tmpDir.path);
    final session = LocalSession(terminal: Terminal());

    await provider.startRecording(session);
    expect(provider.isRecording(session.id), isTrue);

    var notified = false;
    provider.addListener(() => notified = true);

    // Simulates the PTY/shell dying: SshService and LocalShellService call
    // this directly on the service, bypassing the provider.
    service.onShellClosed(session.id);
    await Future<void>.delayed(Duration.zero);

    expect(provider.isRecording(session.id), isFalse,
        reason: 'REC indicator must not stay red after the shell closed');
    expect(notified, isTrue);
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
    // Delete via the entry's own path (what the UI passes) — on Windows the
    // listed path uses '\' while f.path was built with '/'.
    await provider.deleteRecording(provider.recordings.first.filePath);
    expect(provider.recordings.isEmpty, isTrue);
    expect(f.existsSync(), isFalse);
  });

  test('startRecording failure invokes onStartFailed callback', () async {
    // Pin the round-3 fix: when the recording service throws (here because the
    // path is unwritable), the provider must surface it via onStartFailed
    // instead of silently dropping the session — otherwise `autoRecord` looks
    // like it disabled itself.
    final unwritable = Platform.isWindows ? 'Z:\\\\nowhere\\\\impossible' : '/dev/null/impossible';
    final provider = RecordingProvider(
      RecordingService(),
      getPath: () => unwritable,
    );
    Object? capturedError;
    provider.onStartFailed = (_, error) => capturedError = error;

    final session = SshSession(
      host: Host(label: 'h', host: 'h', username: 'u'),
    );
    await provider.startRecording(session);

    expect(provider.isRecording(session.id), isFalse);
    expect(capturedError, isNotNull);
  });

  test('redactionPolicy result is passed to the service', () async {
    final service = _CapturingService();
    final provider = RecordingProvider(service, getPath: () => tmpDir.path);
    provider.redactionPolicy = (_) => true;

    await provider.startRecording(LocalSession(terminal: Terminal()));
    expect(service.capturedRedact, isTrue);
  });

  test('null redactionPolicy records without redaction', () async {
    final service = _CapturingService();
    final provider = RecordingProvider(service, getPath: () => tmpDir.path);

    await provider.startRecording(LocalSession(terminal: Terminal()));
    expect(service.capturedRedact, isFalse);
  });
}
