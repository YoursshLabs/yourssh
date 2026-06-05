import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

void main() {
  Host base() => Host(label: 'srv', host: '1.2.3.4', username: 'u');

  group('Host.agentForwarding', () {
    test('defaults to false', () {
      expect(base().agentForwarding, isFalse);
    });

    test('round-trips through JSON', () {
      final host = Host(
        label: 'srv',
        host: '1.2.3.4',
        username: 'u',
        agentForwarding: true,
      );
      final restored = Host.fromJson(host.toJson());
      expect(restored.agentForwarding, isTrue);
    });

    test('absent JSON key parses as false (backward compat)', () {
      final json = base().toJson()..remove('agentForwarding');
      final restored = Host.fromJson(json);
      expect(restored.agentForwarding, isFalse);
    });

    test('copyWith toggles and preserves', () {
      final on = base().copyWith(agentForwarding: true);
      expect(on.agentForwarding, isTrue);
      // Unrelated copyWith leaves it untouched.
      expect(on.copyWith(label: 'x').agentForwarding, isTrue);
    });
  });
}
