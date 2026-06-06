// One-shot interop check: writes generated keys for `ssh-keygen -y` to read.
// Run: dart run tool/interop_keygen_check.dart && ssh-keygen -y -P pp -f /tmp/ys_test_key
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

void main() {
  final encrypted = OpenSSHEd25519KeyPair.generate('interop');
  File('/tmp/ys_test_key').writeAsStringSync(encrypted.toPem(passphrase: 'pp'));
  final plain = OpenSSHEd25519KeyPair.generate('interop2');
  File('/tmp/ys_test_key_plain').writeAsStringSync(plain.toPem());
  stdout.writeln('wrote /tmp/ys_test_key (encrypted) and /tmp/ys_test_key_plain');
}
