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

  group('buildBootstrapLine', () {
    final boot = s.buildBootstrapLine();
    test('is one short line guarded on bash/zsh', () {
      expect('\n'.allMatches(boot).length, 1); // trailing newline only
      expect(boot.endsWith('\n'), isTrue);
      expect(boot, contains(r'$BASH_VERSION$ZSH_VERSION'));
      expect(boot.length, lessThan(220)); // must stay short: its echo can wrap
    });
    test('reads payload silently and evals it', () {
      expect(boot, contains('IFS= read -rs __ys'));
      expect(boot, contains(r'eval "$__ys"'));
      expect(boot, contains('unset __ys'));
      // Echo must be off BEFORE RDY is printed (race: payload can arrive
      // before `read -s` flips the tty), and restored afterwards.
      expect(boot.indexOf('stty -echo'), lessThan(boot.indexOf('RDY')));
      expect(boot, contains('stty echo 2>/dev/null'));
    });
    test('sentinel literals never appear in the bootstrap source (echo-safe)', () {
      // printf '__YS_%s__' RDY builds the sentinel at runtime, so scanning the
      // output stream can never false-positive on the echoed command line.
      expect(boot, isNot(contains(ShellIntegrationService.kReadySentinel)));
      expect(boot, isNot(contains(ShellIntegrationService.kDoneSentinel)));
      expect(boot, contains("printf '__YS_%s__' RDY"));
      // Non-bash/zsh branch; the \n lands both sides on a fresh line (col 0)
      // so the next prompt renders consistently after the head is discarded.
      expect(boot, contains(r"printf '__YS_%s__\n' DONE"));
    });
  });

  group('buildPayloadLine', () {
    final payload = s.buildPayloadLine();
    test('is the hook installer terminated by the DONE printf', () {
      expect('\n'.allMatches(payload).length, 1);
      expect(payload.endsWith("printf '__YS_%s__\\n' DONE\n"), isTrue);
      // Hook-installer body is unchanged.
      final body = s.buildInjectionScript();
      expect(payload, startsWith(body.substring(0, body.length - 1)));
    });
    test('sentinel literal never appears in the payload source', () {
      expect(payload, isNot(contains(ShellIntegrationService.kDoneSentinel)));
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
