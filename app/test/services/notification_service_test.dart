import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/notification_service.dart';

void main() {
  group('NotificationService', () {
    late List<({String title, String body})> systemNotifications;
    late List<String> toasts;
    late NotificationService svc;

    setUp(() {
      systemNotifications = [];
      toasts = [];
      svc = NotificationService.forTest(
        debounce: Duration.zero,
        cooldown: const Duration(seconds: 5),
        onSystemNotify: (title, body) => systemNotifications.add((title: title, body: body)),
      );
      svc.enabled = true; // default is off; tests exercise the enabled path
      svc.onToast = (label) => toasts.add(label);
    });

    tearDown(() {
      svc.dispose();
    });

    test('detects bash prompt (\$ )', () async {
      svc.onWindowBlur();
      svc.onTerminalData('output\nuser@host:~\$ ', sessionId: 's1', sessionLabel: 'prod');
      await Future.delayed(Duration.zero);
      expect(systemNotifications.length, 1);
      expect(systemNotifications[0].title, 'YourSSH — Command finished');
      expect(systemNotifications[0].body, 'prod');
    });

    test('detects root prompt (# )', () async {
      svc.onWindowBlur();
      svc.onTerminalData('output\nroot@host:~# ', sessionId: 's1', sessionLabel: 'server');
      await Future.delayed(Duration.zero);
      expect(systemNotifications.length, 1);
    });

    test('detects zsh prompt (% )', () async {
      svc.onWindowBlur();
      svc.onTerminalData('output\nuser@host % ', sessionId: 's1', sessionLabel: 'mac');
      await Future.delayed(Duration.zero);
      expect(systemNotifications.length, 1);
    });

    test('detects zsh arrow prompt (❯)', () async {
      svc.onWindowBlur();
      svc.onTerminalData('output\n❯ ', sessionId: 's1', sessionLabel: 'zsh');
      await Future.delayed(Duration.zero);
      expect(systemNotifications.length, 1);
    });

    test('strips ANSI escape codes before matching', () async {
      svc.onWindowBlur();
      svc.onTerminalData('\x1B[32muser@host\x1B[0m:\x1B[34m~\x1B[0m\$ ', sessionId: 's1', sessionLabel: 'ansi');
      await Future.delayed(Duration.zero);
      expect(systemNotifications.length, 1);
    });

    test('no match on non-prompt output', () async {
      svc.onWindowBlur();
      svc.onTerminalData('Hello world\nSome output line', sessionId: 's1', sessionLabel: 'prod');
      await Future.delayed(Duration.zero);
      expect(systemNotifications, isEmpty);
    });

    test('uses toast when window is focused', () async {
      svc.onWindowFocus();
      svc.onTerminalData('done\nuser@host\$ ', sessionId: 's1', sessionLabel: 'prod');
      await Future.delayed(Duration.zero);
      expect(toasts, ['prod']);
      expect(systemNotifications, isEmpty);
    });

    test('no notification when enabled=false', () async {
      svc.enabled = false;
      svc.onWindowBlur();
      svc.onTerminalData('done\nuser@host\$ ', sessionId: 's1', sessionLabel: 'prod');
      await Future.delayed(Duration.zero);
      expect(systemNotifications, isEmpty);
      expect(toasts, isEmpty);
    });

    test('cooldown prevents second notification within 5 seconds', () async {
      svc.onWindowBlur();
      svc.onTerminalData('user@host\$ ', sessionId: 's1', sessionLabel: 'prod');
      await Future.delayed(Duration.zero);
      svc.onTerminalData('user@host\$ ', sessionId: 's1', sessionLabel: 'prod');
      await Future.delayed(Duration.zero);
      expect(systemNotifications.length, 1);
    });

    test('different sessions each get their own notification', () async {
      svc.onWindowBlur();
      svc.onTerminalData('user@host\$ ', sessionId: 's1', sessionLabel: 'prod');
      await Future.delayed(Duration.zero);
      svc.onTerminalData('user@host\$ ', sessionId: 's2', sessionLabel: 'staging');
      await Future.delayed(Duration.zero);
      expect(systemNotifications.length, 2);
    });

    test('removeSession clears cooldown so next prompt notifies again', () async {
      svc.onWindowBlur();
      // First notification sets cooldown
      svc.onTerminalData('user@host\$ ', sessionId: 's1', sessionLabel: 'prod');
      await Future.delayed(Duration.zero);
      expect(systemNotifications.length, 1);
      // Remove clears cooldown
      svc.removeSession('s1');
      // Should notify again
      svc.onTerminalData('user@host\$ ', sessionId: 's1', sessionLabel: 'prod');
      await Future.delayed(Duration.zero);
      expect(systemNotifications.length, 2);
    });
  });
}
