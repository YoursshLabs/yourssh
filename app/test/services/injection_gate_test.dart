import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/injection_gate.dart';

void main() {
  group('InjectionReadiness', () {
    test('bracketed-paste ON means the line editor is reading', () {
      final r = InjectionReadiness();
      r.onChunk('prompt stuff \x1b[?2004h');
      expect(r.bpOn, isTrue);
      expect(r.bpEver, isTrue);
    });

    test('bracketed-paste OFF after ON means executing, not reading', () {
      final r = InjectionReadiness();
      r.onChunk('\x1b[?2004h');
      r.onChunk('\x1b[?2004l running command');
      expect(r.bpOn, isFalse);
      expect(r.bpEver, isTrue);
    });

    test('last toggle in a chunk wins', () {
      final r = InjectionReadiness();
      r.onChunk('\x1b[?2004h\x1b[?2004l\x1b[?2004h');
      expect(r.bpOn, isTrue);
    });

    test('toggle split across chunks still detected', () {
      final r = InjectionReadiness();
      r.onChunk('text\x1b[?20');
      r.onChunk('04h');
      expect(r.bpOn, isTrue);
    });

    test('alt-screen entry is reported (full-screen app owns the tty)', () {
      final r = InjectionReadiness();
      expect(r.onChunk('\x1b[?1049h'), ReadinessSignal.altScreen);
      expect(InjectionReadiness().onChunk('\x1b[?47h'),
          ReadinessSignal.altScreen);
    });

    test('plain output is no signal', () {
      final r = InjectionReadiness();
      expect(r.onChunk('Last login: Wed\n'), ReadinessSignal.none);
      expect(r.bpOn, isFalse);
      expect(r.bpEver, isFalse);
    });

    group('promptLikeTail', () {
      test('classic prompts match', () {
        expect(InjectionReadiness.promptLikeTail('bash-3.2\$ '), isTrue);
        expect(InjectionReadiness.promptLikeTail('\r\nuser@host:~\$ '), isTrue);
        expect(InjectionReadiness.promptLikeTail('root@box:/# '), isTrue);
        expect(InjectionReadiness.promptLikeTail('❯ '), isTrue);
      });
      test('escape sequences are ignored when finding the tail', () {
        expect(
            InjectionReadiness.promptLikeTail(
                '\x1b[1muser\x1b[0m@host \$ \x1b[K'),
            isTrue);
      });
      test('mid-line MOTD stall does not match', () {
        expect(InjectionReadiness.promptLikeTail('Last login:'), isFalse);
        expect(InjectionReadiness.promptLikeTail('banner text\n'), isFalse);
        expect(InjectionReadiness.promptLikeTail(''), isFalse);
        expect(InjectionReadiness.promptLikeTail('\x1b[0m\r\n'), isFalse);
      });
    });
  });

  InjectionGate gate({int maxHold = 2048}) => InjectionGate(
      readySentinel: '__YS_RDY__',
      doneSentinel: '__YS_DONE__',
      maxHold: maxHold);

  test('withholds output until DONE', () {
    final g = gate();
    expect(g.feed('motd echo').emit, isNull);
    expect(g.isHolding, isTrue);
  });

  test('RDY triggers sendPayload exactly once', () {
    final g = gate();
    expect(g.feed('x__YS_RDY__').sendPayload, isTrue);
    expect(g.feed('more __YS_RDY__ again').sendPayload, isFalse);
  });

  test('RDY split across chunks still triggers', () {
    final g = gate();
    expect(g.feed('echo __YS_R').sendPayload, isFalse);
    expect(g.feed('DY__').sendPayload, isTrue);
  });

  test('DONE discards the echo head and emits only the tail', () {
    // The held head is just the bootstrap echo + RDY — junk. Never write it;
    // erasing it after the fact desyncs the app cursor from the remote's.
    final g = gate();
    g.feed('echo__YS_RDY__noise');
    final r = g.feed('more__YS_DONE__\ntail');
    expect(r.emit, '\ntail');
    expect(g.isHolding, isFalse);
  });

  test('oversized head means real output got held — emit it, stripped', () {
    // Late MOTD landed inside the hold window. Showing it (rendered exactly
    // as if it was never held) beats silently swallowing server output.
    final g = gate(maxHold: 10);
    g.feed('A' * 11);
    final r = g.feed('__YS_RDY____YS_DONE__tail');
    expect(r.emit, '${'A' * 11}tail');
    expect(r.sendPayload, isTrue);
  });

  test('DONE without RDY (non-bash/zsh) discards echo without payload', () {
    final g = gate();
    final r = g.feed('echo__YS_DONE__');
    expect(r.emit, '');
    expect(r.sendPayload, isFalse);
    expect(g.isHolding, isFalse);
  });

  test('RDY and DONE in the same chunk sends payload and emits tail', () {
    final g = gate();
    final r = g.feed('__YS_RDY____YS_DONE__tail');
    expect(r.sendPayload, isTrue);
    expect(r.emit, 'tail');
  });

  test('DONE split across chunks still completes', () {
    final g = gate();
    g.feed('__YS_RDY__x__YS_DO');
    final r = g.feed('NE__after');
    expect(r.emit, 'after');
    expect(g.isHolding, isFalse);
  });

  test('passthrough after DONE', () {
    final g = gate();
    g.feed('__YS_DONE__');
    expect(g.feed('hello').emit, 'hello');
  });

  test('flush releases held text and stops gating', () {
    final g = gate();
    g.feed('partial __YS_R');
    expect(g.flush(), 'partial __YS_R');
    expect(g.isHolding, isFalse);
    expect(g.feed('after').emit, 'after');
  });

  test('heldLength tracks the withheld buffer', () {
    final g = gate();
    g.feed('12345');
    expect(g.heldLength, 5);
  });
}
