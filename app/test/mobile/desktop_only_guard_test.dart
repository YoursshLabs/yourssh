import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flutter_pty fork no longer declares an iOS platform', () {
    final y = File('../packages/flutter_pty/pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^\s+ios:', multiLine: true).hasMatch(y), isFalse);
  });

  test('app/lib/mobile imports no desktop-only module', () {
    const banned = [
      "/main.dart'", 'main_screen.dart', 'single_instance.dart',
      'cli_listener', 'peer_cred.dart', 'app_cli_handlers.dart',
      'update_service.dart', 'update_provider.dart', 'local_shell_service.dart',
      'pty_runner.dart', '/recording_', '/audit_', '/plugin_',
      'yourssh_script_engine', 'window_manager', 'hotkey_manager',
      'local_notifier',
    ];
    final offenders = [
      for (final f in Directory('lib/mobile')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        for (final l
            in f.readAsLinesSync().where((l) => l.startsWith('import ')))
          if (banned.any(l.contains)) '${f.path}: $l',
    ];
    expect(offenders, isEmpty);
  });

  test('main() returns for mobile before any desktop start-up', () {
    final src = File('lib/main.dart').readAsStringSync();
    final start = src.indexOf('void main(');
    final mobile = src.indexOf('runApp(const YourSSHMobileApp())', start);
    expect(mobile, greaterThan(start));
    for (final call in [
      'claimSingleInstance(',
      '_migrateSandboxContainer(',
      'windowManager.ensureInitialized',
      'NotificationService.init',
    ]) {
      expect(src.indexOf(call, start), greaterThan(mobile), reason: call);
    }
  });
}
