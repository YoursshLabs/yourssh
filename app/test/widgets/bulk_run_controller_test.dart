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
    await Future.wait(<Future<void>>[first, second]);
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
    await controller.runCommand('x');
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
