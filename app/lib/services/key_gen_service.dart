import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../util/file_mode.dart';
import 'shell_integration_service.dart';

/// Result of one key generation: both files exist on disk.
class GeneratedKey {
  final String privateKeyPath;
  final String publicKeyLine;
  const GeneratedKey(
      {required this.privateKeyPath, required this.publicKeyLine});
}

/// Generates SSH keypairs. Ed25519 is pure Dart (dartssh2 fork — no
/// external binary); RSA/ECDSA shell out to ssh-keygen, gated by
/// [probeSshKeygen]. See
/// docs/superpowers/specs/2026-06-06-ssh-key-generation-design.md.
class KeyGenService {
  static String sanitizeKeyName(String name) =>
      name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  /// ssh-copy-id-style append: `grep -qxF` keeps redeploys idempotent and
  /// the EXISTS/ADDED marker tells the deploy dialog which happened.
  static String buildDeployCommand(String publicKeyLine) {
    final quoted = ShellIntegrationService.shQuote(publicKeyLine.trim());
    return 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && '
        'if grep -qxF $quoted ~/.ssh/authorized_keys 2>/dev/null; '
        'then echo EXISTS; '
        "else printf '%s\\n' $quoted >> ~/.ssh/authorized_keys && echo ADDED; "
        'fi && chmod 600 ~/.ssh/authorized_keys';
  }

  static List<String> sshKeygenArgs({
    required String type,
    required String keyPath,
    required String comment,
    required String passphrase,
  }) =>
      [
        '-t', type,
        if (type == 'rsa') ...['-b', '4096'],
        if (type == 'ecdsa') ...['-b', '256'],
        '-f', keyPath,
        '-C', comment,
        '-N', passphrase,
      ];

  bool? _probeCache;

  /// Whether the system ssh-keygen binary exists. `-?` exits non-zero but
  /// proves the binary runs; only a missing executable throws.
  Future<bool> probeSshKeygen() async {
    if (_probeCache != null) return _probeCache!;
    try {
      await Process.run('ssh-keygen', ['-?']);
      _probeCache = true;
    } on ProcessException {
      _probeCache = false;
    }
    return _probeCache!;
  }

  Future<GeneratedKey> generateEd25519({
    required String name,
    String passphrase = '',
    required String dir,
  }) async {
    final keyPair = OpenSSHEd25519KeyPair.generate(name);
    final pem =
        keyPair.toPem(passphrase: passphrase.isEmpty ? null : passphrase);
    final publicKeyLine =
        '${keyPair.name} ${base64.encode(keyPair.toPublicKey().encode())} '
        '$name';

    final keyPath = p.join(dir, sanitizeKeyName(name));
    await File(keyPath).writeAsString(pem);
    await File('$keyPath.pub').writeAsString('$publicKeyLine\n');
    if (!Platform.isWindows) await chmodLocal(keyPath, 0x180 /* 0600 */);
    return GeneratedKey(privateKeyPath: keyPath, publicKeyLine: publicKeyLine);
  }

  Future<GeneratedKey> generateWithSshKeygen({
    required String type,
    required String name,
    String passphrase = '',
    required String dir,
  }) async {
    final keyPath = p.join(dir, sanitizeKeyName(name));
    final proc = await Process.run(
        'ssh-keygen',
        sshKeygenArgs(
            type: type,
            keyPath: keyPath,
            comment: name,
            passphrase: passphrase));
    if (proc.exitCode != 0) {
      throw Exception('ssh-keygen failed: ${proc.stderr}');
    }
    final publicKeyLine = (await File('$keyPath.pub').readAsString()).trim();
    return GeneratedKey(privateKeyPath: keyPath, publicKeyLine: publicKeyLine);
  }
}
