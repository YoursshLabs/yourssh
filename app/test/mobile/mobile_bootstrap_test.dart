import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/mobile_bootstrap.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('constructs services and wires SessionProvider callbacks', () {
    final b = MobileBootstrap();

    // Connect-critical callbacks must be wired.
    expect(b.sessions.keyLookup, isNotNull);
    expect(b.sessions.hostKeyVerifier, isNotNull);
    expect(b.sessions.autoReconnectEnabled, isNotNull);
    expect(b.sessions.terminalType, isNotNull);
    expect(b.ssh.defaultHostKeyVerifier, isNotNull);
    expect(b.ssh.defaultKeyLookup, isNotNull);

    // Exposes a provider list for the widget tree.
    expect(b.providers, isNotEmpty);
  });
}
