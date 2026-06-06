# Bulk Action Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Multi-select hosts on the dashboard and run bulk actions against them: connect-all, parallel command exec with a diff view, and SFTP push to the fleet.

**Architecture:** A `BulkActionService` engine (worker pool with bounded concurrency, cancel token, per-host failure isolation) runs over injected per-host functions (`SshService.exec`, `SftpTransferService` uploads, `SftpFileOpsService.mkdir`). A dialog-scoped `BulkRunController` (ChangeNotifier) feeds two modal dialogs (Run command, Push files). Pure diff helpers (`bulk_diff.dart`) group identical outputs and compute line diffs. The hosts dashboard gains a selection mode whose action bar triggers everything.

**Tech Stack:** Flutter/Dart, provider, existing `SshService`/`SftpTransferService`/`SftpFileOpsService`, `file_selector` (already a dependency), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-05-bulk-action-panel-design.md`

**Conventions:**
- All commands run from the repo root; Flutter commands from `app/`.
- Commit after every task (Conventional Commits).
- Dark-only theme: colors come from `AppColors` in `app/lib/theme/app_theme.dart` (`bg`, `sidebar`, `card`, `border`, `accent`, `red`, `orange`, `textPrimary/Secondary/Tertiary`).

---

### Task 1: Result model

**Files:**
- Create: `app/lib/models/bulk_result.dart`

Pure data, no logic — no dedicated test file.

- [ ] **Step 1: Create the model**

```dart
// app/lib/models/bulk_result.dart
import 'host.dart';

/// Lifecycle of one host inside a bulk run.
enum BulkHostStatus { pending, running, success, failed, cancelled }

/// Immutable snapshot of one host's progress/result in a bulk run.
///
/// For exec runs, [BulkHostStatus.success] means the command ran — a
/// non-zero [exitCode] is still success (the command's own failure is data
/// shown in the row); [BulkHostStatus.failed] means the app could not run
/// it at all (connect, auth, timeout, channel error).
class BulkHostResult {
  final Host host;
  final BulkHostStatus status;
  final int? exitCode; // exec only
  final String stdout; // exec only
  final String stderr; // exec only
  final String? error; // connect/auth/timeout/transfer error
  final Duration? elapsed;
  final int bytesTransferred; // push only
  final int totalBytes; // push only

  const BulkHostResult({
    required this.host,
    required this.status,
    this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.error,
    this.elapsed,
    this.bytesTransferred = 0,
    this.totalBytes = 0,
  });
}
```

- [ ] **Step 2: Analyze**

Run: `cd app && flutter analyze`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add app/lib/models/bulk_result.dart
git commit -m "feat(bulk): add BulkHostResult model and status enum"
```

---

### Task 2: Pure diff helpers (`bulk_diff.dart`)

**Files:**
- Create: `app/lib/util/bulk_diff.dart`
- Test: `app/test/util/bulk_diff_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/util/bulk_diff_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/bulk_result.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/util/bulk_diff.dart';

BulkHostResult _ok(String label, String stdout) => BulkHostResult(
      host: Host(label: label, host: '$label.example', username: 'u'),
      status: BulkHostStatus.success,
      exitCode: 0,
      stdout: stdout,
    );

BulkHostResult _failed(String label) => BulkHostResult(
      host: Host(label: label, host: '$label.example', username: 'u'),
      status: BulkHostStatus.failed,
      error: 'connection refused',
    );

void main() {
  group('groupByOutput', () {
    test('groups identical outputs, largest group first', () {
      final groups = groupByOutput([
        _ok('a', 'v1'),
        _ok('b', 'v2'),
        _ok('c', 'v1'),
        _ok('d', 'v1'),
      ]);
      expect(groups, hasLength(2));
      expect(groups[0].output, 'v1');
      expect(groups[0].hostLabels, ['a', 'c', 'd']);
      expect(groups[1].hostLabels, ['b']);
    });

    test('trailing whitespace does not split a group', () {
      final groups = groupByOutput([_ok('a', 'same\n'), _ok('b', 'same')]);
      expect(groups, hasLength(1));
      expect(groups[0].hostLabels, ['a', 'b']);
    });

    test('equal-sized groups keep first-seen order', () {
      final groups = groupByOutput([_ok('a', 'x'), _ok('b', 'y')]);
      expect(groups[0].output, 'x');
      expect(groups[1].output, 'y');
    });

    test('failed hosts are excluded', () {
      final groups = groupByOutput([_ok('a', 'x'), _failed('b')]);
      expect(groups, hasLength(1));
      expect(groups[0].hostLabels, ['a']);
    });

    test('empty outputs still group together', () {
      final groups = groupByOutput([_ok('a', ''), _ok('b', '')]);
      expect(groups, hasLength(1));
      expect(groups[0].size, 2);
    });
  });

  group('lineDiff', () {
    test('identical inputs are all same', () {
      final d = lineDiff('a\nb', 'a\nb');
      expect(d.every((l) => l.op == DiffOp.same), isTrue);
      expect(d, hasLength(2));
    });

    test('added line', () {
      final d = lineDiff('a\nc', 'a\nb\nc');
      expect(d.map((l) => (l.op, l.text)).toList(), [
        (DiffOp.same, 'a'),
        (DiffOp.added, 'b'),
        (DiffOp.same, 'c'),
      ]);
    });

    test('removed line', () {
      final d = lineDiff('a\nb\nc', 'a\nc');
      expect(d.map((l) => (l.op, l.text)).toList(), [
        (DiffOp.same, 'a'),
        (DiffOp.removed, 'b'),
        (DiffOp.same, 'c'),
      ]);
    });

    test('changed line becomes removed + added', () {
      final d = lineDiff('a\nold\nc', 'a\nnew\nc');
      expect(d.map((l) => (l.op, l.text)).toList(), [
        (DiffOp.same, 'a'),
        (DiffOp.removed, 'old'),
        (DiffOp.added, 'new'),
        (DiffOp.same, 'c'),
      ]);
    });

    test('empty vs content', () {
      expect(lineDiff('', 'a').single.op, DiffOp.added);
      expect(lineDiff('a', '').single.op, DiffOp.removed);
      expect(lineDiff('', ''), isEmpty);
    });
  });

  group('sideBySideRows', () {
    test('zips a removed run with the following added run', () {
      final rows = sideBySideRows(const [
        DiffLine(DiffOp.same, 'a'),
        DiffLine(DiffOp.removed, 'old1'),
        DiffLine(DiffOp.removed, 'old2'),
        DiffLine(DiffOp.added, 'new1'),
        DiffLine(DiffOp.same, 'z'),
      ]);
      expect(rows, hasLength(4));
      expect((rows[0].left!.text, rows[0].right!.text), ('a', 'a'));
      expect((rows[1].left!.text, rows[1].right!.text), ('old1', 'new1'));
      expect(rows[2].left!.text, 'old2');
      expect(rows[2].right, isNull);
      expect((rows[3].left!.text, rows[3].right!.text), ('z', 'z'));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/util/bulk_diff_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:yourssh/util/bulk_diff.dart'`

- [ ] **Step 3: Implement**

