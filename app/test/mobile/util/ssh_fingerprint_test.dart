import 'package:flutter_test/flutter_test.dart';

import 'package:yourssh/mobile/util/ssh_fingerprint.dart';

void main() {
  // Known vector: computed once via Python's hashlib.sha256 over the raw
  // base64-decoded blob, then base64-encoded without '=' padding.
  const knownPubKey =
      'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPM4vCvRPxj8W9BoYRLsNJNMW5JCZw0DhS4OxGmwsUAZ test@example';
  const knownFingerprint = 'SHA256:HMCzWOXfDZ/SJgzrmmqFS5EObmWd6/IYky/Ck6FBoYU';

  test('returns correct SHA256 fingerprint for known key', () {
    expect(sha256Fingerprint(knownPubKey), equals(knownFingerprint));
  });

  test('works without comment field', () {
    const noComment =
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPM4vCvRPxj8W9BoYRLsNJNMW5JCZw0DhS4OxGmwsUAZ';
    expect(sha256Fingerprint(noComment), equals(knownFingerprint));
  });

  test('starts with SHA256:', () {
    expect(sha256Fingerprint(knownPubKey), startsWith('SHA256:'));
  });

  test('returns null for empty string', () {
    expect(sha256Fingerprint(''), isNull);
  });

  test('returns null for single token (no blob)', () {
    expect(sha256Fingerprint('ssh-ed25519'), isNull);
  });

  test('returns null for invalid base64 blob', () {
    expect(sha256Fingerprint('ssh-ed25519 NOT!!VALID!!BASE64'), isNull);
  });

  test('handles key with extra whitespace gracefully', () {
    final padded =
        '  ssh-ed25519   AAAAC3NzaC1lZDI1NTE5AAAAIPM4vCvRPxj8W9BoYRLsNJNMW5JCZw0DhS4OxGmwsUAZ  ';
    expect(sha256Fingerprint(padded), equals(knownFingerprint));
  });
}
