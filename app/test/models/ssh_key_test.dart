import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/ssh_key.dart';

void main() {
  group('SshKeyEntry', () {
    test('toJson/fromJson round-trips certificatePath', () {
      final entry = SshKeyEntry(
        label: 'my-key',
        algorithm: KeyAlgorithm.ed25519,
        publicKey: 'ssh-ed25519 AAAA',
        privateKeyPath: '/home/user/.ssh/id_ed25519',
        certificatePath: '/home/user/.ssh/id_ed25519-cert.pub',
      );
      final decoded = SshKeyEntry.fromJson(entry.toJson());
      expect(decoded.certificatePath, '/home/user/.ssh/id_ed25519-cert.pub');
    });

    test('fromJson without certificatePath returns null', () {
      final json = {
        'id': 'x', 'label': 'x', 'algorithm': 'ed25519',
        'publicKey': '', 'privateKeyPath': '/tmp/key',
        'addedAt': DateTime.now().toIso8601String(),
      };
      final entry = SshKeyEntry.fromJson(json);
      expect(entry.certificatePath, isNull);
    });
  });
}
