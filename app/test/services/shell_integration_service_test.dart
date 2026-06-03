import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/shell_integration_service.dart';

void main() {
  final s = ShellIntegrationService();

  group('parseOsc7Path', () {
    test('strips scheme + host, decodes percent-encoding', () {
      expect(ShellIntegrationService.parseOsc7Path('file://myhost/home/u/my%20proj'),
          '/home/u/my proj');
    });
    test('handles empty host (file:///path)', () {
      expect(ShellIntegrationService.parseOsc7Path('file:///var/log'), '/var/log');
    });
    test('rejects non-file urls', () {
      expect(ShellIntegrationService.parseOsc7Path('http://x/y'), isNull);
    });
  });

  group('parseOsc', () {
    test('OSC 7 -> cwd', () {
      final e = s.parseOsc('7', ['file://h/srv/app'])!;
      expect(e.kind, ShellOscKind.cwd);
      expect(e.cwd, '/srv/app');
    });
    test('OSC 7 with ";" in path is rejoined (xterm splits on ;)', () {
      expect(s.parseOsc('7', ['file://h/srv/a', 'b'])!.cwd, '/srv/a;b');
    });
    test('OSC 133;A -> promptStart', () {
      expect(s.parseOsc('133', ['A'])!.kind, ShellOscKind.promptStart);
    });
    test('OSC 133;C is ignored (no exec tracking)', () {
      expect(s.parseOsc('133', ['C']), isNull);
    });
    test('OSC 133;D;0 -> finished exit 0', () {
      final e = s.parseOsc('133', ['D', '0'])!;
      expect(e.kind, ShellOscKind.finished);
      expect(e.exitCode, 0);
    });
    test('OSC 133;D (no code) -> finished null exit', () {
      expect(s.parseOsc('133', ['D'])!.exitCode, isNull);
    });
    test('OSC 133;B and unknown -> null', () {
      expect(s.parseOsc('133', ['B']), isNull);
      expect(s.parseOsc('133', ['Z']), isNull);
      expect(s.parseOsc('9', ['x']), isNull);
      expect(s.parseOsc('133', const []), isNull);
    });
  });

  group('buildInjectionScript', () {
    final script = s.buildInjectionScript();
    test('is single-line and guarded + idempotent', () {
      expect('\n'.allMatches(script).length, 1); // only trailing newline
      expect(script, contains(r'$__yourssh_si'));
    });
    test('covers bash and zsh branches', () {
      expect(script, contains(r'$ZSH_VERSION'));
      expect(script, contains(r'$BASH_VERSION'));
      expect(script, contains('precmd_functions+=('));
      expect(script, contains('PROMPT_COMMAND="__ys_post;'));
      expect(script, contains("trap 'printf \"\\033]133;C\\a\"' DEBUG"));
    });
    test('emits all OSC markers', () {
      for (final m in [r']133;A', r']133;B', r']133;C', r']133;D', r']7;file://']) {
        expect(script, contains(m));
      }
    });
  });
}
