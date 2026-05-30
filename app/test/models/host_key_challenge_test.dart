import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/known_host.dart';

void main() {
  group('HostKeyChallenge timeout', () {
    test('resolves to false after 2 minutes if no UI response', () {
      fakeAsync((async) {
        final challenge = HostKeyChallenge(
          host: 'example.com',
          port: 22,
          keyType: 'ssh-ed25519',
          oldFingerprint: 'aa:bb',
          newFingerprint: 'cc:dd',
        );

        bool? trusted;
        challenge.result.then((v) => trusted = v);

        async.elapse(const Duration(seconds: 119));
        expect(trusted, isNull, reason: 'should not resolve before 2 min');

        async.elapse(const Duration(seconds: 2));
        expect(trusted, isFalse,
            reason: 'timeout must auto-reject so the connect future is unblocked');
      });
    });

    test('explicit resolve(true) wins over the timeout', () {
      fakeAsync((async) {
        final challenge = HostKeyChallenge(
          host: 'example.com',
          port: 22,
          keyType: 'ssh-ed25519',
          oldFingerprint: 'aa:bb',
          newFingerprint: 'cc:dd',
        );

        bool? trusted;
        challenge.result.then((v) => trusted = v);

        async.elapse(const Duration(seconds: 5));
        challenge.resolve(true);
        async.flushMicrotasks();
        expect(trusted, isTrue);

        // Even after the 2-min mark, the resolved value sticks.
        async.elapse(const Duration(minutes: 5));
        expect(trusted, isTrue);
      });
    });

    test('reject() is idempotent', () {
      final challenge = HostKeyChallenge(
        host: 'example.com',
        port: 22,
        keyType: 'ssh-ed25519',
        oldFingerprint: 'aa:bb',
        newFingerprint: 'cc:dd',
      );
      challenge.reject();
      // Second call must not throw (Completer can't complete twice).
      expect(() => challenge.reject(), returnsNormally);
    });
  });
}
