import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/known_host.dart';
import 'package:yourssh/providers/known_hosts_provider.dart';

void main() {
  test('rdp pin: first sight unknown, accept stores, mismatch detected', () async {
    final p = KnownHostsProvider.forTest([]);

    expect(p.verifyRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'aa'),
        RdpCertVerdict.unknown);

    await p.acceptRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'aa');

    expect(p.verifyRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'aa'),
        RdpCertVerdict.trusted);
    expect(p.verifyRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'bb'),
        RdpCertVerdict.mismatch);
  });

  test('rdp pin: accept overwrites previous pin', () async {
    final p = KnownHostsProvider.forTest([]);

    await p.acceptRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'aa');
    await p.acceptRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'bb');

    expect(p.verifyRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'aa'),
        RdpCertVerdict.mismatch);
    expect(p.verifyRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'bb'),
        RdpCertVerdict.trusted);
  });

  test('rdp pin: different port is independent', () async {
    final p = KnownHostsProvider.forTest([]);

    await p.acceptRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'aa');

    // Same host, different port — unknown.
    expect(p.verifyRdpCert(host: '10.0.0.5', port: 3390, fingerprint: 'aa'),
        RdpCertVerdict.unknown);
  });

  test('rdp pin does not collide with ssh entries', () async {
    final p = KnownHostsProvider.forTest([
      KnownHost(
        host: '10.0.0.5',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: 'aa',
        addedAt: DateTime(2025),
        protocol: 'ssh',
      ),
    ]);

    // SSH entry at same host (different port) should not satisfy RDP lookup.
    expect(p.verifyRdpCert(host: '10.0.0.5', port: 22, fingerprint: 'aa'),
        RdpCertVerdict.unknown);
  });

  test('challengeRdpCert: resolving true accepts and stores cert', () async {
    final p = KnownHostsProvider.forTest([]);

    final future = p.challengeRdpCert(
        host: 'srv', port: 3389, fingerprint: 'fp1', isMismatch: false);

    // Challenge should be pending.
    expect(p.pendingRdpChallenge, isNotNull);
    expect(p.pendingRdpChallenge!.fingerprint, 'fp1');

    p.pendingRdpChallenge!.resolve(true);
    final result = await future;

    expect(result, isTrue);
    expect(p.verifyRdpCert(host: 'srv', port: 3389, fingerprint: 'fp1'),
        RdpCertVerdict.trusted);
    expect(p.pendingRdpChallenge, isNull);
  });

  test('challengeRdpCert: resolving false does not store cert', () async {
    final p = KnownHostsProvider.forTest([]);

    final future = p.challengeRdpCert(
        host: 'srv', port: 3389, fingerprint: 'fp1', isMismatch: false);

    p.pendingRdpChallenge!.resolve(false);
    final result = await future;

    expect(result, isFalse);
    expect(p.verifyRdpCert(host: 'srv', port: 3389, fingerprint: 'fp1'),
        RdpCertVerdict.unknown);
  });

  test('remove() deletes an RDP pin (does not require ssh protocol)', () async {
    final p = KnownHostsProvider.forTest([]);
    await p.acceptRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'aa');

    final pin = p.hosts.single;
    await p.remove(pin);

    expect(p.hosts, isEmpty);
    expect(p.verifyRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'aa'),
        RdpCertVerdict.unknown);
  });

  test('remove() of an RDP pin leaves the SSH row for the same endpoint',
      () async {
    final ssh = KnownHost(
      host: '10.0.0.5',
      port: 3389, // same endpoint on purpose
      keyType: 'ssh-ed25519',
      fingerprint: 'bb',
      addedAt: DateTime(2025),
    );
    final p = KnownHostsProvider.forTest([ssh]);
    await p.acceptRdpCert(host: '10.0.0.5', port: 3389, fingerprint: 'aa');

    final pin =
        p.hosts.firstWhere((h) => h.protocol == KnownHost.protocolRdp);
    await p.remove(pin);

    expect(p.hosts.single.keyType, 'ssh-ed25519');
  });

  test('pinnedRdpFingerprint returns the pin or null', () async {
    final p = KnownHostsProvider.forTest([]);
    expect(p.pinnedRdpFingerprint('srv', 3389), isNull);
    await p.acceptRdpCert(host: 'srv', port: 3389, fingerprint: 'fp1');
    expect(p.pinnedRdpFingerprint('srv', 3389), 'fp1');
    expect(p.pinnedRdpFingerprint('srv', 3390), isNull);
  });
}
