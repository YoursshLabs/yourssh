import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/shell_integration_service.dart';

void main() {
  final svc = ShellIntegrationService();

  group('shQuote', () {
    test('wraps in single quotes', () {
      expect(ShellIntegrationService.shQuote('abc'), "'abc'");
    });

    test('escapes embedded single quotes', () {
      expect(ShellIntegrationService.shQuote("it's"), r"'it'\''s'");
    });

    test('strips control chars — payload must stay one line', () {
      expect(ShellIntegrationService.shQuote('a\nb\tc'), "'abc'");
    });
  });

  group('isValidEnvKey', () {
    test('accepts POSIX names', () {
      for (final k in ['FOO', '_FOO', 'F00_BAR', 'a']) {
        expect(ShellIntegrationService.isValidEnvKey(k), isTrue, reason: k);
      }
    });

    test('rejects invalid names', () {
      for (final k in ['1FOO', 'FOO-BAR', '', 'FOO BAR', 'FOO=']) {
        expect(ShellIntegrationService.isValidEnvKey(k), isFalse, reason: k);
      }
    });
  });

  group('buildPayloadLine', () {
    test('defaults are byte-identical to the legacy installer payload', () {
      // No template → existing shell-integration behavior must not change.
      expect(svc.buildPayloadLine(workingDir: null, envVars: const {}),
          svc.buildPayloadLine());
      expect(svc.buildPayloadLine(), contains('__yourssh_si'));
      expect(svc.buildPayloadLine(), contains(r"printf '__YS_%s__\n' DONE"));
    });

    test('orders installer → cd → exports → DONE → warning', () {
      final line = svc.buildPayloadLine(
          workingDir: '/srv/app', envVars: {'FOO': 'a', 'BAR': 'b'});
      final idx = [
        line.indexOf('__yourssh_si'),
        line.indexOf("cd -- '/srv/app' 2>/dev/null"),
        line.indexOf("export FOO='a'"),
        line.indexOf("export BAR='b'"),
        line.indexOf(r"printf '__YS_%s__\n' DONE"),
        line.indexOf('working dir not found'),
      ];
      for (var i = 0; i < idx.length; i++) {
        expect(idx[i], greaterThanOrEqualTo(0), reason: 'part $i missing');
        if (i > 0) expect(idx[i], greaterThan(idx[i - 1]), reason: 'order $i');
      }
    });

    test('includeInstaller: false omits the SI installer', () {
      final line = svc.buildPayloadLine(
          includeInstaller: false, workingDir: '/srv/app');
      expect(line, isNot(contains('__yourssh_si')));
      expect(line, contains("cd -- '/srv/app'"));
    });

    test('cd failure flag wires to a post-DONE warning', () {
      final line = svc.buildPayloadLine(workingDir: '/nope');
      expect(line, contains('|| __ys_td=1'));
      expect(line, contains(r'[ -n "$__ys_td" ]'));
      expect(line, contains('unset __ys_td'));
      // Warning strictly after DONE so it survives the gate discard.
      expect(line.indexOf('working dir not found'),
          greaterThan(line.indexOf(r"printf '__YS_%s__\n' DONE")));
    });

    test('no cd flag machinery without a workingDir', () {
      expect(svc.buildPayloadLine(envVars: {'A': '1'}),
          isNot(contains('__ys_td')));
    });

    test('skips invalid env keys (defense in depth)', () {
      final line = svc.buildPayloadLine(envVars: {'BAD-KEY': 'x', 'OK': 'y'});
      expect(line, isNot(contains('BAD-KEY')));
      expect(line, contains("export OK='y'"));
    });

    test('quotes dir and values', () {
      final line = svc.buildPayloadLine(
          workingDir: "/data/o'brien", envVars: {'MSG': "it's"});
      expect(line, contains(r"cd -- '/data/o'\''brien'"));
      expect(line, contains(r"export MSG='it'\''s'"));
    });

    test('payload is a single line ending in newline', () {
      final line = svc.buildPayloadLine(
          workingDir: '/srv', envVars: {'A': '1', 'B': '2'});
      expect(line.endsWith('\n'), isTrue);
      expect(line.indexOf('\n'), line.length - 1);
    });

    test('blank workingDir is treated as unset', () {
      expect(svc.buildPayloadLine(workingDir: '  '), svc.buildPayloadLine());
    });
  });
}
