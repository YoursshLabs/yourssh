import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/bulk_result.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/bulk_action_service.dart';

List<Host> _hosts(int n) =>
    [for (var i = 0; i < n; i++) Host(label: 'h$i', host: 'h$i.x', username: 'u')];

({String stdout, String stderr, int exitCode}) _okResult() =>
    (stdout: 'ok', stderr: '', exitCode: 0);

void main() {
  group('runCommand', () {
    test('collects a success result per host', () async {
      final service = BulkActionService(
        exec: (host, cmd) async =>
            (stdout: 'out-${host.label}', stderr: '', exitCode: 0),
      );
      final updates = <BulkHostResult>[];
      await service.runCommand(_hosts(3), 'uptime',
          onUpdate: updates.add, token: BulkCancelToken());
      final done =
          updates.where((r) => r.status == BulkHostStatus.success).toList();
      expect(done, hasLength(3));
      expect(done.map((r) => r.stdout).toSet(),
          {'out-h0', 'out-h1', 'out-h2'});
      expect(done.every((r) => r.elapsed != null), isTrue);
      // every host also emitted a running update first
      expect(updates.where((r) => r.status == BulkHostStatus.running),
          hasLength(3));
    });

    test('caps concurrency', () async {
      var inFlight = 0, maxInFlight = 0;
      final allThreeIn = Completer<void>();
      final service = BulkActionService(exec: (host, cmd) async {
        inFlight++;
        maxInFlight = max(maxInFlight, inFlight);
        if (inFlight == 3 && !allThreeIn.isCompleted) allThreeIn.complete();
        await allThreeIn.future;
        inFlight--;
        return _okResult();
      });
      await service.runCommand(_hosts(10), 'x',
          onUpdate: (_) {}, token: BulkCancelToken(), maxConcurrent: 3);
      expect(maxInFlight, 3);
    });

    test('one throwing host does not affect the others', () async {
      final service = BulkActionService(exec: (host, cmd) async {
        if (host.label == 'h1') throw Exception('auth failed');
        return _okResult();
      });
      final byLabel = <String, BulkHostStatus>{};
      await service.runCommand(_hosts(3), 'x',
          onUpdate: (r) => byLabel[r.host.label] = r.status,
          token: BulkCancelToken());
      expect(byLabel['h0'], BulkHostStatus.success);
      expect(byLabel['h1'], BulkHostStatus.failed);
      expect(byLabel['h2'], BulkHostStatus.success);
    });

    test('failed result carries the error message', () async {
      final service = BulkActionService(
          exec: (host, cmd) async => throw Exception('boom'));
      BulkHostResult? result;
      await service.runCommand(_hosts(1), 'x',
          onUpdate: (r) {
            if (r.status == BulkHostStatus.failed) result = r;
          },
          token: BulkCancelToken());
      expect(result!.error, contains('boom'));
    });

    test('cancel marks queued hosts cancelled, in-flight completes', () async {
      final token = BulkCancelToken();
      final service = BulkActionService(exec: (host, cmd) async {
        token.cancel(); // fires while the first host is in flight
        return _okResult();
      });
      final byLabel = <String, BulkHostStatus>{};
      await service.runCommand(_hosts(3), 'x',
          onUpdate: (r) => byLabel[r.host.label] = r.status,
          token: token,
          maxConcurrent: 1);
      expect(byLabel['h0'], BulkHostStatus.success);
      expect(byLabel['h1'], BulkHostStatus.cancelled);
      expect(byLabel['h2'], BulkHostStatus.cancelled);
    });

    test('per-host timeout produces failed', () async {
      final service = BulkActionService(
          exec: (host, cmd) => Completer<
                  ({String stdout, String stderr, int exitCode})>()
              .future); // never completes
      BulkHostResult? result;
      await service.runCommand(_hosts(1), 'x',
          onUpdate: (r) {
            if (r.status == BulkHostStatus.failed) result = r;
          },
          token: BulkCancelToken(),
          perHostTimeout: const Duration(milliseconds: 20));
      expect(result!.error, contains('Timed out'));
    });

    test('throws StateError when exec is not wired', () {
      expect(
        () => BulkActionService().runCommand(_hosts(1), 'x',
            onUpdate: (_) {}, token: BulkCancelToken()),
        throwsStateError,
      );
    });
  });

  group('ensureRemoteDir', () {
    test('creates each path segment, root skipped', () async {
      final calls = <String>[];
      await BulkActionService.ensureRemoteDir((path) async => calls.add(path),
          '/opt/app/conf');
      expect(calls, ['/opt', '/opt/app', '/opt/app/conf']);
    });

    test('mkdir errors are swallowed', () async {
      await BulkActionService.ensureRemoteDir(
          (path) async => throw Exception('exists'), '/opt/app');
      // no throw = pass
    });
  });

  group('pushFiles', () {
    const file = BulkPushSource(path: '/tmp/x.txt', isDirectory: false, bytes: 10);
    const dir = BulkPushSource(path: '/tmp/conf', isDirectory: true, bytes: 3);

    BulkActionService buildService(List<String> log,
        {bool failUpload = false}) {
      return BulkActionService(
        uploadFile: (host, local, remote, {onProgress}) async {
          if (failUpload) throw Exception('upload boom');
          log.add('${host.label}:file:$local->$remote');
          onProgress?.call(5, 10);
          onProgress?.call(10, 10);
        },
        uploadDirectory: ({
          required host,
          required localDir,
          required remoteDir,
          required onProgress,
          required isCancelled,
        }) async {
          log.add('${host.label}:dir:$localDir->$remoteDir');
          onProgress('$localDir/a.yml', 3, 3);
        },
        mkdir: (host, path) async => log.add('${host.label}:mkdir:$path'),
      );
    }

    test('routes files and directories, mkdir runs first', () async {
      final log = <String>[];
      final updates = <BulkHostResult>[];
      await buildService(log).pushFiles(_hosts(1), [file, dir], '/etc/app',
          onUpdate: updates.add, token: BulkCancelToken());
      expect(log, [
        'h0:mkdir:/etc',
        'h0:mkdir:/etc/app',
        'h0:file:/tmp/x.txt->/etc/app/x.txt',
        'h0:dir:/tmp/conf->/etc/app/conf',
      ]);
      final done = updates.last;
      expect(done.status, BulkHostStatus.success);
      expect(done.bytesTransferred, 13);
      expect(done.totalBytes, 13);
    });

    test('progress aggregates across sources', () async {
      final log = <String>[];
      final seen = <int>[];
      await buildService(log).pushFiles(_hosts(1), [file, dir], '/etc/app',
          onUpdate: (r) => seen.add(r.bytesTransferred),
          token: BulkCancelToken());
      // 0 (running), 5, 10 (file), 13 (dir file done), 13 (final)
      expect(seen, containsAllInOrder([0, 5, 10, 13]));
    });

    test('a failing host does not stop the others', () async {
      final byLabel = <String, BulkHostStatus>{};
      final service = BulkActionService(
        uploadFile: (host, local, remote, {onProgress}) async {
          if (host.label == 'h0') throw Exception('disk full');
        },
        uploadDirectory: ({
          required host,
          required localDir,
          required remoteDir,
          required onProgress,
          required isCancelled,
        }) async {},
        mkdir: (host, path) async {},
      );
      await service.pushFiles(_hosts(2), [file], '/etc',
          onUpdate: (r) => byLabel[r.host.label] = r.status,
          token: BulkCancelToken());
      expect(byLabel['h0'], BulkHostStatus.failed);
      expect(byLabel['h1'], BulkHostStatus.success);
    });

    test('cancel marks queued hosts cancelled', () async {
      final token = BulkCancelToken();
      final byLabel = <String, BulkHostStatus>{};
      final service = BulkActionService(
        uploadFile: (host, local, remote, {onProgress}) async => token.cancel(),
        uploadDirectory: ({
          required host,
          required localDir,
          required remoteDir,
          required onProgress,
          required isCancelled,
        }) async {},
        mkdir: (host, path) async {},
      );
      await service.pushFiles(_hosts(3), [file], '/etc',
          onUpdate: (r) => byLabel[r.host.label] = r.status,
          token: token,
          maxConcurrent: 1);
      expect(byLabel['h1'], BulkHostStatus.cancelled);
      expect(byLabel['h2'], BulkHostStatus.cancelled);
    });

    test('cancel during ensureRemoteDir with no sources reports cancelled',
        () async {
      final token = BulkCancelToken();
      final service = BulkActionService(
        uploadFile: (host, local, remote, {onProgress}) async {},
        uploadDirectory: ({
          required host,
          required localDir,
          required remoteDir,
          required onProgress,
          required isCancelled,
        }) async {},
        mkdir: (host, path) async => token.cancel(),
      );
      final statuses = <BulkHostStatus>[];
      await service.pushFiles(_hosts(1), const [], '/etc',
          onUpdate: (r) => statuses.add(r.status), token: token);
      expect(statuses.last, BulkHostStatus.cancelled);
    });

    test('throws StateError when upload fns are not wired', () {
      expect(
        () => BulkActionService().pushFiles(_hosts(1), [file], '/etc',
            onUpdate: (_) {}, token: BulkCancelToken()),
        throwsStateError,
      );
    });
  });

  group('resolveSources', () {
    test('sizes files and walks directories', () async {
      final tmp = await Directory.systemTemp.createTemp('bulk_test');
      addTearDown(() => tmp.delete(recursive: true));
      final f = File('${tmp.path}/a.txt')..writeAsStringSync('12345');
      final sub = Directory('${tmp.path}/sub')..createSync();
      File('${sub.path}/b.txt').writeAsStringSync('123');

      final sources =
          await BulkActionService.resolveSources([f.path, sub.path]);
      expect(sources[0].isDirectory, isFalse);
      expect(sources[0].bytes, 5);
      expect(sources[1].isDirectory, isTrue);
      expect(sources[1].bytes, 3);
    });
  });
}