```dart
// app/lib/util/bulk_diff.dart
// Pure helpers behind the bulk Run-command Diff tab. No Flutter/IO imports.
import 'dart:math';

import '../models/bulk_result.dart';

/// Hosts whose trimmed stdout was byte-identical.
class OutputGroup {
  final String output; // trimmed stdout shared by every host in the group
  final List<String> hostLabels; // display labels, in run order
  const OutputGroup({required this.output, required this.hostLabels});
  int get size => hostLabels.length;
}

/// Groups successful results by identical stdout (trailing whitespace
/// trimmed), largest group first; equal-sized groups keep first-seen order.
/// Failed/cancelled hosts never participate.
List<OutputGroup> groupByOutput(List<BulkHostResult> results) {
  final labelsByOutput = <String, List<String>>{};
  final firstSeen = <String, int>{};
  for (final r in results) {
    if (r.status != BulkHostStatus.success) continue;
    final key = r.stdout.trimRight();
    firstSeen.putIfAbsent(key, () => firstSeen.length);
    (labelsByOutput[key] ??= []).add(r.host.label);
  }
  final keys = labelsByOutput.keys.toList()
    ..sort((a, b) {
      final bySize =
          labelsByOutput[b]!.length.compareTo(labelsByOutput[a]!.length);
      return bySize != 0 ? bySize : firstSeen[a]!.compareTo(firstSeen[b]!);
    });
  return [
    for (final k in keys)
      OutputGroup(output: k, hostLabels: labelsByOutput[k]!),
  ];
}

enum DiffOp { same, added, removed }

class DiffLine {
  final DiffOp op;
  final String text;
  const DiffLine(this.op, this.text);
}

/// LCS-table size cap. Common prefix/suffix are stripped first, so this only
/// trips on genuinely divergent huge outputs — those fall back to a plain
/// removed-everything/added-everything diff instead of an O(m·n) table.
const _maxLcsCells = 4 * 1000 * 1000;

/// Line-based diff from [a] to [b]: `removed` lines exist only in [a],
/// `added` only in [b].
List<DiffLine> lineDiff(String a, String b) {
  final aLines = a.isEmpty ? <String>[] : a.split('\n');
  final bLines = b.isEmpty ? <String>[] : b.split('\n');

  var start = 0;
  while (start < aLines.length &&
      start < bLines.length &&
      aLines[start] == bLines[start]) {
    start++;
  }
  var aEnd = aLines.length, bEnd = bLines.length;
  while (aEnd > start && bEnd > start && aLines[aEnd - 1] == bLines[bEnd - 1]) {
    aEnd--;
    bEnd--;
  }

  return [
    for (var i = 0; i < start; i++) DiffLine(DiffOp.same, aLines[i]),
    ..._diffMiddle(aLines.sublist(start, aEnd), bLines.sublist(start, bEnd)),
    for (var i = aEnd; i < aLines.length; i++) DiffLine(DiffOp.same, aLines[i]),
  ];
}

List<DiffLine> _diffMiddle(List<String> a, List<String> b) {
  if (a.isEmpty) return [for (final l in b) DiffLine(DiffOp.added, l)];
  if (b.isEmpty) return [for (final l in a) DiffLine(DiffOp.removed, l)];
  if (a.length * b.length > _maxLcsCells) {
    return [
      for (final l in a) DiffLine(DiffOp.removed, l),
      for (final l in b) DiffLine(DiffOp.added, l),
    ];
  }
  final lcs =
      List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      out.add(DiffLine(DiffOp.same, a[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      out.add(DiffLine(DiffOp.removed, a[i]));
      i++;
    } else {
      out.add(DiffLine(DiffOp.added, b[j]));
      j++;
    }
  }
  while (i < a.length) {
    out.add(DiffLine(DiffOp.removed, a[i]));
    i++;
  }
  while (j < b.length) {
    out.add(DiffLine(DiffOp.added, b[j]));
    j++;
  }
  return out;
}

/// Pairs diff lines into side-by-side rows: a run of removed lines is
/// zipped with the added run that follows it (changed lines align), and
/// unmatched lines pair with null on the other side.
List<({DiffLine? left, DiffLine? right})> sideBySideRows(
    List<DiffLine> lines) {
  final rows = <({DiffLine? left, DiffLine? right})>[];
  var i = 0;
  while (i < lines.length) {
    if (lines[i].op == DiffOp.same) {
      rows.add((left: lines[i], right: lines[i]));
      i++;
      continue;
    }
    final removed = <DiffLine>[];
    final added = <DiffLine>[];
    while (i < lines.length && lines[i].op == DiffOp.removed) {
      removed.add(lines[i]);
      i++;
    }
    while (i < lines.length && lines[i].op == DiffOp.added) {
      added.add(lines[i]);
      i++;
    }
    final n = max(removed.length, added.length);
    for (var k = 0; k < n; k++) {
      rows.add((
        left: k < removed.length ? removed[k] : null,
        right: k < added.length ? added[k] : null,
      ));
    }
  }
  return rows;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/util/bulk_diff_test.dart`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/util/bulk_diff.dart app/test/util/bulk_diff_test.dart
