import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_script_engine/src/permission_guard.dart';

void main() {
  test('allows call when permission granted', () {
    final guard = PermissionGuard(
        pluginId: 'test', granted: {'ssh.exec', 'terminal.transform'});
    expect(() => guard.require('ssh.exec'), returnsNormally);
  });

  test('throws PermissionDeniedException when not granted', () {
    final guard = PermissionGuard(pluginId: 'test', granted: {});
    expect(() => guard.require('ssh.exec'),
        throwsA(isA<PermissionDeniedException>()));
  });

  test('has() returns true for granted permission', () {
    final guard = PermissionGuard(pluginId: 'test', granted: {'ui.notify'});
    expect(guard.has('ui.notify'), true);
    expect(guard.has('ssh.exec'), false);
  });
}
