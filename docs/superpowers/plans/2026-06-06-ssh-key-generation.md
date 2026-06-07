# In-app SSH Key Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the Keychain Generate feature: pure-Dart Ed25519 (no ssh-keygen dependency), fixed RSA-4096/ECDSA via ssh-keygen with availability probe, encrypted OpenSSH PEM in the dartssh2 fork, copy-public-key actions, saved passphrases, and ssh-copy-id-style deploy.

**Architecture:** The dartssh2 fork gains an encrypting `toPem({passphrase})` (bcrypt-pbkdf + aes256-ctr, reusing the decrypt path's primitives) and an `OpenSSHEd25519KeyPair.generate()` factory (pinenacl lives in the fork). A new app-side `KeyGenService` wraps both generation paths + the ssh-keygen probe. UI: Generate panel reworked (probe-gated options, success state with the public key), key tiles gain copy + deploy actions, `DeployKeyDialog` appends to `authorized_keys` over `SshService.exec`.

**Tech Stack:** dartssh2 fork (pinenacl, bcrypt_pbkdf, SSHCipherType.aes256ctr), Process.run ssh-keygen, existing `shQuote`/`chmodLocal`/`AppSnack` helpers.

**Spec:** `docs/superpowers/specs/2026-06-06-ssh-key-generation-design.md`

---

## File map

| File | Change |
|---|---|
| `packages/dartssh2/lib/src/ssh_key_pair.dart` | `OpenSSHKeyPairs.encrypted` factory; mixin `toPem({String? passphrase})`; `OpenSSHEd25519KeyPair.generate()` |
| `packages/dartssh2/test/openssh_encode_test.dart` | **new** — encode round-trip tests (`dart test` in the package) |
| `app/lib/services/key_gen_service.dart` | **new** — generate Ed25519 / ssh-keygen, probe, pure helpers, deploy command builder |
| `app/test/services/key_gen_service_test.dart` | **new** |
| `app/lib/providers/key_provider.dart` | `addKeyFromFile` returns `SshKeyEntry`; `savePassphrase` callback field |
| `app/lib/main.dart` | wire `_keyProvider.savePassphrase = _storage.savePassphrase;` (line ~184) |
| `app/lib/widgets/keychain_screen.dart` | panel rework + tile copy/deploy actions; `KeychainScreen` gains optional `keyGen` test seam |
| `app/lib/widgets/deploy_key_dialog.dart` | **new** |
| `app/test/widgets/keychain_generate_test.dart` | **new** |
| `CLAUDE.md` | document KeyGenService + fork encoder |

Key facts locked during exploration: `OpenSSHEd25519KeyPair` is exported from `package:dartssh2/dartssh2.dart`; `SSHCipherType.aes256ctr.name == 'aes256-ctr'` (keySize 32, ivSize 16, blockSize 16); decrypt derives key+iv via `bcrypt_pbkdf(pass, passLen, salt, saltLen, out, outLen, rounds)`; `StorageService.savePassphrase(keyId, passphrase)` exists but StorageService is NOT in the provider tree (hence the KeyProvider callback); `chmodLocal(String path, int mode, ...)` in `app/lib/util/file_mode.dart`; existing generate panel at `keychain_screen.dart:461-691`, tile at 178-307.

All app test commands run from `app/`; fork tests run from `packages/dartssh2/`.

---

### Task 1: Fork — encrypted OpenSSH PEM + Ed25519 generate

**Files:**
- Modify: `packages/dartssh2/lib/src/ssh_key_pair.dart`
- Test: `packages/dartssh2/test/openssh_encode_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `packages/dartssh2/test/openssh_encode_test.dart`:

```dart
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:test/test.dart';

void main() {
  group('OpenSSHEd25519KeyPair.generate', () {
    test('produces a working keypair (sign round-trip via PEM)', () {
      final kp = OpenSSHEd25519KeyPair.generate('test@yourssh');
      expect(kp.publicKey.length, 32);
      expect(kp.privateKey.length, 64);
      expect(kp.comment, 'test@yourssh');

      final parsed = SSHKeyPair.fromPem(kp.toPem()).single;
      expect(parsed.name, 'ssh-ed25519');
      final sig = parsed.sign(Uint8List.fromList([1, 2, 3]));
      expect(sig.signature.length, 64);
    });

    test('two generates differ', () {
      final a = OpenSSHEd25519KeyPair.generate('a');
      final b = OpenSSHEd25519KeyPair.generate('b');
      expect(a.publicKey, isNot(equals(b.publicKey)));
    });
  });

  group('encrypted toPem', () {
    test('round-trips with the right passphrase', () {
      final kp = OpenSSHEd25519KeyPair.generate('enc@yourssh');
      final pem = kp.toPem(passphrase: 'hunter2');
      expect(SSHKeyPair.isEncryptedPem(pem), isTrue);

      final parsed = SSHKeyPair.fromPem(pem, 'hunter2').single
          as OpenSSHEd25519KeyPair;
      expect(parsed.publicKey, kp.publicKey);
      expect(parsed.privateKey, kp.privateKey);
      expect(parsed.comment, 'enc@yourssh');
    });

    test('wrong passphrase throws', () {
      final pem =
          OpenSSHEd25519KeyPair.generate('x').toPem(passphrase: 'right');
      expect(() => SSHKeyPair.fromPem(pem, 'wrong'),
          throwsA(isA<SSHKeyDecryptError>()));
    });

    test('null/empty passphrase stays unencrypted (regression pin)', () {
      final kp = OpenSSHEd25519KeyPair.generate('plain');
      expect(SSHKeyPair.isEncryptedPem(kp.toPem()), isFalse);
      expect(SSHKeyPair.isEncryptedPem(kp.toPem(passphrase: '')), isFalse);
      // Unencrypted output parses without a passphrase.
      expect(SSHKeyPair.fromPem(kp.toPem()), hasLength(1));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/dartssh2 && dart test test/openssh_encode_test.dart`
Expected: FAIL — `generate` not defined; `toPem` takes no named param.

- [ ] **Step 3: Implement in the fork**

In `packages/dartssh2/lib/src/ssh_key_pair.dart`:

1. Add the encrypted factory to `OpenSSHKeyPairs` (after `unencrypted`,
   line ~109). `Random.secure` for the salt; same kdf derivation the
   decrypt path uses:

```dart
  /// Encrypts [privateKeyBlob] with aes256-ctr; the key+IV are derived from
  /// [passphrase] via bcrypt-pbkdf — the exact inverse of
  /// [_decryptPrivateKeyBlob], so [getPrivateKeys] reads it back.
  factory OpenSSHKeyPairs.encrypted({
    required List<Uint8List> publicKeys,
    required Uint8List privateKeyBlob,
    required String passphrase,
    int rounds = 16,
  }) {
    final cipher = SSHCipherType.aes256ctr;
    final random = Random.secure();
    final salt =
        Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
    final passphraseBytes = Utf8Encoder().convert(passphrase);
    final kdfHash = Uint8List(cipher.keySize + cipher.ivSize);
    bcrypt_pbkdf(
      passphraseBytes,
      passphraseBytes.lengthInBytes,
      salt,
      salt.lengthInBytes,
      kdfHash,
      kdfHash.lengthInBytes,
      rounds,
    );
    final key = Uint8List.view(kdfHash.buffer, 0, cipher.keySize);
    final iv = Uint8List.view(kdfHash.buffer, cipher.keySize, cipher.ivSize);
    final encryptCipher = cipher.createCipher(key, iv, forEncryption: true);
    return OpenSSHKeyPairs(
      cipherName: cipher.name,
      kdfName: 'bcrypt',
      kdfOptions: OpenSSHBcryptKdfOptions(salt, rounds),
      publicKeys: publicKeys,
      privateKeyBlob: encryptCipher.processAll(privateKeyBlob),
    );
  }
```

2. Replace the mixin's `toPem` (line ~292) with the passphrase-aware
   version — encrypted blobs pad to the cipher block size, unencrypted
   keeps the historical 8:

```dart
  @override
  String toPem({String? passphrase}) {
    final writer = SSHMessageWriter();
    final checkInt = Random().nextInt(0xFFFFFFFF);

    writer.writeUint32(checkInt);
    writer.writeUint32(checkInt);
    writer.writeUtf8(name);
    writeTo(writer);

    final encrypt = passphrase != null && passphrase.isNotEmpty;
    // Encrypted blobs must pad to the cipher block size; unencrypted keeps
    // the historical 8 so existing output stays byte-identical.
    final padTo = encrypt ? SSHCipherType.aes256ctr.blockSize : 8;
    // pad with bytes 1, 2, 3, ...
    for (var i = 0; writer.length % padTo != 0; i++) {
      writer.writeUint8(i + 1);
    }

    final container = encrypt
        ? OpenSSHKeyPairs.encrypted(
            publicKeys: [toPublicKey().encode()],
            privateKeyBlob: writer.takeBytes(),
            passphrase: passphrase,
          )
        : OpenSSHKeyPairs.unencrypted(
            publicKeys: [toPublicKey().encode()],
            privateKeyBlob: writer.takeBytes(),
          );
    return container.toPem();
  }
```

3. Update the abstract declaration in `SSHKeyPair` (line ~70) to match:
   `String toPem({String? passphrase});` — and adjust the two legacy
   implementations (`RsaKeyPair`/`EcKeyPair`-derived `toPem()` at
   line ~713 area) to `String toPem({String? passphrase})` that throws
   `UnsupportedError('Passphrase encoding not supported for legacy PEM')`
   when a non-empty passphrase is passed, otherwise behaves as before.
   (Grep `String toPem()` in the file to catch every implementor.)

4. Add the generate factory to `OpenSSHEd25519KeyPair` (after its
   constructor, line ~399):

```dart
  /// Generates a fresh keypair. pinenacl's [ed25519.SigningKey.generate]
  /// uses the platform CSPRNG; the OpenSSH private field is the 64-byte
  /// seed‖publicKey form that [readFrom]/[sign] already expect.
  factory OpenSSHEd25519KeyPair.generate([String comment = '']) {
    final signing = ed25519.SigningKey.generate();
    return OpenSSHEd25519KeyPair(
      Uint8List.fromList(signing.publicKey),
      Uint8List.fromList(signing),
      comment,
    );
  }
```

   If `Uint8List.fromList(signing)` does not yield 64 bytes (pinenacl API
   drift), use `signing.asTypedList` / concatenate seed+publicKey — the
   Step-1 test (`privateKey.length, 64` + PEM sign round-trip) is the
   acceptance check.

- [ ] **Step 4: Run tests**

Run: `cd packages/dartssh2 && dart test test/openssh_encode_test.dart`
Expected: PASS. Then `dart analyze lib/src/ssh_key_pair.dart` → no errors.

- [ ] **Step 5: Interop check (manual, macOS)**

```bash
cd packages/dartssh2 && dart run - <<'EOF'
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
void main() {
  final kp = OpenSSHEd25519KeyPair.generate('interop');
  File('/tmp/ys_test_key').writeAsStringSync(kp.toPem(passphrase: 'pp'));
}
EOF
ssh-keygen -y -P pp -f /tmp/ys_test_key && rm /tmp/ys_test_key
```
Expected: ssh-keygen prints the `ssh-ed25519 …` public line (real-world
OpenSSH accepts our encrypted PEM). If `dart run -` is unsupported, write
the snippet to a temp file. Treat failure as a blocker.

- [ ] **Step 6: Commit**

```bash
git add packages/dartssh2/lib/src/ssh_key_pair.dart packages/dartssh2/test/openssh_encode_test.dart
git commit -m "feat(dartssh2): Ed25519 generation + encrypted OpenSSH PEM encoding"
```

---

### Task 2: KeyGenService

**Files:**
- Create: `app/lib/services/key_gen_service.dart`
- Test: `app/test/services/key_gen_service_test.dart` (new)

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/key_gen_service.dart';

void main() {
  late Directory tmp;
  final svc = KeyGenService();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('keygen_test');
  });

  tearDown(() => tmp.delete(recursive: true));

  group('sanitizeKeyName', () {
    test('keeps safe chars, replaces the rest', () {
      expect(KeyGenService.sanitizeKeyName('id_ed25519'), 'id_ed25519');
      expect(KeyGenService.sanitizeKeyName('my key/2!'), 'my_key_2_');
    });
  });

  group('buildDeployCommand', () {
    test('quotes the key and is idempotent via grep -qxF', () {
      final cmd = KeyGenService.buildDeployCommand('ssh-ed25519 AAAA test');
      expect(cmd, contains("grep -qxF 'ssh-ed25519 AAAA test'"));
      expect(cmd, contains('echo EXISTS'));
      expect(cmd, contains('echo ADDED'));
      expect(cmd, contains('chmod 700'));
      expect(cmd, contains('chmod 600'));
    });

    test('single quotes in the line are escaped', () {
      final cmd = KeyGenService.buildDeployCommand("key with ' quote");
      expect(cmd, contains(r"'key with '\'' quote'"));
    });
  });

  group('generateEd25519', () {
    test('writes a parseable key + .pub line, registers paths', () async {
      final r = await svc.generateEd25519(
          name: 'test key', passphrase: '', dir: tmp.path);
      expect(r.privateKeyPath, '${tmp.path}/test_key');
      final pem = File(r.privateKeyPath).readAsStringSync();
      expect(SSHKeyPair.fromPem(pem).single.name, 'ssh-ed25519');
      final pubLine = File('${r.privateKeyPath}.pub').readAsStringSync();
      expect(pubLine, startsWith('ssh-ed25519 '));
      expect(pubLine.trim(), endsWith(' test key'));
      expect(r.publicKeyLine, pubLine.trim());
      if (!Platform.isWindows) {
        final mode = File(r.privateKeyPath).statSync().mode & 0xFFF;
        expect(mode, 0x180, reason: 'private key must be 0600');
      }
    });

    test('passphrase produces an encrypted PEM that decrypts', () async {
      final r = await svc.generateEd25519(
          name: 'enc', passphrase: 's3cret', dir: tmp.path);
      final pem = File(r.privateKeyPath).readAsStringSync();
      expect(SSHKeyPair.isEncryptedPem(pem), isTrue);
      expect(SSHKeyPair.fromPem(pem, 's3cret'), hasLength(1));
    });
  });

  group('sshKeygenArgs', () {
    test('rsa gets -b 4096, ecdsa gets -b 256, ed25519 gets no -b', () {
      expect(
          KeyGenService.sshKeygenArgs(
              type: 'rsa', keyPath: '/k', comment: 'c', passphrase: ''),
          containsAllInOrder(['-t', 'rsa', '-b', '4096']));
      expect(
          KeyGenService.sshKeygenArgs(
              type: 'ecdsa', keyPath: '/k', comment: 'c', passphrase: ''),
          containsAllInOrder(['-t', 'ecdsa', '-b', '256']));
      expect(
          KeyGenService.sshKeygenArgs(
              type: 'ed25519', keyPath: '/k', comment: 'c', passphrase: ''),
          isNot(contains('-b')));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/key_gen_service_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement**

Create `app/lib/services/key_gen_service.dart`:

```dart
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
  /// the EXISTS/ADDED marker tells the dialog which happened.
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
    final pem = keyPair.toPem(
        passphrase: passphrase.isEmpty ? null : passphrase);
    final publicKeyLine =
        '${keyPair.name} ${base64.encode(keyPair.toPublicKey().encode())} '
        '$name';

    final keyPath = p.join(dir, sanitizeKeyName(name));
    await File(keyPath).writeAsString(pem);
    await File('$keyPath.pub').writeAsString('$publicKeyLine\n');
    if (!Platform.isWindows) await chmodLocal(keyPath, 0x180 /* 0600 */);
    return GeneratedKey(
        privateKeyPath: keyPath, publicKeyLine: publicKeyLine);
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
    final publicKeyLine =
        (await File('$keyPath.pub').readAsString()).trim();
    return GeneratedKey(
        privateKeyPath: keyPath, publicKeyLine: publicKeyLine);
  }
}
```

(Check `chmodLocal`'s exact signature in `app/lib/util/file_mode.dart` —
it takes `(String path, int mode, ...)`; pass octal 0600 = 384 decimal.
If the mode constant style differs, follow the file.)

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/services/key_gen_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/key_gen_service.dart app/test/services/key_gen_service_test.dart
git commit -m "feat: KeyGenService — pure-Dart Ed25519 + fixed ssh-keygen args"
```

---

### Task 3: KeyProvider returns the entry + passphrase callback

**Files:**
- Modify: `app/lib/providers/key_provider.dart` (`addKeyFromFile`, line ~70)
- Modify: `app/lib/main.dart` (~line 184)
- Test: extend `app/test/providers/key_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `app/test/providers/key_provider_test.dart` (mirror its setup):

```dart
  test('addKeyFromFile returns the created entry', () async {
    final dir = await Directory.systemTemp.createTemp('kp_test');
    addTearDown(() => dir.delete(recursive: true));
    final keyFile = File('${dir.path}/id_ed25519')
      ..writeAsStringSync('PRIVATE');
    File('${dir.path}/id_ed25519.pub').writeAsStringSync('ssh-ed25519 AAA c');

    final provider = KeyProvider();
    final entry = await provider.addKeyFromFile(keyFile.path, 'my key');
    expect(entry.label, 'my key');
    expect(entry.publicKey, 'ssh-ed25519 AAA c');
    expect(provider.findById(entry.id), isNotNull);
  });
```

(Use the file's existing imports/`SharedPreferences.setMockInitialValues`
setup.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/providers/key_provider_test.dart`
Expected: FAIL — `addKeyFromFile` returns `void`, not an entry.

- [ ] **Step 3: Implement**

In `key_provider.dart`:

```dart
  /// Persists key passphrases (wired to StorageService.savePassphrase in
  /// main.dart — StorageService is not in the provider tree).
  Future<void> Function(String keyId, String passphrase)? savePassphrase;

  Future<SshKeyEntry> addKeyFromFile(String path, String label) async {
    // ... existing body unchanged ...
    await _save();
    notifyListeners();
    return entry;
  }
```

In `main.dart` after `_keyProvider = KeyProvider();`:

```dart
    _keyProvider.savePassphrase = _storage.savePassphrase;
```

- [ ] **Step 4: Run tests + commit**

Run: `cd app && flutter test test/providers/key_provider_test.dart && flutter analyze`
Expected: PASS, 0 issues.

```bash
git add app/lib/providers/key_provider.dart app/lib/main.dart app/test/providers/key_provider_test.dart
git commit -m "feat: addKeyFromFile returns entry; passphrase persistence hook"
```

---

### Task 4: Deploy dialog

**Files:**
- Create: `app/lib/widgets/deploy_key_dialog.dart`

- [ ] **Step 1: Implement**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/host.dart';
import '../models/ssh_key.dart';
import '../providers/host_provider.dart';
import '../services/key_gen_service.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';

/// ssh-copy-id-style deploy: pick a saved host, append [entry]'s public
/// key to its ~/.ssh/authorized_keys (idempotent). Failures keep the
/// dialog open for retry.
class DeployKeyDialog extends StatefulWidget {
  final SshKeyEntry entry;
  const DeployKeyDialog({super.key, required this.entry});

  @override
  State<DeployKeyDialog> createState() => _DeployKeyDialogState();
}

class _DeployKeyDialogState extends State<DeployKeyDialog> {
  String _search = '';
  String? _busyHostId;
  String? _error;

  Future<void> _deploy(Host host) async {
    setState(() {
      _busyHostId = host.id;
      _error = null;
    });
    try {
      final cmd =
          KeyGenService.buildDeployCommand(widget.entry.publicKey);
      final r = await context.read<SshService>().exec(host, cmd);
      if (!mounted) return;
      if (r.exitCode == 0) {
        final added = r.stdout.contains('ADDED');
        Navigator.pop(context);
        AppSnack.success(
            context,
            added
                ? 'Public key added to ${host.label}'
                : 'Key already deployed on ${host.label}');
      } else {
        setState(() => _error =
            'Failed on ${host.label}: ${r.stderr.trim().isEmpty ? 'exit ${r.exitCode}' : r.stderr.trim()}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed on ${host.label}: $e');
    } finally {
      if (mounted) setState(() => _busyHostId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.toLowerCase();
    final hosts = context
        .watch<HostProvider>()
        .allHosts
        .where((h) =>
            q.isEmpty ||
            h.label.toLowerCase().contains(q) ||
            h.host.toLowerCase().contains(q))
        .toList();

    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text('Deploy "${widget.entry.label}" to host',
          style:
              const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
      content: SizedBox(
        width: 380,
        height: 360,
        child: Column(children: [
          TextField(
            autofocus: true,
            style:
                const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Search hosts…',
              hintStyle:
                  TextStyle(color: AppColors.textTertiary, fontSize: 13),
              prefixIcon: Icon(Icons.search, size: 16),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.red, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: hosts.isEmpty
                ? const Center(
                    child: Text('No hosts',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 13)))
                : ListView.builder(
                    itemCount: hosts.length,
                    itemBuilder: (_, i) {
                      final h = hosts[i];
                      final busy = _busyHostId == h.id;
                      return ListTile(
                        dense: true,
                        enabled: _busyHostId == null,
                        leading: const Icon(Icons.dns_outlined,
                            size: 16, color: AppColors.textSecondary),
                        title: Text(h.label,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13)),
                        subtitle: Text('${h.username}@${h.host}',
                            style: const TextStyle(
                                color: AppColors.textTertiary, fontSize: 11)),
                        trailing: busy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5))
                            : null,
                        onTap: () => _deploy(h),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }
}
```

- [ ] **Step 2: Analyze + commit**

Run: `cd app && flutter analyze`
Expected: 0 issues.

```bash
git add app/lib/widgets/deploy_key_dialog.dart
git commit -m "feat: deploy-public-key-to-host dialog"
```

---

### Task 5: Keychain screen rework

**Files:**
- Modify: `app/lib/widgets/keychain_screen.dart`
- Test: `app/test/widgets/keychain_generate_test.dart` (new)

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/services/key_gen_service.dart';
import 'package:yourssh/widgets/keychain_screen.dart';

class _FakeKeyGen extends KeyGenService {
  _FakeKeyGen({required this.sshKeygenAvailable});
  final bool sshKeygenAvailable;

  @override
  Future<bool> probeSshKeygen() async => sshKeygenAvailable;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, KeyGenService keyGen) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => KeyProvider())],
      child: MaterialApp(
          home: Scaffold(body: KeychainScreen(keyGen: keyGen))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('rsa/ecdsa options disabled when ssh-keygen is missing',
      (tester) async {
    await pump(tester, _FakeKeyGen(sshKeygenAvailable: false));
    await tester.tap(find.text('GENERATE'));
    await tester.pumpAndSettle();

    expect(find.textContaining('requires OpenSSH client'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    // Disabled items render greyed; asserting they exist but tapping one
    // doesn't change the selection:
    await tester.tap(find.text('RSA 4096').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Ed25519 (recommended)'), findsOneWidget);
  });

  testWidgets('rsa/ecdsa enabled when ssh-keygen exists', (tester) async {
    await pump(tester, _FakeKeyGen(sshKeygenAvailable: true));
    await tester.tap(find.text('GENERATE'));
    await tester.pumpAndSettle();
    expect(find.textContaining('requires OpenSSH client'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/keychain_generate_test.dart`
Expected: FAIL — `KeychainScreen` has no `keyGen` parameter.

- [ ] **Step 3: Implement the panel rework**

In `keychain_screen.dart`:

1. `KeychainScreen` gains `final KeyGenService? keyGen;` constructor param
   (default null → `KeyGenService()` instantiated once in state); threaded
   into `_GenerateKeyPanel(keyGen: …)`.
2. `_GenerateKeyPanelState`:
   - `bool? _sshKeygenAvailable; String? _generatedPublicKey;` — probe in
     `initState` via `widget.keyGen.probeSshKeygen().then(...)`.
   - Dropdown items use `enabled:` (ed25519 always; rsa/ecdsa
     `enabled: _sshKeygenAvailable ?? true`), labels
     `Ed25519 (recommended)` / `RSA 4096` / `ECDSA P-256`; when
     `_sshKeygenAvailable == false` show helper text
     `RSA/ECDSA require OpenSSH client (ssh-keygen)` under the dropdown.
   - `_submit` branches:

```dart
      final dir = p.join(
          (await getApplicationDocumentsDirectory()).path, 'YourSSH', 'keys');
      await Directory(dir).create(recursive: true);
      final GeneratedKey result = _type == 'ed25519'
          ? await widget.keyGen.generateEd25519(
              name: _label.text.trim(),
              passphrase: _passphrase.text,
              dir: dir)
          : await widget.keyGen.generateWithSshKeygen(
              type: _type,
              name: _label.text.trim(),
              passphrase: _passphrase.text,
              dir: dir);
      final provider = context.read<KeyProvider>();
      final entry = await provider.addKeyFromFile(
          result.privateKeyPath, _label.text.trim());
      if (_passphrase.text.isNotEmpty) {
        await provider.savePassphrase
                ?.call(entry.id, _passphrase.text) ??
            Future<void>.value();
      }
      setState(() => _generatedPublicKey = result.publicKeyLine);
```

   - When `_generatedPublicKey != null`, the build shows the success state
     instead of the form: a `SelectableText` (monospace, 12px, inside an
     `AppColors.card` container) with the public key, a full-width
     **Copy public key** `FilledButton` (Clipboard.setData +
     `AppSnack.success(context, 'Public key copied')`), and a **Done**
     `TextButton` calling `widget.onClose()`.
   - All raw `ScaffoldMessenger…SnackBar` calls → `AppSnack.success` /
     `AppSnack.error`.
3. `_KeyTile` hover actions (next to delete, same 28×28 button style):
   - **copy** (`Icons.copy_outlined`, shown when `e.publicKey.isNotEmpty`):
     `Clipboard.setData(ClipboardData(text: e.publicKey))` +
     `AppSnack.success(context, 'Public key copied')`.
   - **deploy** (`Icons.cloud_upload_outlined`, same visibility):
     `showDialog(context: context, builder: (_) => DeployKeyDialog(entry: e))`.
   Imports: `package:flutter/services.dart` (Clipboard),
   `deploy_key_dialog.dart`, `../services/key_gen_service.dart`.

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/widgets/keychain_generate_test.dart && flutter analyze`
Expected: PASS, 0 issues.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/keychain_screen.dart app/test/widgets/keychain_generate_test.dart
git commit -m "feat: keychain generate panel rework — probe gating, success state, copy/deploy"
```

---

### Task 6: Full verification + docs

- [ ] **Step 1: Full run**

Run: `cd app && flutter analyze && flutter test`
and `cd packages/dartssh2 && dart test test/openssh_encode_test.dart`
Expected: all pass, 0 analyzer issues.

- [ ] **Step 2: Update CLAUDE.md**

- **Services** add:
  `- KeyGenService — SSH key generation: Ed25519 pure-Dart (fork's OpenSSHEd25519KeyPair.generate + toPem(passphrase:) — bcrypt-pbkdf/aes256-ctr encrypted OpenSSH PEM), RSA-4096/ECDSA-P256 via ssh-keygen (probeSshKeygen gates the panel options); buildDeployCommand (ssh-copy-id-style, grep -qxF idempotent, EXISTS/ADDED marker) used by DeployKeyDialog over SshService.exec; generated keys land in Documents/YourSSH/keys with mode 600 and the passphrase saved as pp_<keyId> via KeyProvider.savePassphrase`
- **dartssh2 fork bullet** (monorepo layout): append `; adds OpenSSHEd25519KeyPair.generate() and passphrase-encrypting toPem (bcrypt-pbkdf + aes256-ctr, unencrypted output unchanged)`
- **KeyProvider bullet**: note `addKeyFromFile returns the entry; savePassphrase callback wired to StorageService in main.dart`.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: SSH key generation in CLAUDE.md"
```

---

## Self-review notes (already applied)

- **Spec coverage:** fork encrypted encoder + generate (T1, incl. real
  ssh-keygen interop check), pure-Dart Ed25519 + `-b` fixes + probe +
  deploy builder (T2), passphrase persistence (T3 + T5 submit), copy
  public key tile/panel + AppSnack + success state (T5), deploy dialog
  with EXISTS/ADDED wording and stay-open-on-error (T4), mode 600 (T2),
  docs (T6).
- **Type consistency:** `GeneratedKey{privateKeyPath, publicKeyLine}`
  (T2) used in T5; `KeyGenService.buildDeployCommand` static (T2) used in
  T4; `addKeyFromFile → SshKeyEntry` (T3) used in T5;
  `probeSshKeygen` overridable instance method (T2) faked in T5's test.
- **Known risks:** pinenacl `SigningKey` byte-shape (T1 Step 3 note — the
  round-trip test is the acceptance check); `chmodLocal` signature
  (T2 note); legacy `toPem()` implementors must all gain the named param
  (T1 Step 3.3 says grep for every implementor).
