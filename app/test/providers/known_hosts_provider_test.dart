import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/known_host.dart';
import 'package:yourssh/providers/known_hosts_provider.dart';

// Build a Uint8List from a colon-hex string like 'aa:bb:cc'
Uint8List _fp(String hex) {
  final octets = hex.split(':');
  return Uint8List.fromList(octets.map((h) => int.parse(h, radix: 16)).toList());
}

KnownHost _entry(String host, String fp) => KnownHost(
      host: host,
      port: 22,
      keyType: 'ecdsa-sha2-nistp256',
      fingerprint: fp,
      addedAt: DateTime(2026),
    );

void main() {
  const host = 'server.example.com';
  const port = 22;
  const keyType = 'ecdsa-sha2-nistp256';

  group('verifyHostKey', () {
    test('unknown host is saved and trusted', () async {
      final provider = KnownHostsProvider.forTest([]);
      final result = await provider.verifyHostKey(host, port, keyType, _fp('aa:bb:cc'));
      expect(result, true);
      expect(provider.hosts.length, 1);
      expect(provider.hosts.first.fingerprint, 'aa:bb:cc');
    });

    test('known host with matching fingerprint is trusted', () async {
      final provider = KnownHostsProvider.forTest([_entry(host, 'aa:bb:cc')]);
      final result = await provider.verifyHostKey(host, port, keyType, _fp('aa:bb:cc'));
      expect(result, true);
      expect(provider.hosts.length, 1);
    });

    test('mismatched key creates pendingChallenge with correct fingerprints', () async {
      final provider = KnownHostsProvider.forTest([_entry(host, 'aa:bb:cc')]);
      final future = provider.verifyHostKey(host, port, keyType, _fp('dd:ee:ff'));
      expect(provider.pendingChallenge, isNotNull);
      expect(provider.pendingChallenge!.oldFingerprint, 'aa:bb:cc');
      expect(provider.pendingChallenge!.newFingerprint, 'dd:ee:ff');
      provider.pendingChallenge!.resolve(false);
      expect(await future, false);
      expect(provider.pendingChallenge, isNull);
    });

    test('trusting mismatch replaces stored fingerprint', () async {
      final provider = KnownHostsProvider.forTest([_entry(host, 'aa:bb:cc')]);
      final future = provider.verifyHostKey(host, port, keyType, _fp('dd:ee:ff'));
      provider.pendingChallenge!.resolve(true);
      final result = await future;
      expect(result, true);
      expect(provider.hosts.length, 1);
      expect(provider.hosts.first.fingerprint, 'dd:ee:ff');
    });
  });

  group('verifyHostKey — key type change for a pinned host', () {
    const ed = 'ssh-ed25519';
    const ecdsa = 'ecdsa-sha2-nistp256';

    KnownHost pinned(String keyType, String fp, {String protocol = KnownHost.protocolSsh}) =>
        KnownHost(
          host: host,
          port: port,
          keyType: keyType,
          fingerprint: fp,
          addedAt: DateTime(2026),
          protocol: protocol,
        );

    test('different key type raises a challenge and is not trusted silently', () async {
      final provider = KnownHostsProvider.forTest([pinned(ed, 'aa:bb:cc')]);
      final future = provider.verifyHostKey(host, port, ecdsa, _fp('dd:ee:ff'));
      final c = provider.pendingChallenge;
      expect(c, isNotNull, reason: 'a downgraded/switched key type must block on the user');
      expect(c!.keyType, ecdsa);
      expect(c.oldKeyType, ed);
      expect(c.oldFingerprint, 'aa:bb:cc');
      expect(c.newFingerprint, 'dd:ee:ff');
      expect(provider.hosts.length, 1, reason: 'nothing added before the user decides');
      c.resolve(false);
      expect(await future, false);
      expect(provider.hosts.length, 1);
      expect(provider.hosts.single.keyType, ed);
    });

    test('trusting adds the new entry and keeps the old one', () async {
      final provider = KnownHostsProvider.forTest([pinned(ed, 'aa:bb:cc')]);
      final future = provider.verifyHostKey(host, port, ecdsa, _fp('dd:ee:ff'));
      provider.pendingChallenge!.resolve(true);
      expect(await future, true);
      expect(provider.hosts.length, 2);
      expect(provider.hosts.firstWhere((h) => h.keyType == ed).fingerprint, 'aa:bb:cc');
      expect(provider.hosts.firstWhere((h) => h.keyType == ecdsa).fingerprint, 'dd:ee:ff');
    });

    test('same type and same fingerprint is still trusted silently', () async {
      final provider = KnownHostsProvider.forTest(
          [pinned(ed, 'aa:bb:cc'), pinned(ecdsa, 'dd:ee:ff')]);
      expect(await provider.verifyHostKey(host, port, ecdsa, _fp('dd:ee:ff')), true);
      expect(provider.pendingChallenge, isNull);
      expect(provider.hosts.length, 2);
    });

    test('same type with a changed fingerprint challenges with no type change', () async {
      final provider = KnownHostsProvider.forTest([pinned(ed, 'aa:bb:cc')]);
      final future = provider.verifyHostKey(host, port, ed, _fp('dd:ee:ff'));
      expect(provider.pendingChallenge!.oldKeyType, isNull);
      provider.pendingChallenge!.resolve(false);
      await future;
    });

    test('host with no entries is still accepted on first use (current behavior)', () async {
      final provider = KnownHostsProvider.forTest([]);
      expect(await provider.verifyHostKey(host, port, ed, _fp('aa:bb:cc')), true);
      expect(provider.pendingChallenge, isNull);
      expect(provider.hosts.length, 1);
    });

    test('an entry for another port does not trigger the type-change challenge', () async {
      final provider = KnownHostsProvider.forTest([
        KnownHost(
            host: host,
            port: 2222,
            keyType: ed,
            fingerprint: 'aa:bb:cc',
            addedAt: DateTime(2026)),
      ]);
      expect(await provider.verifyHostKey(host, port, ecdsa, _fp('dd:ee:ff')), true);
      expect(provider.pendingChallenge, isNull);
    });

    test('an RDP pin for the same host:port is ignored', () async {
      final provider = KnownHostsProvider.forTest(
          [pinned('', 'aa:bb:cc', protocol: KnownHost.protocolRdp)]);
      expect(await provider.verifyHostKey(host, port, ed, _fp('dd:ee:ff')), true);
      expect(provider.pendingChallenge, isNull);
    });
  });

  group('remove', () {
    test('removes matching entry', () async {
      final provider = KnownHostsProvider.forTest([_entry(host, 'aa:bb:cc')]);
      await provider.remove(provider.hosts.first);
      expect(provider.hosts, isEmpty);
    });
  });
}