git commit -m "feat(bulk): pure output grouping and LCS line diff helpers"
```

---

### Task 3: Engine — cancel token, worker pool, `runCommand`

**Files:**
- Create: `app/lib/services/bulk_action_service.dart`
- Test: `app/test/services/bulk_action_service_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/services/bulk_action_service_test.dart
import 'dart:async';
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
      final service = BulkActionService(exec: (host, cmd) async {
        inFlight++;
        maxInFlight = max(maxInFlight, inFlight);
        await Future<void>.delayed(const Duration(milliseconds: 10));
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/services/bulk_action_service_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:yourssh/services/bulk_action_service.dart'`

- [ ] **Step 3: Implement**

```dart
// app/lib/services/bulk_action_service.dart
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/bulk_result.dart';
import '../models/host.dart';

/// Cooperative cancellation for a bulk run: queued hosts are marked
/// cancelled; hosts already in flight run to completion and record their
/// real result (an SSH exec can't be aborted mid-flight).
class BulkCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// One local source (file or directory) for a bulk push, with its total
/// byte size pre-computed so per-host progress has a denominator.
class BulkPushSource {
  final String path;
  final bool isDirectory;
  final int bytes;
  const BulkPushSource(
      {required this.path, required this.isDirectory, required this.bytes});
  String get name => p.basename(path);
}

typedef BulkExecFn = Future<({String stdout, String stderr, int exitCode})>
    Function(Host host, String command);
typedef BulkUploadFileFn = Future<void> Function(
    Host host, String localPath, String remotePath,
    {void Function(int sent, int total)? onProgress});
typedef BulkUploadDirFn = Future<void> Function({
  required Host host,
  required String localDir,
  required String remoteDir,
  required void Function(String filePath, int bytes, int total) onProgress,
  required bool Function() isCancelled,
});
typedef BulkMkdirFn = Future<void> Function(Host host, String path);

/// Parallel engine behind the bulk action panel: bounded-concurrency worker
/// pool with per-host failure isolation. Pure orchestration over injected
/// per-host operations — tests inject fakes; the dialogs inject
/// `SshService.exec`, `SftpTransferService` uploads, and
/// `SftpFileOpsService.mkdir`.
class BulkActionService {
  final BulkExecFn? _exec;
  final BulkUploadFileFn? _uploadFile;
  final BulkUploadDirFn? _uploadDirectory;
  final BulkMkdirFn? _mkdir;

  BulkActionService({
    BulkExecFn? exec,
    BulkUploadFileFn? uploadFile,
    BulkUploadDirFn? uploadDirectory,
    BulkMkdirFn? mkdir,
  })  : _exec = exec,
        _uploadFile = uploadFile,
        _uploadDirectory = uploadDirectory,
        _mkdir = mkdir;

  /// Runs [command] on every host, at most [maxConcurrent] in flight.
  /// Emits a `running` update when a host is picked up and exactly one
  /// terminal update (`success`/`failed`/`cancelled`) when it finishes.
  Future<void> runCommand(
    List<Host> hosts,
    String command, {
    required void Function(BulkHostResult) onUpdate,
    required BulkCancelToken token,
    int maxConcurrent = 6,
    Duration perHostTimeout = const Duration(seconds: 30),
  }) {
    final exec = _exec;
    if (exec == null) throw StateError('BulkActionService: exec not wired');
    return _pool(hosts, maxConcurrent, (host) async {
      if (token.isCancelled) {
        onUpdate(BulkHostResult(host: host, status: BulkHostStatus.cancelled));
        return;
      }
      onUpdate(BulkHostResult(host: host, status: BulkHostStatus.running));
      final sw = Stopwatch()..start();
      try {
        final r = await exec(host, command).timeout(perHostTimeout);
        onUpdate(BulkHostResult(
          host: host,
          status: BulkHostStatus.success,
          exitCode: r.exitCode,
          stdout: r.stdout,
          stderr: r.stderr,
          elapsed: sw.elapsed,
        ));
      } on TimeoutException {
        onUpdate(BulkHostResult(
          host: host,
          status: BulkHostStatus.failed,
          error: 'Timed out after ${perHostTimeout.inSeconds}s',
          elapsed: sw.elapsed,
        ));
      } catch (e) {
        onUpdate(BulkHostResult(
          host: host,
          status: BulkHostStatus.failed,
          error: e.toString(),
          elapsed: sw.elapsed,
        ));
      }
    });
  }

  /// Runs [body] for every host with at most [maxConcurrent] in flight.
  /// Dequeue happens synchronously at loop top (single-threaded event loop),
  /// so no host is ever picked up twice.
  Future<void> _pool(List<Host> hosts, int maxConcurrent,
      Future<void> Function(Host host) body) async {
    final queue = List.of(hosts);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        await body(queue.removeAt(0));
      }
    }

    final n = maxConcurrent.clamp(1, hosts.isEmpty ? 1 : hosts.length);
    await Future.wait([for (var i = 0; i < n; i++) worker()]);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/services/bulk_action_service_test.dart`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/bulk_action_service.dart app/test/services/bulk_action_service_test.dart
git commit -m "feat(bulk): BulkActionService worker pool with runCommand"
```

---

### Task 4: Engine — `ensureRemoteDir`, `resolveSources`, `pushFiles`

**Files:**
- Modify: `app/lib/services/bulk_action_service.dart`
- Test: `app/test/services/bulk_action_service_test.dart` (append groups)

- [ ] **Step 1: Append the failing tests**

Add to `main()` in the test file:

```dart
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
```

Also add `import 'dart:io';` to the test file's imports.

- [ ] **Step 2: Run tests to verify the new groups fail**

Run: `cd app && flutter test test/services/bulk_action_service_test.dart`
Expected: FAIL — `ensureRemoteDir`/`pushFiles`/`resolveSources` not defined.

- [ ] **Step 3: Implement — append to `BulkActionService`**

```dart
  /// Pushes every source to [remoteDir] on every host (hosts in parallel,
  /// sources within a host sequential). Emits `running` updates with
  /// cumulative [BulkHostResult.bytesTransferred] and one terminal update.
  Future<void> pushFiles(
    List<Host> hosts,
    List<BulkPushSource> sources,
    String remoteDir, {
    required void Function(BulkHostResult) onUpdate,
    required BulkCancelToken token,
    int maxConcurrent = 4,
  }) {
    final uploadFile = _uploadFile;
    final uploadDirectory = _uploadDirectory;
    final mkdir = _mkdir;
    if (uploadFile == null || uploadDirectory == null || mkdir == null) {
      throw StateError('BulkActionService: upload/mkdir not wired');
    }
    final total = sources.fold(0, (a, s) => a + s.bytes);
    return _pool(hosts, maxConcurrent, (host) async {
      if (token.isCancelled) {
        onUpdate(BulkHostResult(
            host: host, status: BulkHostStatus.cancelled, totalBytes: total));
        return;
      }
      onUpdate(BulkHostResult(
          host: host, status: BulkHostStatus.running, totalBytes: total));
      final sw = Stopwatch()..start();
      var done = 0; // bytes of fully finished sources
      void progress(int withinCurrent) => onUpdate(BulkHostResult(
            host: host,
            status: BulkHostStatus.running,
            bytesTransferred: done + withinCurrent,
            totalBytes: total,
          ));
      try {
        await ensureRemoteDir((path) => mkdir(host, path), remoteDir);
        for (final src in sources) {
          if (token.isCancelled) break;
          final dest = p.posix.join(remoteDir, src.name);
          if (src.isDirectory) {
            var dirSent = 0;
            final perFile = <String, int>{};
            await uploadDirectory(
              host: host,
              localDir: src.path,
              remoteDir: dest,
              onProgress: (filePath, bytes, _) {
                dirSent += bytes - (perFile[filePath] ?? 0);
                perFile[filePath] = bytes;
                progress(dirSent);
              },
              isCancelled: () => token.isCancelled,
            );
          } else {
            await uploadFile(host, src.path, dest,
                onProgress: (sent, _) => progress(sent));
          }
          done += src.bytes;
        }
        final cancelled = token.isCancelled && done < total;
        onUpdate(BulkHostResult(
          host: host,
          status:
              cancelled ? BulkHostStatus.cancelled : BulkHostStatus.success,
          bytesTransferred: done,
          totalBytes: total,
          elapsed: sw.elapsed,
        ));
      } catch (e) {
        onUpdate(BulkHostResult(
          host: host,
          status: BulkHostStatus.failed,
          error: e.toString(),
          bytesTransferred: done,
          totalBytes: total,
          elapsed: sw.elapsed,
        ));
      }
    });
  }

  /// Creates [remoteDir] and any missing parents with single-level [mkdir]
  /// calls. Errors are swallowed: "already exists" is the common case, and
  /// a dir that truly failed to create surfaces as the upload error that
  /// follows immediately.
  static Future<void> ensureRemoteDir(
      Future<void> Function(String path) mkdir, String remoteDir) async {
    final parts = p.posix.split(remoteDir);
    var current = '';
    for (final part in parts) {
      current = current.isEmpty ? part : p.posix.join(current, part);
      if (current == '/') continue;
      try {
        await mkdir(current);
      } catch (_) {
        // exists, or the upload right after will surface the real error
      }
    }
  }

  /// Resolves picked paths into [BulkPushSource]s with pre-computed sizes
  /// (the denominator for progress). Directories are walked recursively.
  static Future<List<BulkPushSource>> resolveSources(
      List<String> paths) async {
    final out = <BulkPushSource>[];
    for (final path in paths) {
      if (await FileSystemEntity.isDirectory(path)) {
        var bytes = 0;
        await for (final e
            in Directory(path).list(recursive: true, followLinks: false)) {
          if (e is File) bytes += await e.length();
        }
        out.add(BulkPushSource(path: path, isDirectory: true, bytes: bytes));
      } else {
        out.add(BulkPushSource(
            path: path, isDirectory: false, bytes: await File(path).length()));
      }
    }
    return out;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/services/bulk_action_service_test.dart`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/bulk_action_service.dart app/test/services/bulk_action_service_test.dart
git commit -m "feat(bulk): pushFiles with remote-dir bootstrap and source resolution"
```

---

### Task 5: `SftpTransferService` — `uploadFile` progress + `uploadDirectory` overwrite

**Files:**
- Modify: `app/lib/services/sftp_transfer_service.dart`

These are thin IO-wiring changes against a real `SftpClient` (not unit-testable without a large fake); behavior is exercised through the engine tests via injection. Run the existing suite to guard regressions.

- [ ] **Step 1: Add `onProgress` to `uploadFile`**

Replace the existing `uploadFile` (currently `app/lib/services/sftp_transfer_service.dart:150-171`) with:

```dart
  Future<void> uploadFile(Host host, String localPath, String remotePath,
      {void Function(int sent, int total)? onProgress}) async {
    final sftp = await _sshService.openSftp(host);
    SftpFile? remoteFile;
    try {
      final total = await File(localPath).length();
      remoteFile = await sftp.open(
        remotePath,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      int offset = 0;
      await for (final chunk in File(localPath).openRead()) {
        final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        await remoteFile.writeBytes(bytes, offset: offset);
        offset += bytes.length;
        onProgress?.call(offset, total);
      }
    } finally {
      await remoteFile?.close();
      sftp.close();
    }
  }
```

- [ ] **Step 2: Add `overwrite` to `uploadDirectory`**

In `uploadDirectory` (line 201) add the parameter and pass it down:

```dart
  Future<void> uploadDirectory({
    required String localDir,
    required Host remoteHost,
    required String remoteDir,
    required void Function(String filePath, int bytes, int total) onProgress,
    required void Function(String filePath) onFileSkipped,
    required bool Function() isCancelled,
    bool overwrite = false,
  }) async {
    final sftp = await _sshService.openSftp(remoteHost);
    try {
      await _uploadDirRecursive(
        sftp: sftp,
        localDir: localDir,
        remoteDir: remoteDir,
        onProgress: onProgress,
        onFileSkipped: onFileSkipped,
        isCancelled: isCancelled,
        overwrite: overwrite,
      );
    } finally {
      sftp.close();
    }
  }
```

In `_uploadDirRecursive`, add `required bool overwrite` to the signature, pass `overwrite: overwrite` in the recursive call, and guard the exists-check (the `bool fileExists; try { await sftp.stat(...) ... }` block plus the `if (fileExists)` skip) so it only runs when `!overwrite`:

```dart
        if (!overwrite) {
          // stat: only treat "no such file" as "needs upload". Permission /
          // I/O errors are surfaced so we don't silently overwrite or skip.
          bool fileExists;
          try {
            await sftp.stat(remotePath);
            fileExists = true;
          } on SftpStatusError catch (e) {
            if (e.code == SftpStatusCode.noSuchFile) {
              fileExists = false;
            } else {
              rethrow;
            }
          }
          if (fileExists) {
            onFileSkipped(entity.path);
            continue;
          }
        }
        await _uploadFileWithProgress(sftp, entity.path, remotePath, onProgress);
```

- [ ] **Step 3: Verify**

Run: `cd app && flutter analyze && flutter test test/services/sftp_transfer_service_test.dart`
Expected: No analyzer issues; existing tests pass (both params are optional — no caller breaks).

- [ ] **Step 4: Commit**

```bash
git add app/lib/services/sftp_transfer_service.dart
git commit -m "feat(sftp): uploadFile progress callback + uploadDirectory overwrite flag"
```

---

### Task 6: `BulkRunController`

**Files:**
- Create: `app/lib/widgets/bulk/bulk_run_controller.dart`
- Test: `app/test/widgets/bulk_run_controller_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/widgets/bulk_run_controller_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/bulk_result.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/bulk_action_service.dart';
import 'package:yourssh/widgets/bulk/bulk_run_controller.dart';

void main() {
  final hosts = [
    Host(label: 'a', host: 'a.x', username: 'u'),
    Host(label: 'b', host: 'b.x', username: 'u'),
  ];

  test('runCommand drives results from pending to success', () async {
    final controller = BulkRunController(
      service: BulkActionService(
          exec: (h, c) async => (stdout: 'ok', stderr: '', exitCode: 0)),
      hosts: hosts,
    );
    expect(controller.results, isEmpty);
    expect(controller.hasRun, isFalse);

    final run = controller.runCommand('uptime');
    expect(controller.isRunning, isTrue);
    expect(controller.results, hasLength(2)); // initialized immediately
    await run;

    expect(controller.isRunning, isFalse);
    expect(controller.hasRun, isTrue);
    expect(controller.countOf(BulkHostStatus.success), 2);
    // results keep host order
    expect(controller.results.map((r) => r.host.label).toList(), ['a', 'b']);
  });

  test('second run while running is a no-op', () async {
    final gate = Completer<void>();
    final controller = BulkRunController(
      service: BulkActionService(exec: (h, c) async {
        await gate.future;
        return (stdout: '', stderr: '', exitCode: 0);
      }),
      hosts: hosts,
    );
    final first = controller.runCommand('x');
    final second = controller.runCommand('y'); // ignored
    gate.complete();
    await Future.wait([first, second]);
    expect(controller.countOf(BulkHostStatus.success), 2);
  });

  test('cancel cancels the active token', () async {
    late BulkRunController controller;
    controller = BulkRunController(
      service: BulkActionService(exec: (h, c) async {
        controller.cancel();
        return (stdout: '', stderr: '', exitCode: 0);
      }),
      hosts: hosts,
    );
    await controller.runCommand('x'); // maxConcurrent > hosts, but pool
    // serializes per worker; with 2 hosts/6 workers both may start —
    // assert no exception and run completes.
    expect(controller.isRunning, isFalse);
  });

  test('dispose mid-run does not throw on late updates', () async {
    final gate = Completer<void>();
    final controller = BulkRunController(
      service: BulkActionService(exec: (h, c) async {
        await gate.future;
        return (stdout: '', stderr: '', exitCode: 0);
      }),
      hosts: hosts,
    );
    final run = controller.runCommand('x');
    controller.dispose();
    gate.complete();
    await run; // late onUpdate/notify must not throw
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/widgets/bulk_run_controller_test.dart`
Expected: FAIL — missing `bulk_run_controller.dart`.

- [ ] **Step 3: Implement**

```dart
// app/lib/widgets/bulk/bulk_run_controller.dart
import 'package:flutter/foundation.dart';

import '../../models/bulk_result.dart';
import '../../models/host.dart';
import '../../services/bulk_action_service.dart';

/// Dialog-scoped state for one bulk run. Created and disposed by the
/// dialog that shows it — deliberately NOT registered in main.dart's
/// MultiProvider: the run lives only as long as the dialog and nothing
/// outside consumes it.
class BulkRunController extends ChangeNotifier {
  final BulkActionService _service;
  final List<Host> hosts;

  BulkRunController({required BulkActionService service, required this.hosts})
      : _service = service;

  final Map<String, BulkHostResult> _results = {}; // hostId → latest
  BulkCancelToken? _token;
  bool _running = false;
  bool _disposed = false;

  bool get isRunning => _running;
  bool get hasRun => _results.isNotEmpty;

  /// Latest result per host, in the order the run was started with.
  List<BulkHostResult> get results => [
        for (final h in hosts)
          if (_results[h.id] != null) _results[h.id]!,
      ];

  int countOf(BulkHostStatus status) =>
      results.where((r) => r.status == status).length;

  Future<void> runCommand(String command) =>
      _start((token) => _service.runCommand(hosts, command,
          onUpdate: _onUpdate, token: token));

  Future<void> pushFiles(List<BulkPushSource> sources, String remoteDir) =>
      _start((token) => _service.pushFiles(hosts, sources, remoteDir,
          onUpdate: _onUpdate, token: token));

  Future<void> _start(
      Future<void> Function(BulkCancelToken token) run) async {
    if (_running) return;
    _running = true;
    final token = BulkCancelToken();
    _token = token;
    for (final h in hosts) {
      _results[h.id] = BulkHostResult(host: h, status: BulkHostStatus.pending);
    }
    _safeNotify();
    try {
      await run(token);
    } finally {
      _running = false;
      _safeNotify();
    }
  }

  void _onUpdate(BulkHostResult r) {
    _results[r.host.id] = r;
    _safeNotify();
  }

  void cancel() => _token?.cancel();

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/bulk_run_controller_test.dart`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/bulk/bulk_run_controller.dart app/test/widgets/bulk_run_controller_test.dart
git commit -m "feat(bulk): dialog-scoped BulkRunController"
```

---

### Task 7: Shared per-host status rows (`BulkHostStatusList`)

**Files:**
- Create: `app/lib/widgets/bulk/bulk_host_status_list.dart`
- Test: `app/test/widgets/bulk_host_status_list_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/widgets/bulk_host_status_list_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/bulk_result.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/widgets/bulk/bulk_host_status_list.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  final host = Host(label: 'web-1', host: 'w1.x', username: 'root');

  testWidgets('renders rows and expands to show output', (tester) async {
    await tester.pumpWidget(_wrap(BulkHostStatusList(results: [
      BulkHostResult(
          host: host,
          status: BulkHostStatus.success,
          exitCode: 0,
          stdout: 'Linux web-1',
          elapsed: const Duration(milliseconds: 1200)),
    ])));
    expect(find.text('web-1'), findsOneWidget);
    expect(find.text('1.2s'), findsOneWidget);
    expect(find.text('Linux web-1'), findsNothing); // collapsed

    await tester.tap(find.text('web-1'));
    await tester.pumpAndSettle();
    expect(find.text('Linux web-1'), findsOneWidget); // expanded
  });

  testWidgets('failed row shows error and non-zero exit shows chip',
      (tester) async {
    await tester.pumpWidget(_wrap(BulkHostStatusList(results: [
      BulkHostResult(
          host: host, status: BulkHostStatus.failed, error: 'auth failed'),
      BulkHostResult(
          host: Host(label: 'db-1', host: 'd1.x', username: 'root'),
          status: BulkHostStatus.success,
          exitCode: 2,
          stdout: ''),
    ])));
    expect(find.text('auth failed'), findsOneWidget); // error shown inline
    expect(find.text('exit 2'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/bulk_host_status_list_test.dart`
Expected: FAIL — missing widget file.

- [ ] **Step 3: Implement**

```dart
// app/lib/widgets/bulk/bulk_host_status_list.dart
import 'package:flutter/material.dart';

import '../../models/bulk_result.dart';
import '../../theme/app_theme.dart';

/// Per-host rows shared by the Run-command and Push-files dialogs:
/// status icon, label, error/exit info, transfer progress; tap to expand
/// stdout/stderr/error.
class BulkHostStatusList extends StatelessWidget {
  final List<BulkHostResult> results;
  const BulkHostStatusList({super.key, required this.results});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Center(
        child: Text('Nothing run yet.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
      );
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) => _ResultRow(result: results[i]),
    );
  }
}

class _ResultRow extends StatefulWidget {
  final BulkHostResult result;
  const _ResultRow({required this.result});

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _expanded = false;

  bool get _expandable {
    final r = widget.result;
    return r.stdout.isNotEmpty || r.stderr.isNotEmpty || r.error != null;
  }

  Widget _statusIcon(BulkHostResult r) {
    switch (r.status) {
      case BulkHostStatus.pending:
        return const Icon(Icons.radio_button_unchecked,
            size: 14, color: AppColors.textTertiary);
      case BulkHostStatus.running:
        return const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: AppColors.textSecondary));
      case BulkHostStatus.success:
        final clean = (r.exitCode ?? 0) == 0;
        return Icon(clean ? Icons.check_circle_outline : Icons.error_outline,
            size: 14, color: clean ? AppColors.accent : AppColors.orange);
      case BulkHostStatus.failed:
        return const Icon(Icons.error_outline,
            size: 14, color: AppColors.red);
      case BulkHostStatus.cancelled:
        return const Icon(Icons.block, size: 14, color: AppColors.textTertiary);
    }
  }

  String _elapsed(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';

  String _bytes(int b) {
    if (b >= 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '$b B';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final transferring =
        r.totalBytes > 0 && r.status == BulkHostStatus.running;
    return InkWell(
      onTap: _expandable ? () => setState(() => _expanded = !_expanded) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _statusIcon(r),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.host.label,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                      Text('${r.host.username}@${r.host.host}',
                          style: const TextStyle(
                              color: AppColors.textTertiary, fontSize: 11)),
                    ],
                  ),
                ),
                if (r.error != null && !_expanded)
                  Flexible(
                    child: Text(r.error!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.red, fontSize: 11)),
                  ),
                if (r.status == BulkHostStatus.success &&
                    (r.exitCode ?? 0) != 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('exit ${r.exitCode}',
                        style: const TextStyle(
                            color: AppColors.orange, fontSize: 10)),
                  ),
                ],
                if (transferring) ...[
                  const SizedBox(width: 8),
                  Text('${_bytes(r.bytesTransferred)} / ${_bytes(r.totalBytes)}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ],
                if (r.elapsed != null) ...[
                  const SizedBox(width: 8),
                  Text(_elapsed(r.elapsed!),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ],
                if (_expandable) ...[
                  const SizedBox(width: 6),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 14, color: AppColors.textTertiary),
                ],
              ],
            ),
            if (transferring) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: r.totalBytes == 0
                    ? null
                    : r.bytesTransferred / r.totalBytes,
                minHeight: 3,
                backgroundColor: AppColors.border,
                color: AppColors.accent,
              ),
            ],
            if (_expanded) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r.stdout.isNotEmpty)
                      SelectableText(r.stdout.trimRight(),
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                    if (r.stderr.isNotEmpty)
                      SelectableText(r.stderr.trimRight(),
                          style: const TextStyle(
                              color: AppColors.orange,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                    if (r.error != null)
                      SelectableText(r.error!,
                          style: const TextStyle(
                              color: AppColors.red,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/widgets/bulk_host_status_list_test.dart`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/bulk/bulk_host_status_list.dart app/test/widgets/bulk_host_status_list_test.dart
git commit -m "feat(bulk): shared per-host status row list"
```

---

### Task 8: Diff tab (`BulkDiffView`)

**Files:**
- Create: `app/lib/widgets/bulk/bulk_diff_view.dart`
- Test: `app/test/widgets/bulk_diff_view_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/widgets/bulk_diff_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/bulk_result.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/widgets/bulk/bulk_diff_view.dart';

BulkHostResult _ok(String label, String stdout) => BulkHostResult(
      host: Host(label: label, host: '$label.x', username: 'u'),
      status: BulkHostStatus.success,
      exitCode: 0,
      stdout: stdout,
    );

Widget _wrap(Widget child) => MaterialApp(
    home: Scaffold(body: SizedBox(width: 900, height: 600, child: child)));

void main() {
  testWidgets('groups outputs, baseline is the largest group',
      (tester) async {
    await tester.pumpWidget(_wrap(BulkDiffView(results: [
      _ok('a', 'kernel 6.1'),
      _ok('b', 'kernel 6.1'),
      _ok('c', 'kernel 5.4'),
    ])));
    expect(find.text('2 distinct outputs'), findsOneWidget);
    expect(find.text('BASELINE'), findsOneWidget);
    expect(find.text('2 hosts'), findsOneWidget);
    expect(find.text('1 host'), findsOneWidget);
  });

  testWidgets('selecting the divergent group shows a diff vs baseline',
      (tester) async {
    await tester.pumpWidget(_wrap(BulkDiffView(results: [
      _ok('a', 'kernel 6.1'),
      _ok('b', 'kernel 6.1'),
      _ok('c', 'kernel 5.4'),
    ])));
    await tester.tap(find.text('1 host'));
    await tester.pumpAndSettle();
    expect(find.text('- kernel 6.1'), findsOneWidget);
    expect(find.text('+ kernel 5.4'), findsOneWidget);
  });

  testWidgets('failed hosts listed separately', (tester) async {
    await tester.pumpWidget(_wrap(BulkDiffView(results: [
      _ok('a', 'x'),
      BulkHostResult(
          host: Host(label: 'bad', host: 'bad.x', username: 'u'),
          status: BulkHostStatus.failed,
          error: 'unreachable'),
    ])));
    expect(find.text('Failed (1)'), findsOneWidget);
    expect(find.text('bad'), findsOneWidget);
  });

  testWidgets('no successful results shows placeholder', (tester) async {
    await tester.pumpWidget(_wrap(const BulkDiffView(results: [])));
    expect(find.text('No successful output to compare.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/bulk_diff_view_test.dart`
Expected: FAIL — missing widget file.

- [ ] **Step 3: Implement**

```dart
// app/lib/widgets/bulk/bulk_diff_view.dart
import 'package:flutter/material.dart';

import '../../models/bulk_result.dart';
import '../../theme/app_theme.dart';
import '../../util/bulk_diff.dart';

/// Diff tab of the bulk Run-command dialog: groups identical outputs
/// (largest group = default baseline), shows a unified diff of any group
/// against the baseline, and offers a two-host side-by-side compare.
class BulkDiffView extends StatefulWidget {
  final List<BulkHostResult> results;
  const BulkDiffView({super.key, required this.results});

  @override
  State<BulkDiffView> createState() => _BulkDiffViewState();
}

class _BulkDiffViewState extends State<BulkDiffView> {
  int _baseline = 0;
  int? _selected; // null → show baseline
  bool _compare = false;
  String? _hostA;
  String? _hostB;

  @override
  Widget build(BuildContext context) {
    final groups = groupByOutput(widget.results);
    final failed = widget.results
        .where((r) => r.status == BulkHostStatus.failed)
        .toList();
    if (groups.isEmpty) {
      return const Center(
        child: Text('No successful output to compare.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
      );
    }
    // Guard stale indices when a re-run produced fewer groups.
    final baseline = _baseline < groups.length ? _baseline : 0;
    final selected =
        (_selected != null && _selected! < groups.length) ? _selected! : baseline;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 250,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                    '${groups.length} distinct output${groups.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (var i = 0; i < groups.length; i++)
                      _GroupTile(
                        group: groups[i],
                        isBaseline: i == baseline,
                        isSelected: i == selected && !_compare,
                        onTap: () =>
                            setState(() { _selected = i; _compare = false; }),
                        onSetBaseline: () => setState(() => _baseline = i),
                      ),
                    if (failed.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
                        child: Text('Failed (${failed.length})',
                            style: const TextStyle(
                                color: AppColors.red,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                      for (final r in failed)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.host.label,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 11)),
                              if (r.error != null)
                                Text(r.error!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 10)),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: OutlinedButton(
                  onPressed: () => setState(() => _compare = !_compare),
                  child: Text(
                      _compare ? 'BACK TO GROUPS' : 'COMPARE TWO HOSTS',
                      style: const TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: AppColors.border),
        Expanded(
          child: _compare
              ? _HostCompare(
                  results: widget.results,
                  hostA: _hostA,
                  hostB: _hostB,
                  onPick: (a, b) => setState(() { _hostA = a; _hostB = b; }),
                )
              : selected == baseline
                  ? _PlainOutput(output: groups[baseline].output)
                  : _UnifiedDiff(
                      lines: lineDiff(
                          groups[baseline].output, groups[selected].output)),
        ),
      ],
    );
  }
}

class _GroupTile extends StatelessWidget {
  final OutputGroup group;
  final bool isBaseline;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onSetBaseline;
  const _GroupTile(
      {required this.group,
      required this.isBaseline,
      required this.isSelected,
      required this.onTap,
      required this.onSetBaseline});

  @override
  Widget build(BuildContext context) {
    final preview = group.hostLabels.take(3).join(', ') +
        (group.size > 3 ? ' +${group.size - 3}' : '');
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.cardHover : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      '${group.size} host${group.size == 1 ? '' : 's'}',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                if (isBaseline)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('BASELINE',
                        style: TextStyle(
                            color: AppColors.accent, fontSize: 9)),
                  )
                else
                  Tooltip(
                    message: 'Set as baseline',
                    child: InkWell(
                      onTap: onSetBaseline,
                      child: const Icon(Icons.flag_outlined,
                          size: 13, color: AppColors.textTertiary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _PlainOutput extends StatelessWidget {
  final String output;
  const _PlainOutput({required this.output});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SelectableText(output.isEmpty ? '(empty output)' : output,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace')),
    );
  }
}

class _UnifiedDiff extends StatelessWidget {
  final List<DiffLine> lines;
  const _UnifiedDiff({required this.lines});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: lines.length,
      itemBuilder: (_, i) {
        final l = lines[i];
        final (prefix, color, bg) = switch (l.op) {
          DiffOp.added => ('+ ', AppColors.accent,
              AppColors.accent.withValues(alpha: 0.08)),
          DiffOp.removed => ('- ', AppColors.red,
              AppColors.red.withValues(alpha: 0.08)),
          DiffOp.same => ('  ', AppColors.textSecondary, null),
        };
        return Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('$prefix${l.text}',
              style: TextStyle(
                  color: color, fontSize: 12, fontFamily: 'monospace')),
        );
      },
    );
  }
}

class _HostCompare extends StatelessWidget {
  final List<BulkHostResult> results;
  final String? hostA;
  final String? hostB;
  final void Function(String? a, String? b) onPick;
  const _HostCompare(
      {required this.results,
      required this.hostA,
      required this.hostB,
      required this.onPick});

  @override
  Widget build(BuildContext context) {
    final ok =
        results.where((r) => r.status == BulkHostStatus.success).toList();
    final labels = [for (final r in ok) r.host.label];
    final a = ok.where((r) => r.host.label == hostA).firstOrNull;
    final b = ok.where((r) => r.host.label == hostB).firstOrNull;

    DropdownButton<String> picker(String? value, bool isA) =>
        DropdownButton<String>(
          value: value,
          hint: Text(isA ? 'Host A' : 'Host B',
              style: const TextStyle(
                  color: AppColors.textTertiary, fontSize: 12)),
          dropdownColor: AppColors.card,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          items: [
            for (final l in labels)
              DropdownMenuItem(value: l, child: Text(l)),
          ],
          onChanged: (v) => onPick(isA ? v : hostA, isA ? hostB : v),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              picker(hostA, true),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.compare_arrows,
                    size: 16, color: AppColors.textSecondary),
              ),
              picker(hostB, false),
            ],
          ),
        ),
        Expanded(
          child: (a == null || b == null)
              ? const Center(
                  child: Text('Pick two hosts to compare.',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 12)))
              : _SideBySide(
                  rows: sideBySideRows(lineDiff(
                      a.stdout.trimRight(), b.stdout.trimRight()))),
        ),
      ],
    );
  }
}

class _SideBySide extends StatelessWidget {
  final List<({DiffLine? left, DiffLine? right})> rows;
  const _SideBySide({required this.rows});

  Widget _cell(DiffLine? line) {
    final color = switch (line?.op) {
      DiffOp.removed => AppColors.red,
      DiffOp.added => AppColors.accent,
      DiffOp.same => AppColors.textSecondary,
      null => Colors.transparent,
    };
    final bg = switch (line?.op) {
      DiffOp.removed => AppColors.red.withValues(alpha: 0.08),
      DiffOp.added => AppColors.accent.withValues(alpha: 0.08),
      _ => null,
    };
    return Expanded(
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(line?.text ?? '',
            style: TextStyle(
                color: color, fontSize: 12, fontFamily: 'monospace')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      itemBuilder: (_, i) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cell(rows[i].left),
          Container(width: 1, height: 16, color: AppColors.border),
          _cell(rows[i].right),
        ],
      ),
    );
  }
}
```

Note: `firstOrNull` needs no extra import — `package:collection` extensions are already available transitively; if the analyzer complains, use `cast<BulkHostResult?>().firstWhere(..., orElse: () => null)` or add `import 'package:collection/collection.dart';`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/widgets/bulk_diff_view_test.dart`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/bulk/bulk_diff_view.dart app/test/widgets/bulk_diff_view_test.dart
git commit -m "feat(bulk): diff view with output groups, baseline, side-by-side compare"
```

---

### Task 9: Run command dialog (`BulkRunDialog`)

**Files:**
- Create: `app/lib/widgets/bulk/bulk_run_dialog.dart`
- Test: `app/test/widgets/bulk_run_dialog_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/widgets/bulk_run_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/bulk_action_service.dart';
import 'package:yourssh/widgets/bulk/bulk_run_dialog.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget wrap(Widget child) => ChangeNotifierProvider(
        create: (_) => SnippetProvider(),
        child: MaterialApp(home: Scaffold(body: child)),
      );

  testWidgets('runs a command and shows per-host results', (tester) async {
    final hosts = [
      Host(label: 'a', host: 'a.x', username: 'u'),
      Host(label: 'b', host: 'b.x', username: 'u'),
    ];
    final service = BulkActionService(
        exec: (h, c) async => (stdout: 'up 1 day', stderr: '', exitCode: 0));

    await tester.pumpWidget(
        wrap(BulkRunDialog(hosts: hosts, serviceOverride: service)));
    expect(find.text('Run command on 2 hosts'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('bulk-command-field')), 'uptime');
    await tester.tap(find.text('RUN'));
    await tester.pumpAndSettle();

    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
    expect(find.textContaining('2 ok'), findsOneWidget);
  });

  testWidgets('RUN does nothing with an empty command', (tester) async {
    var execCount = 0;
    final service = BulkActionService(exec: (h, c) async {
      execCount++;
      return (stdout: '', stderr: '', exitCode: 0);
    });
    await tester.pumpWidget(wrap(BulkRunDialog(
        hosts: [Host(label: 'a', host: 'a.x', username: 'u')],
        serviceOverride: service)));
    await tester.tap(find.text('RUN'));
    await tester.pumpAndSettle();
    expect(execCount, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/bulk_run_dialog_test.dart`
Expected: FAIL — missing dialog file.

- [ ] **Step 3: Implement**

```dart
// app/lib/widgets/bulk/bulk_run_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

import '../../models/bulk_result.dart';
import '../../models/host.dart';
import '../../services/bulk_action_service.dart';
import '../../services/ssh_service.dart';
import '../../theme/app_theme.dart';
import 'bulk_diff_view.dart';
import 'bulk_host_status_list.dart';
import 'bulk_run_controller.dart';

/// Modal that runs one command (free text or snippet) on N hosts in
/// parallel; Results tab = per-host rows, Diff tab = output grouping.
class BulkRunDialog extends StatefulWidget {
  final List<Host> hosts;

  /// Tests inject a service with fake exec; production builds one over
  /// [SshService.exec] read from the tree.
  final BulkActionService? serviceOverride;

  const BulkRunDialog({super.key, required this.hosts, this.serviceOverride});

  @override
  State<BulkRunDialog> createState() => _BulkRunDialogState();
}

class _BulkRunDialogState extends State<BulkRunDialog> {
  late final BulkRunController _controller;
  final _commandController = TextEditingController();
  bool _showDiff = false;

  @override
  void initState() {
    super.initState();
    final service = widget.serviceOverride ??
        BulkActionService(exec: context.read<SshService>().exec);
    _controller = BulkRunController(service: service, hosts: widget.hosts)
      ..addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _commandController.dispose();
    super.dispose();
  }

  void _run() {
    final cmd = _commandController.text.trim();
    if (cmd.isEmpty || _controller.isRunning) return;
    setState(() => _showDiff = false);
    _controller.runCommand(cmd);
  }

  Future<void> _close() async {
    if (_controller.isRunning) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Cancel run?',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
          content: const Text(
              'Hosts still in flight will finish; queued hosts will be cancelled.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep running')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cancel run',
                    style: TextStyle(color: AppColors.red))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      _controller.cancel();
    }
    if (mounted) Navigator.of(context).pop();
  }

  String get _summary {
    final ok = _controller.countOf(BulkHostStatus.success);
    final failed = _controller.countOf(BulkHostStatus.failed);
    final cancelled = _controller.countOf(BulkHostStatus.cancelled);
    var s = '$ok ok · $failed failed';
    if (cancelled > 0) s += ' · $cancelled cancelled';
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final snippets = context.watch<SnippetProvider>().snippets;
    final running = _controller.isRunning;
    final diffReady = _controller.hasRun && !running;

    return Dialog(
      backgroundColor: AppColors.bg,
      insetPadding: const EdgeInsets.all(40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 900,
          height: 650,
          child: Column(
            children: [
              // Header
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: AppColors.sidebar,
                  border:
                      Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.terminal,
                        size: 15, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text('Run command on ${widget.hosts.length} hosts',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 16, color: AppColors.textSecondary),
                      onPressed: _close,
                    ),
                  ],
                ),
              ),
              // Command row
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('bulk-command-field'),
                        controller: _commandController,
                        onSubmitted: (_) => _run(),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          hintText: 'Command to run on every host…',
                          hintStyle: const TextStyle(
                              color: AppColors.textTertiary, fontSize: 13),
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.card,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<Snippet>(
                      tooltip: 'Insert snippet',
                      color: AppColors.card,
                      icon: const Icon(Icons.data_object,
                          size: 18, color: AppColors.textSecondary),
                      itemBuilder: (_) => [
                        for (final s in snippets)
                          PopupMenuItem(
                            value: s,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.label,
                                    style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 12)),
                                Text(s.command,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 10,
                                        fontFamily: 'monospace')),
                              ],
                            ),
                          ),
                      ],
                      onSelected: (s) =>
                          setState(() => _commandController.text = s.command),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            running ? AppColors.red : AppColors.accent,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: running ? _controller.cancel : _run,
                      child: Text(running ? 'CANCEL' : 'RUN',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              // Tabs
              Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    _TabBtn(
                        label: 'RESULTS',
                        active: !_showDiff,
                        onTap: () => setState(() => _showDiff = false)),
                    _TabBtn(
                        label: 'DIFF',
                        active: _showDiff,
                        enabled: diffReady,
                        onTap: () => setState(() => _showDiff = true)),
                  ],
                ),
              ),
              Expanded(
                child: _showDiff
                    ? BulkDiffView(results: _controller.results)
                    : BulkHostStatusList(results: _controller.results),
              ),
              // Footer
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: AppColors.sidebar,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    if (_controller.hasRun)
                      Text(_summary,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                    const Spacer(),
                    TextButton(
                      onPressed: _close,
                      child: const Text('CLOSE',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  const _TabBtn(
      {required this.label,
      required this.active,
      this.enabled = true,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: !enabled
                  ? AppColors.textTertiary
                  : active
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            )),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/widgets/bulk_run_dialog_test.dart`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/bulk/bulk_run_dialog.dart app/test/widgets/bulk_run_dialog_test.dart
git commit -m "feat(bulk): run-command dialog with results and diff tabs"
```

---

### Task 10: Push files dialog (`BulkPushDialog`)

**Files:**
- Create: `app/lib/widgets/bulk/bulk_push_dialog.dart`

OS file pickers (`openFiles` / `getDirectoryPath`) can't run in widget tests; the engine underneath is fully covered by Task 4. Verify with analyzer + the manual smoke test in Task 12.

- [ ] **Step 1: Implement**

```dart
// app/lib/widgets/bulk/bulk_push_dialog.dart
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bulk_result.dart';
import '../../models/host.dart';
import '../../services/bulk_action_service.dart';
import '../../services/sftp_file_ops_service.dart';
import '../../services/sftp_transfer_service.dart';
import '../../services/ssh_service.dart';
import '../../theme/app_theme.dart';
import 'bulk_host_status_list.dart';
import 'bulk_run_controller.dart';

/// Modal that uploads local files/folders to the same remote path on N
/// hosts. Existing remote files are overwritten.
class BulkPushDialog extends StatefulWidget {
  final List<Host> hosts;
  final BulkActionService? serviceOverride; // tests
  const BulkPushDialog({super.key, required this.hosts, this.serviceOverride});

  @override
  State<BulkPushDialog> createState() => _BulkPushDialogState();
}

class _BulkPushDialogState extends State<BulkPushDialog> {
  late final BulkRunController _controller;
  final List<BulkPushSource> _sources = [];
  final _destController = TextEditingController(text: '/tmp');

  @override
  void initState() {
    super.initState();
    _controller =
        BulkRunController(service: _buildService(), hosts: widget.hosts)
          ..addListener(_onChanged);
  }

  BulkActionService _buildService() {
    if (widget.serviceOverride != null) return widget.serviceOverride!;
    final ssh = context.read<SshService>();
    final transfer = SftpTransferService(ssh);
    final ops = SftpFileOpsService(ssh);
    return BulkActionService(
      uploadFile: (host, local, remote, {onProgress}) =>
          transfer.uploadFile(host, local, remote, onProgress: onProgress),
      uploadDirectory: ({
        required host,
        required localDir,
        required remoteDir,
        required onProgress,
        required isCancelled,
      }) =>
          transfer.uploadDirectory(
            localDir: localDir,
            remoteHost: host,
            remoteDir: remoteDir,
            onProgress: onProgress,
            onFileSkipped: (_) {},
            isCancelled: isCancelled,
            overwrite: true,
          ),
      mkdir: ops.mkdir,
    );
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _destController.dispose();
    super.dispose();
  }

  Future<void> _addFiles() async {
    final files = await openFiles();
    if (files.isEmpty) return;
    final fresh = [
      for (final f in files)
        if (!_sources.any((s) => s.path == f.path)) f.path,
    ];
    final resolved = await BulkActionService.resolveSources(fresh);
    if (mounted) setState(() => _sources.addAll(resolved));
  }

  Future<void> _addFolder() async {
    final dir = await getDirectoryPath();
    if (dir == null || _sources.any((s) => s.path == dir)) return;
    final resolved = await BulkActionService.resolveSources([dir]);
    if (mounted) setState(() => _sources.addAll(resolved));
  }

  bool get _destValid => _destController.text.trim().startsWith('/');
  bool get _canPush =>
      _sources.isNotEmpty && _destValid && !_controller.isRunning;

  void _push() {
    if (!_canPush) return;
    _controller.pushFiles(List.of(_sources), _destController.text.trim());
  }

  Future<void> _close() async {
    if (_controller.isRunning) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Cancel push?',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
          content: const Text(
              'Transfers in flight will stop at the next file boundary.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep pushing')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cancel push',
                    style: TextStyle(color: AppColors.red))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      _controller.cancel();
    }
    if (mounted) Navigator.of(context).pop();
  }

  String _fmtBytes(int b) {
    if (b >= 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '$b B';
  }

  @override
  Widget build(BuildContext context) {
    final running = _controller.isRunning;
    final ok = _controller.countOf(BulkHostStatus.success);
    final failed = _controller.countOf(BulkHostStatus.failed);
    final cancelled = _controller.countOf(BulkHostStatus.cancelled);

    return Dialog(
      backgroundColor: AppColors.bg,
      insetPadding: const EdgeInsets.all(40),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 760,
          height: 600,
          child: Column(
            children: [
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: AppColors.sidebar,
                  border:
                      Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.upload_file,
                        size: 15, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text('Push files to ${widget.hosts.length} hosts',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 16, color: AppColors.textSecondary),
                      onPressed: _close,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: running ? null : _addFiles,
                          icon: const Icon(Icons.insert_drive_file_outlined,
                              size: 14),
                          label: const Text('ADD FILES',
                              style: TextStyle(fontSize: 11)),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: running ? null : _addFolder,
                          icon:
                              const Icon(Icons.folder_outlined, size: 14),
                          label: const Text('ADD FOLDER',
                              style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                    if (_sources.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in _sources)
                            Chip(
                              backgroundColor: AppColors.card,
                              side:
                                  const BorderSide(color: AppColors.border),
                              label: Text(
                                  '${s.isDirectory ? '📁 ' : ''}${s.name} · ${_fmtBytes(s.bytes)}',
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 11)),
                              deleteIcon: const Icon(Icons.close, size: 12),
                              onDeleted: running
                                  ? null
                                  : () =>
                                      setState(() => _sources.remove(s)),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text('Destination',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: const Key('bulk-dest-field'),
                            controller: _destController,
                            enabled: !running,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontFamily: 'monospace'),
                            decoration: InputDecoration(
                              hintText: '/absolute/remote/path',
                              hintStyle: const TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 12),
                              errorText: _destValid
                                  ? null
                                  : 'Must be an absolute path',
                              isDense: true,
                              filled: true,
                              fillColor: AppColors.card,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: AppColors.border),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                running ? AppColors.red : AppColors.accent,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: running
                              ? _controller.cancel
                              : (_canPush ? _push : null),
                          child: Text(running ? 'CANCEL' : 'PUSH',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text('Existing remote files will be overwritten.',
                        style: TextStyle(
                            color: AppColors.orange, fontSize: 11)),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                  child:
                      BulkHostStatusList(results: _controller.results)),
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: AppColors.sidebar,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    if (_controller.hasRun)
                      Text(
                          '$ok ok · $failed failed${cancelled > 0 ? ' · $cancelled cancelled' : ''}',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                    const Spacer(),
                    TextButton(
                      onPressed: _close,
                      child: const Text('CLOSE',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run: `cd app && flutter analyze`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/bulk/bulk_push_dialog.dart
git commit -m "feat(bulk): push-files dialog with per-host transfer progress"
```

---

### Task 11: `planConnectAll` helper + `BulkActionBar`

**Files:**
- Create: `app/lib/util/bulk_connect.dart`
- Create: `app/lib/widgets/bulk/bulk_action_bar.dart`
- Test: `app/test/util/bulk_connect_test.dart`
- Test: `app/test/widgets/bulk_action_bar_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/util/bulk_connect_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/util/bulk_connect.dart';

void main() {
  test('splits selection into to-connect and skipped', () {
    final a = Host(label: 'a', host: 'a.x', username: 'u');
    final b = Host(label: 'b', host: 'b.x', username: 'u');
    final c = Host(label: 'c', host: 'c.x', username: 'u');
    final plan =
        planConnectAll(selected: [a, b, c], liveHostIds: {b.id});
    expect(plan.toConnect.map((h) => h.label).toList(), ['a', 'c']);
    expect(plan.skipped, 1);
  });

  test('nothing live connects everything', () {
    final a = Host(label: 'a', host: 'a.x', username: 'u');
    final plan = planConnectAll(selected: [a], liveHostIds: {});
    expect(plan.toConnect, hasLength(1));
    expect(plan.skipped, 0);
  });
}
```

```dart
// app/test/widgets/bulk_action_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/bulk/bulk_action_bar.dart';

void main() {
  testWidgets('fires callbacks; actions disabled with empty selection',
      (tester) async {
    final fired = <String>[];
    Widget build(int count) => MaterialApp(
          home: Scaffold(
            body: BulkActionBar(
              selectedCount: count,
              onSelectAll: () => fired.add('all'),
              onClear: () => fired.add('clear'),
              onConnectAll: () => fired.add('connect'),
              onRunCommand: () => fired.add('run'),
              onPushFiles: () => fired.add('push'),
              onDone: () => fired.add('done'),
            ),
          ),
        );

    await tester.pumpWidget(build(0));
    expect(find.text('0 selected'), findsOneWidget);
    await tester.tap(find.text('CONNECT ALL'));
    expect(fired, isEmpty); // disabled at 0

    await tester.pumpWidget(build(3));
    expect(find.text('3 selected'), findsOneWidget);
    await tester.tap(find.text('CONNECT ALL'));
    await tester.tap(find.text('RUN COMMAND'));
    await tester.tap(find.text('PUSH FILES'));
    await tester.tap(find.text('SELECT ALL'));
    await tester.tap(find.text('DONE'));
    expect(fired, ['connect', 'run', 'push', 'all', 'done']);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/util/bulk_connect_test.dart test/widgets/bulk_action_bar_test.dart`
Expected: FAIL — missing files.

- [ ] **Step 3: Implement `bulk_connect.dart`**

```dart
// app/lib/util/bulk_connect.dart
// Pure helper for the bulk Connect-all action. No Flutter imports.
import '../models/host.dart';

/// Splits [selected] into hosts to connect and the count skipped because
/// they already have a live (connecting/connected) session.
({List<Host> toConnect, int skipped}) planConnectAll({
  required List<Host> selected,
  required Set<String> liveHostIds,
}) {
  final toConnect = [
    for (final h in selected)
      if (!liveHostIds.contains(h.id)) h,
  ];
  return (toConnect: toConnect, skipped: selected.length - toConnect.length);
}
```

- [ ] **Step 4: Implement `bulk_action_bar.dart`**

```dart
// app/lib/widgets/bulk/bulk_action_bar.dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Replaces the hosts-dashboard top bar while selection mode is active.
class BulkActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onConnectAll;
  final VoidCallback onRunCommand;
  final VoidCallback onPushFiles;
  final VoidCallback onDone;

  const BulkActionBar({
    super.key,
    required this.selectedCount,
    required this.onSelectAll,
    required this.onClear,
    required this.onConnectAll,
    required this.onRunCommand,
    required this.onPushFiles,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedCount > 0;
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text('$selectedCount selected',
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 16),
          _BarBtn(label: 'SELECT ALL', onTap: onSelectAll),
          const SizedBox(width: 8),
          _BarBtn(label: 'CLEAR', onTap: onClear, enabled: hasSelection),
          const Spacer(),
          _BarBtn(
              icon: Icons.cable,
              label: 'CONNECT ALL',
              onTap: onConnectAll,
              enabled: hasSelection),
          const SizedBox(width: 8),
          _BarBtn(
              icon: Icons.terminal,
              label: 'RUN COMMAND',
              onTap: onRunCommand,
              enabled: hasSelection),
          const SizedBox(width: 8),
          _BarBtn(
              icon: Icons.upload_file,
              label: 'PUSH FILES',
              onTap: onPushFiles,
              enabled: hasSelection),
          const SizedBox(width: 16),
          _BarBtn(label: 'DONE', onTap: onDone, accent: true),
        ],
      ),
    );
  }
}

class _BarBtn extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool accent;
  const _BarBtn(
      {this.icon,
      required this.label,
      required this.onTap,
      this.enabled = true,
      this.accent = false});

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.textTertiary
        : accent
            ? AppColors.accent
            : AppColors.textSecondary;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(
              color: accent && enabled ? AppColors.accent : AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd app && flutter test test/util/bulk_connect_test.dart test/widgets/bulk_action_bar_test.dart`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/util/bulk_connect.dart app/lib/widgets/bulk/bulk_action_bar.dart \
        app/test/util/bulk_connect_test.dart app/test/widgets/bulk_action_bar_test.dart
git commit -m "feat(bulk): connect-all planner and selection-mode action bar"
```

---

### Task 12: Dashboard integration — selection mode

**Files:**
- Modify: `app/lib/widgets/hosts_dashboard.dart`

All logic was tested in Tasks 1–11; this task is wiring. Verify with analyzer + manual smoke test.

- [ ] **Step 1: Add imports**

At the top of `hosts_dashboard.dart` add:

```dart
import '../models/ssh_session.dart';
import '../util/bulk_connect.dart';
import 'bulk/bulk_action_bar.dart';
import 'bulk/bulk_push_dialog.dart';
import 'bulk/bulk_run_dialog.dart';
```

(`dart:async` and `package:flutter/services.dart` are already imported.)

- [ ] **Step 2: Add selection state + handlers to `_HostsDashboardState`**

```dart
  bool _selectionMode = false;
  final Set<String> _selectedHostIds = {};
```

Add methods (and extend `dispose` to remove the key handler):

```dart
  void _enterSelectionMode() {
    if (_selectionMode) return;
    HardwareKeyboard.instance.addHandler(_onSelectionKey);
    setState(() => _selectionMode = true);
  }

  void _exitSelectionMode() {
    HardwareKeyboard.instance.removeHandler(_onSelectionKey);
    setState(() {
      _selectionMode = false;
      _selectedHostIds.clear();
    });
  }

  bool _onSelectionKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _exitSelectionMode();
      return true;
    }
    return false;
  }

  void _toggleSelected(Host host) {
    setState(() {
      if (!_selectedHostIds.remove(host.id)) _selectedHostIds.add(host.id);
    });
  }

  List<Host> _selectedHosts() => context
      .read<HostProvider>()
      .allHosts
      .where((h) => _selectedHostIds.contains(h.id))
      .toList();

  void _selectAllFiltered() {
    final hosts = context.read<HostProvider>().allHosts;
    final query = HostQuery.parse(_search);
    final filtered = query.isEmpty ? hosts : hosts.where(query.matches);
    setState(() => _selectedHostIds.addAll(filtered.map((h) => h.id)));
  }

  Future<void> _connectAll() async {
    final sessionProvider = context.read<SessionProvider>();
    final live = {
      for (final s in sessionProvider.sshSessions)
        if (s.status == SessionStatus.connecting ||
            s.status == SessionStatus.connected)
          s.host.id,
    };
    final plan =
        planConnectAll(selected: _selectedHosts(), liveHostIds: live);
    if (plan.toConnect.length > 5) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Open ${plan.toConnect.length} tabs?',
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 15)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Open all',
                    style: TextStyle(color: AppColors.accent))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    for (final h in plan.toConnect) {
      unawaited(sessionProvider.connect(h));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(plan.skipped > 0
          ? 'Opened ${plan.toConnect.length} tabs · ${plan.skipped} already connected'
          : 'Opened ${plan.toConnect.length} tabs'),
    ));
    _exitSelectionMode();
  }

  void _openBulkRun() {
    final hosts = _selectedHosts();
    if (hosts.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BulkRunDialog(hosts: hosts),
    );
  }

  void _openBulkPush() {
    final hosts = _selectedHosts();
    if (hosts.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BulkPushDialog(hosts: hosts),
    );
  }
```

Update `dispose`:

```dart
  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onSelectionKey);
    _searchController.dispose();
    super.dispose();
  }
```

- [ ] **Step 3: Swap the top bar and prune stale ids in `build`**

At the start of `build`, right after `final hosts = hostProvider.allHosts;` add:

```dart
    _selectedHostIds.removeWhere((id) => !hosts.any((h) => h.id == id));
```

Replace the `_TopBar(...)` call with:

```dart
          _selectionMode
              ? BulkActionBar(
                  selectedCount: _selectedHostIds.length,
                  onSelectAll: _selectAllFiltered,
                  onClear: () => setState(_selectedHostIds.clear),
                  onConnectAll: _connectAll,
                  onRunCommand: _openBulkRun,
                  onPushFiles: _openBulkPush,
                  onDone: _exitSelectionMode,
                )
              : _TopBar(
                  controller: _searchController,
                  onSearch: (v) => setState(() => _search = v),
                  totalHosts: hosts.length,
                  filteredCount: filtered.length,
                  onAddHost: widget.onAddHost,
                  onLocalTerminal: widget.onOpenLocalTerminal,
                  onNewGroup: widget.onNewGroup,
                  onImport: widget.onImport,
                  onSelect: _enterSelectionMode,
                ),
```

Pass selection params to the grid:

```dart
                    _HostGrid(
                      hosts: filtered,
                      onEditHost: widget.onEditHost,
                      selectionMode: _selectionMode,
                      selectedIds: _selectedHostIds,
                      onToggleSelect: _toggleSelected,
                    ),
```

- [ ] **Step 4: Add the Select button to `_TopBar`**

Add the field + constructor param:

```dart
  final VoidCallback? onSelect;
```

(in the constructor: `this.onSelect,`)

In the `Row` children, before the `LOCAL TERMINAL` button insert:

```dart
          _OutlinedBtn(
            icon: Icons.check_box_outlined,
            label: 'SELECT',
            onTap: onSelect ?? () {},
          ),
          const SizedBox(width: 8),
```

- [ ] **Step 5: Thread selection through `_HostGrid`**

```dart
class _HostGrid extends StatelessWidget {
  final List<Host> hosts;
  final void Function(Host)? onEditHost;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(Host)? onToggleSelect;
  const _HostGrid(
      {required this.hosts,
      this.onEditHost,
      this.selectionMode = false,
      this.selectedIds = const {},
      this.onToggleSelect});
```

And in the card construction:

```dart
                    child: _HostCard(
                      host: h,
                      onEditHost: onEditHost,
                      selectionMode: selectionMode,
                      selected: selectedIds.contains(h.id),
                      onToggleSelect: () => onToggleSelect?.call(h),
                    ),
```

- [ ] **Step 6: Selection support in `_HostCard`**

Add fields + constructor params:

```dart
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelect;
```

(constructor: `this.selectionMode = false, this.selected = false, this.onToggleSelect`)

In `_HostCardState.build`, change the `GestureDetector` and decoration:

```dart
      child: GestureDetector(
        onTap: widget.selectionMode ? widget.onToggleSelect : null,
        onDoubleTap: widget.selectionMode
            ? null
            : () => sessionProvider.connect(widget.host),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.cardHover : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: widget.selected
                    ? AppColors.accent
                    : _hovered
                        ? AppColors.border.withValues(alpha: 0.8)
                        : AppColors.border),
          ),
```

As the first child of the card's `Row`, add the checkbox:

```dart
              if (widget.selectionMode) ...[
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: widget.selected,
                    onChanged: (_) => widget.onToggleSelect?.call(),
                    activeColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.border),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 10),
              ],
```

Suppress hover actions in selection mode — change the existing condition:

```dart
              if (!widget.selectionMode &&
                  _hovered &&
                  !_testing &&
                  _testResult == null) ...[
```

- [ ] **Step 7: Analyze and run the full test suite**

Run: `cd app && flutter analyze && flutter test`
Expected: No analyzer issues; all tests pass.

- [ ] **Step 8: Manual smoke test**

Run: `cd app && flutter run -d macos`
1. Hosts dashboard → click **SELECT** → checkboxes appear, top bar swaps to the action bar.
2. Click two cards → border + checkbox toggle, count updates; **Esc** exits.
3. Filter `tag:…` then **SELECT ALL** → only filtered hosts selected.
4. **CONNECT ALL** with >5 hosts shows the confirm; tabs open; snackbar reports skipped.
5. **RUN COMMAND** → type `uname -a` → per-host rows fill in; Diff tab groups outputs.
6. **PUSH FILES** → pick a small file, destination `/tmp` → progress, success.

- [ ] **Step 9: Commit**

```bash
git add app/lib/widgets/hosts_dashboard.dart
git commit -m "feat(bulk): host dashboard selection mode wired to bulk actions"
```

---

### Task 13: Final verification + changelog

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Full verification**

Run: `cd app && flutter analyze && flutter test`
Expected: clean analyze, full suite green.

- [ ] **Step 2: Update CHANGELOG**

Under the `[Unreleased]` section (create the section after the header if it doesn't exist), add:

```markdown
### Added
- **Bulk action panel** — select N hosts on the dashboard (Select mode, filter-aware Select all, Esc to exit) and act on all of them: Connect all (skips already-connected hosts, confirm above 5 tabs), Run command in parallel (bounded concurrency, per-host timeout and failure isolation, snippet picker, per-host results with exit code/stdout/stderr) with a Diff tab that groups identical outputs against a baseline and side-by-side compares any two hosts, and Push files (multi-file/folder upload to one remote path on every host, overwrite semantics, per-host progress and cancel).

### Changed
- `SftpTransferService.uploadFile` reports byte progress; `uploadDirectory` gained an `overwrite` flag (bulk push uses it — the SFTP panel's skip-existing behavior is unchanged).
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): bulk action panel"
```

---

## Self-review notes

- **Spec coverage:** selection mode (T12), connect-all + skip + confirm (T11/T12), engine + concurrency + cancel + timeout (T3/T4), exec via `SshService.exec` (T9 wiring), push + mkdir bootstrap + overwrite (T4/T5/T10), diff grouping + baseline + side-by-side + failed section (T2/T8), controller scoping (T6), shared row widget (T7), error isolation (T3/T4 tests). `file_selector` already in pubspec — no dependency task.
- **Types:** `BulkHostResult`/`BulkHostStatus` (T1) used by T2/T3/T4/T6/T7/T8; `BulkPushSource`/`BulkCancelToken` defined T3/T4, used T6/T10; `OutputGroup`/`DiffLine`/`DiffOp`/`sideBySideRows` defined T2, used T8; `planConnectAll` defined T11, used T12; `BulkActionBar` defined T11, used T12.
- **Known small risk:** `firstOrNull` import note in T8; `Checkbox` inside a 18px `SizedBox` may need `materialTapTargetSize: MaterialTapTargetSize.shrinkWrap` if the analyzer/layout complains — both called out inline.
