# SSH Certificate Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OpenSSH certificate auth (CA-signed `-cert.pub` keys) and wire up the existing `AuthType.agent` to the real system ssh-agent.

**Architecture:** Certificate auth uses a `CertificateKeyPair` that wraps a normal private key pair and substitutes the cert blob as the presented identity — no dartssh2 changes needed. Agent auth requires a minimal local fork of dartssh2 to add `Future<SSHSignature> signAsync()` to `SSHKeyPair`, enabling the async socket communication the agent protocol requires. The fork is pinned via `dependency_overrides` in `pubspec.yaml`.

**Tech Stack:** Flutter/Dart, dartssh2 (local fork at `packages/dartssh2/`), `dart:io` Unix domain sockets, `dart:convert` base64, `dart:typed_data`.

---

## File Map

**New files:**
- `app/lib/services/certificate_key_pair.dart` — `CertificateKeyPair` + `_RawBlobHostKey`
- `app/lib/services/system_agent_proxy.dart` — `SystemAgentProxy`, `_AgentKeyPair`, `_RawSignature`, `SSHAgentUnavailableException`, wire protocol helpers
- `app/test/services/certificate_key_pair_test.dart`
- `app/test/services/system_agent_proxy_test.dart`
- `packages/dartssh2/` — minimal local fork of dartssh2 2.17.1

**Modified files:**
- `app/lib/models/host.dart` — add `AuthType.certificate`
- `app/lib/models/ssh_key.dart` — add `certificatePath`, `hasCertificate`
- `app/lib/providers/key_provider.dart` — cert auto-discovery, `setCertificate`, `removeCertificate`
- `app/lib/services/ssh_service.dart` — handle `AuthType.certificate` and `AuthType.agent`
- `app/lib/widgets/keychain_screen.dart` — cert link/unlink UI in `_KeyTile`
- `app/lib/widgets/add_host_dialog.dart` — add `certificate` to auth type dropdown
- `app/pubspec.yaml` — `dependency_overrides` pointing to local dartssh2

---

## Task 1: Add `AuthType.certificate` to host model

**Files:**
- Modify: `app/lib/models/host.dart`
- Modify: `app/lib/widgets/add_host_dialog.dart` (add placeholder to avoid compile error)
- Test: `app/test/models/host_test.dart` (create)

- [ ] **Step 1: Create a failing test**

```dart
// app/test/models/host_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

void main() {
  group('Host', () {
    test('certificate AuthType round-trips through JSON', () {
      final h = Host(
        label: 'Test', host: '1.2.3.4', username: 'user',
        authType: AuthType.certificate, keyId: 'key-1',
      );
      final decoded = Host.fromJson(h.toJson());
      expect(decoded.authType, AuthType.certificate);
    });

    test('unknown authType defaults to password', () {
      final json = {
        'id': 'x', 'label': 'x', 'host': 'x', 'port': 22,
        'username': 'x', 'authType': 'nonexistent',
        'group': '', 'tags': [], 'createdAt': DateTime.now().toIso8601String(),
      };
      // byName would throw; fromJson must not crash on future-unknown values
      expect(() => Host.fromJson(json), throwsArgumentError);
    });
  });
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
cd app && flutter test test/models/host_test.dart -v
```
Expected: FAIL — `AuthType.certificate` does not exist yet.

- [ ] **Step 3: Add `certificate` to the enum and fix fromJson**

In `app/lib/models/host.dart`, change:
```dart
// BEFORE:
enum AuthType { password, privateKey, agent }

// AFTER:
enum AuthType { password, privateKey, certificate, agent }
```

`Host.fromJson` already uses `AuthType.values.byName(...)` which handles the new value automatically.

- [ ] **Step 4: Fix compile error in add_host_dialog.dart**

In `app/lib/widgets/add_host_dialog.dart`, in the `onChanged` of the auth type dropdown, no change needed — the switch on `AuthType` does not need to be exhaustive (it uses `if` chains).

Run `flutter analyze app` to check for errors:
```bash
cd app && flutter analyze
```
Expected: no errors.

- [ ] **Step 5: Run test — confirm it passes**

```bash
cd app && flutter test test/models/host_test.dart -v
```
Expected: PASS.

- [ ] **Step 6: Run full test suite to check for regressions**

```bash
cd app && flutter test
```
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add app/lib/models/host.dart app/test/models/host_test.dart
git commit -m "feat: add AuthType.certificate to host model"
```

---

## Task 2: Extend `SshKeyEntry` with `certificatePath`

**Files:**
- Modify: `app/lib/models/ssh_key.dart`
- Test: `app/test/models/ssh_key_test.dart` (create)

- [ ] **Step 1: Write failing test**

```dart
// app/test/models/ssh_key_test.dart
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
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
cd app && flutter test test/models/ssh_key_test.dart -v
```
Expected: FAIL — `SshKeyEntry` has no `certificatePath` parameter.

- [ ] **Step 3: Add `certificatePath` to `SshKeyEntry`**

Replace the contents of `app/lib/models/ssh_key.dart`:

```dart
import 'dart:io';
import 'package:uuid/uuid.dart';

enum KeyAlgorithm { ed25519, rsa, ecdsa }

class SshKeyEntry {
  final String id;
  String label;
  KeyAlgorithm algorithm;
  String publicKey;
  String privateKeyPath;
  String? certificatePath;
  DateTime addedAt;

  SshKeyEntry({
    String? id,
    required this.label,
    required this.algorithm,
    required this.publicKey,
    required this.privateKeyPath,
    this.certificatePath,
    DateTime? addedAt,
  })  : id = id ?? const Uuid().v4(),
        addedAt = addedAt ?? DateTime.now();

  bool get hasCertificate =>
      certificatePath != null && File(certificatePath!).existsSync();

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'algorithm': algorithm.name,
        'publicKey': publicKey,
        'privateKeyPath': privateKeyPath,
        'certificatePath': certificatePath,
        'addedAt': addedAt.toIso8601String(),
      };

  factory SshKeyEntry.fromJson(Map<String, dynamic> json) => SshKeyEntry(
        id: json['id'],
        label: json['label'],
        algorithm: KeyAlgorithm.values.byName(json['algorithm'] ?? 'rsa'),
        publicKey: json['publicKey'] ?? '',
        privateKeyPath: json['privateKeyPath'] ?? '',
        certificatePath: json['certificatePath'] as String?,
        addedAt: DateTime.parse(json['addedAt']),
      );

  String get algorithmLabel => switch (algorithm) {
        KeyAlgorithm.ed25519 => 'Ed25519',
        KeyAlgorithm.rsa => 'RSA',
        KeyAlgorithm.ecdsa => 'ECDSA',
      };

  String get fingerprint {
    if (publicKey.isEmpty) return '';
    final parts = publicKey.split(' ');
    return parts.length > 1 ? '${parts[0]}...${parts[1].substring(0, 16)}' : '';
  }
}
```

- [ ] **Step 4: Run test — confirm it passes**

```bash
cd app && flutter test test/models/ssh_key_test.dart -v
```
Expected: PASS.

- [ ] **Step 5: Run full suite**

```bash
cd app && flutter test
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/models/ssh_key.dart app/test/models/ssh_key_test.dart
git commit -m "feat: add certificatePath and hasCertificate to SshKeyEntry"
```

---

## Task 3: Implement `CertificateKeyPair`

**Files:**
- Create: `app/lib/services/certificate_key_pair.dart`
- Create: `app/test/services/certificate_key_pair_test.dart`

Note: `SSHHostKey` and `SSHSignature` are not publicly exported by dartssh2. Until Task 8 adds the local fork, import them from the internal path: `package:dartssh2/src/ssh_hostkey.dart`. This import will remain valid after the fork.

- [ ] **Step 1: Write failing tests**

```dart
// app/test/services/certificate_key_pair_test.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/ssh_hostkey.dart';
import 'package:yourssh/services/certificate_key_pair.dart';

// Minimal fake key pair for tests — signs data by returning it as the signature.
class _FakeKeyPair implements SSHKeyPair {
  Uint8List? lastSigned;

  @override
  String get name => 'ssh-ed25519';

  @override
  String get type => 'ssh-ed25519';

  @override
  SSHHostKey toPublicKey() => throw UnimplementedError();

  @override
  SSHSignature sign(Uint8List data) {
    lastSigned = data;
    return _FakeSignature(data);
  }

  @override
  Future<SSHSignature> signAsync(Uint8List data) async => sign(data);

  @override
  String toPem() => throw UnimplementedError();
}

class _FakeSignature implements SSHSignature {
  final Uint8List _bytes;
  _FakeSignature(this._bytes);
  @override
  Uint8List encode() => _bytes;
}

/// Builds a minimal cert blob with only the algorithm name field populated.
Uint8List _makeCertBlob(String algorithm) {
  final algBytes = utf8.encode(algorithm);
  final blob = Uint8List(4 + algBytes.length + 4); // algo + dummy uint32 tail
  ByteData.view(blob.buffer).setUint32(0, algBytes.length, Endian.big);
  blob.setRange(4, 4 + algBytes.length, algBytes);
  return blob;
}

void main() {
  group('CertificateKeyPair', () {
    test('type reads algorithm name from cert blob', () {
      final blob = _makeCertBlob('ssh-ed25519-cert-v01@openssh.com');
      final pair = CertificateKeyPair(_FakeKeyPair(), blob);
      expect(pair.type, 'ssh-ed25519-cert-v01@openssh.com');
    });

    test('type works for rsa cert algorithm', () {
      final blob = _makeCertBlob('ssh-rsa-cert-v01@openssh.com');
      final pair = CertificateKeyPair(_FakeKeyPair(), blob);
      expect(pair.type, 'ssh-rsa-cert-v01@openssh.com');
    });

    test('toPublicKey encode returns cert blob verbatim', () {
      final blob = _makeCertBlob('ssh-ed25519-cert-v01@openssh.com');
      final pair = CertificateKeyPair(_FakeKeyPair(), blob);
      expect(pair.toPublicKey().encode(), equals(blob));
    });

    test('sign delegates to inner key pair', () {
      final blob = _makeCertBlob('ssh-ed25519-cert-v01@openssh.com');
      final inner = _FakeKeyPair();
      final pair = CertificateKeyPair(inner, blob);
      final challenge = Uint8List.fromList([1, 2, 3]);
      pair.sign(challenge);
      expect(inner.lastSigned, equals(challenge));
    });

    test('toPem throws UnsupportedError', () {
      final blob = _makeCertBlob('ssh-ed25519-cert-v01@openssh.com');
      final pair = CertificateKeyPair(_FakeKeyPair(), blob);
      expect(() => pair.toPem(), throwsUnsupportedError);
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd app && flutter test test/services/certificate_key_pair_test.dart -v
```
Expected: FAIL — `CertificateKeyPair` does not exist.

- [ ] **Step 3: Implement `CertificateKeyPair`**

Create `app/lib/services/certificate_key_pair.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/ssh_hostkey.dart';

class CertificateKeyPair implements SSHKeyPair {
  final SSHKeyPair _inner;
  final Uint8List _certBytes;

  CertificateKeyPair(this._inner, this._certBytes);

  /// Loads a key+cert pair from disk.
  ///
  /// [certPath] must point to a file in OpenSSH public cert format:
  ///   `ssh-ed25519-cert-v01@openssh.com AAAA... comment`
  static Future<CertificateKeyPair> load({
    required String keyPath,
    required String certPath,
    String? passphrase,
  }) async {
    final pem = await File(keyPath).readAsString();
    final inner = SSHKeyPair.fromPem(pem, passphrase ?? '').first;

    final certLine = await File(certPath).readAsString();
    final parts = certLine.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) {
      throw FormatException('Invalid cert file (expected "algo base64 [comment]"): $certPath');
    }
    final certBytes = base64.decode(parts[1]);
    return CertificateKeyPair(inner, certBytes);
  }

  @override
  String get name => type;

  /// Returns the OpenSSH certificate algorithm name encoded in the cert blob,
  /// e.g. `ssh-ed25519-cert-v01@openssh.com`.
  @override
  String get type {
    if (_certBytes.length < 4) throw FormatException('Cert blob too short');
    final nameLen = ByteData.view(
      _certBytes.buffer, _certBytes.offsetInBytes, 4,
    ).getUint32(0, Endian.big);
    if (_certBytes.length < 4 + nameLen) {
      throw FormatException('Cert blob truncated: expected $nameLen bytes for algorithm name');
    }
    return utf8.decode(_certBytes.sublist(4, 4 + nameLen));
  }

  @override
  SSHHostKey toPublicKey() => _RawBlobHostKey(_certBytes);

  @override
  SSHSignature sign(Uint8List data) => _inner.sign(data);

  @override
  Future<SSHSignature> signAsync(Uint8List data) async => _inner.sign(data);

  @override
  String toPem() => throw UnsupportedError('CertificateKeyPair cannot be serialized to PEM');
}

class _RawBlobHostKey implements SSHHostKey {
  final Uint8List _bytes;
  const _RawBlobHostKey(this._bytes);

  @override
  Uint8List encode() => _bytes;
}
```

Note: `signAsync` is defined here for forward-compatibility with Task 8's dartssh2 fork. Until the fork is applied, dartssh2's `SSHKeyPair` won't declare it, so the `@override` annotation may generate a warning — that's expected and will be resolved in Task 8.

- [ ] **Step 4: Run tests — confirm they pass**

```bash
cd app && flutter test test/services/certificate_key_pair_test.dart -v
```
Expected: all 5 tests PASS.

- [ ] **Step 5: Run full suite**

```bash
cd app && flutter test
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/services/certificate_key_pair.dart app/test/services/certificate_key_pair_test.dart
git commit -m "feat: add CertificateKeyPair for OpenSSH CA-signed cert auth"
```

---

## Task 4: Update `KeyProvider` — cert auto-discovery and management methods

**Files:**
- Modify: `app/lib/providers/key_provider.dart`
- Test: `app/test/providers/key_provider_test.dart` (create)

- [ ] **Step 1: Write failing tests**

```dart
// app/test/providers/key_provider_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/models/ssh_key.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('KeyProvider certificate methods', () {
    test('setCertificate persists certificatePath on the key entry', () async {
      final provider = KeyProvider();
      // Wait for initial load to complete.
      await Future.delayed(Duration.zero);

      // Manually inject a key entry.
      await provider.addKeyFromFile(_tmpKeyFile(), 'test-key');
      await Future.delayed(Duration.zero);

      final key = provider.keys.first;
      await provider.setCertificate(key.id, '/tmp/id_ed25519-cert.pub');

      expect(provider.keys.first.certificatePath, '/tmp/id_ed25519-cert.pub');
    });

    test('removeCertificate clears certificatePath', () async {
      final provider = KeyProvider();
      await Future.delayed(Duration.zero);

      await provider.addKeyFromFile(_tmpKeyFile(), 'test-key');
      await Future.delayed(Duration.zero);

      final key = provider.keys.first;
      await provider.setCertificate(key.id, '/tmp/id_ed25519-cert.pub');
      await provider.removeCertificate(key.id);

      expect(provider.keys.first.certificatePath, isNull);
    });
  });
}

// Creates a temp file that looks like a private key path (content doesn't matter for these tests).
String _tmpKeyFile() {
  final f = File('/tmp/test_key_${DateTime.now().millisecondsSinceEpoch}');
  f.writeAsStringSync('placeholder');
  return f.path;
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd app && flutter test test/providers/key_provider_test.dart -v
```
Expected: FAIL — `setCertificate` and `removeCertificate` do not exist.

- [ ] **Step 3: Add the methods and cert auto-discovery to `KeyProvider`**

In `app/lib/providers/key_provider.dart`, make these changes:

**a) In `_discoverSshKeys`, after adding each key, check for a cert file:**

```dart
// After: _keys.add(SshKeyEntry(...));
// Add:
final certFile = File(p.join(sshDir.path, '$name-cert.pub'));
if (certFile.existsSync()) {
  _keys.last.certificatePath = certFile.path;
}
```

**b) In `addKeyFromFile`, after creating the entry, check for a cert file:**

```dart
// After: _keys.add(entry);
// Add:
final certFile = File('$path-cert.pub');
if (certFile.existsSync()) {
  _keys.last.certificatePath = certFile.path;
}
```

**c) Add the two new methods before `_save()`:**

```dart
Future<void> setCertificate(String keyId, String certPath) async {
  final idx = _keys.indexWhere((k) => k.id == keyId);
  if (idx == -1) return;
  _keys[idx].certificatePath = certPath;
  await _save();
  notifyListeners();
}

Future<void> removeCertificate(String keyId) async {
  final idx = _keys.indexWhere((k) => k.id == keyId);
  if (idx == -1) return;
  _keys[idx].certificatePath = null;
  await _save();
  notifyListeners();
}
```

**Note:** `SshKeyEntry.certificatePath` must be mutable (`var` not `final`). Check `ssh_key.dart` — it already uses `String? certificatePath` as a regular field (not final), so this is fine.

- [ ] **Step 4: Run tests — confirm they pass**

```bash
cd app && flutter test test/providers/key_provider_test.dart -v
```
Expected: PASS.

- [ ] **Step 5: Run full suite**

```bash
cd app && flutter test
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/providers/key_provider.dart app/test/providers/key_provider_test.dart
git commit -m "feat: auto-discover cert files and add setCertificate/removeCertificate to KeyProvider"
```

---

## Task 5: Wire `CertificateKeyPair` into `SshService`

**Files:**
- Modify: `app/lib/services/ssh_service.dart`

No new test file needed — the connect/testConnection methods interact with a live SSH server; this is covered by integration tests and manual testing.

- [ ] **Step 1: Update `connect()` in `ssh_service.dart`**

Replace the existing `List<SSHKeyPair> identities = [];` block (lines 27–35) with:

```dart
List<SSHKeyPair> identities = [];
if (host.authType == AuthType.privateKey && keyEntry != null) {
  final keyFile = File(keyEntry.privateKeyPath);
  if (await keyFile.exists()) {
    final pem = await keyFile.readAsString();
    final passphrase = await _storage.loadPassphrase(keyEntry.id);
    identities = SSHKeyPair.fromPem(pem, passphrase ?? '');
  }
} else if (host.authType == AuthType.certificate && keyEntry != null) {
  final certPath = keyEntry.certificatePath;
  if (certPath == null) {
    throw Exception('No certificate linked to key "${keyEntry.label}". Add one in Keychain.');
  }
  if (!await File(certPath).exists()) {
    throw Exception('Certificate file not found: $certPath');
  }
  final passphrase = await _storage.loadPassphrase(keyEntry.id);
  identities = [
    await CertificateKeyPair.load(
      keyPath: keyEntry.privateKeyPath,
      certPath: certPath,
      passphrase: passphrase,
    ),
  ];
}
```

Add the import at the top of `ssh_service.dart`:
```dart
import 'certificate_key_pair.dart';
```

- [ ] **Step 2: Apply the same change to `testConnection()`**

Replace the `List<SSHKeyPair> identities = [];` block in `testConnection()` (lines 66–74) with the same logic as above (substituting `password` parameter for `_storage.loadPassword`):

```dart
List<SSHKeyPair> identities = [];
if (host.authType == AuthType.privateKey && keyEntry != null) {
  final keyFile = File(keyEntry.privateKeyPath);
  if (await keyFile.exists()) {
    final pem = await keyFile.readAsString();
    final passphrase = await _storage.loadPassphrase(keyEntry.id);
    identities = SSHKeyPair.fromPem(pem, passphrase ?? '');
  }
} else if (host.authType == AuthType.certificate && keyEntry != null) {
  final certPath = keyEntry.certificatePath;
  if (certPath == null || !await File(certPath).exists()) {
    return (success: false, latencyMs: 0, error: 'Certificate file missing or not linked');
  }
  final passphrase = await _storage.loadPassphrase(keyEntry.id);
  identities = [
    await CertificateKeyPair.load(
      keyPath: keyEntry.privateKeyPath,
      certPath: certPath,
      passphrase: passphrase,
    ),
  ];
}
```

- [ ] **Step 3: Verify it compiles**

```bash
cd app && flutter analyze
```
Expected: no errors.

- [ ] **Step 4: Run full test suite**

```bash
cd app && flutter test
```
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/ssh_service.dart
git commit -m "feat: wire CertificateKeyPair into SshService for AuthType.certificate"
```

---

## Task 6: Update `KeychainScreen` — cert link/unlink UI

**Files:**
- Modify: `app/lib/widgets/keychain_screen.dart`

- [ ] **Step 1: Add cert status row to `_KeyTileState.build()`**

In `app/lib/widgets/keychain_screen.dart`, in `_KeyTileState.build()`, find the `Column` inside the `Expanded` widget (the one containing the label row and key path text) and add a third child after the path text:

```dart
// Add after the existing path Text and missing-file Text:
const SizedBox(height: 4),
_CertRow(entry: e),
```

- [ ] **Step 2: Add the `_CertRow` widget**

Add this widget class at the bottom of `keychain_screen.dart` (before `_Badge`):

```dart
class _CertRow extends StatelessWidget {
  final SshKeyEntry entry;
  const _CertRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    if (entry.hasCertificate) {
      final filename = entry.certificatePath!.split('/').last.split('\\').last;
      return Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text('CERT',
                style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(filename,
                style: const TextStyle(
                    color: AppColors.textTertiary, fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ),
          GestureDetector(
            onTap: () => context.read<KeyProvider>().removeCertificate(entry.id),
            child: const Icon(Icons.link_off, size: 13, color: AppColors.textTertiary),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: () async {
        final result = await FilePicker.platform.pickFiles(
          dialogTitle: 'Select Certificate File (*-cert.pub)',
          allowMultiple: false,
        );
        if (result == null || result.files.isEmpty) return;
        if (context.mounted) {
          await context.read<KeyProvider>().setCertificate(
                entry.id,
                result.files.first.path!,
              );
        }
      },
      child: const Text('Link certificate…',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
    );
  }
}
```

- [ ] **Step 2: Run analyze to confirm no errors**

```bash
cd app && flutter analyze
```
Expected: no errors.

- [ ] **Step 3: Run full test suite**

```bash
cd app && flutter test
```
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/keychain_screen.dart
git commit -m "feat: show cert link/unlink UI in KeychainScreen key tiles"
```

---

## Task 7: Update `AddHostDialog` — add certificate auth type option

**Files:**
- Modify: `app/lib/widgets/add_host_dialog.dart`

- [ ] **Step 1: Add `certificate` to the auth type dropdown**

In `app/lib/widgets/add_host_dialog.dart`, in the `DropdownButtonFormField<AuthType>` items list, add a new item:

```dart
// Add after the privateKey item:
DropdownMenuItem(
  value: AuthType.certificate,
  child: const Text('Certificate (Key + CA cert)'),
),
```

- [ ] **Step 2: Add the key picker for `certificate` auth type**

After the existing `if (_authType == AuthType.privateKey) ...` block, add:

```dart
if (_authType == AuthType.certificate) ...[
  const SizedBox(height: 12),
  DropdownButtonFormField<String>(
    initialValue: _selectedKeyId,
    decoration: const InputDecoration(
      labelText: 'SSH Key (with linked certificate)',
      border: OutlineInputBorder(),
    ),
    hint: const Text('Select a key'),
    items: keys.map((k) => DropdownMenuItem(
      value: k.id,
      child: Row(
        children: [
          Text('${k.label} (${k.algorithmLabel})'),
          if (k.hasCertificate) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text('CERT',
                  style: TextStyle(
                      color: Colors.green,
                      fontSize: 9,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    )).toList(),
    onChanged: (v) => setState(() => _selectedKeyId = v),
    validator: (v) {
      if (v == null) return 'Select a key';
      final key = keys.firstWhere((k) => k.id == v, orElse: () => keys.first);
      if (!key.hasCertificate) {
        return 'Selected key has no linked certificate. Add one in Keychain.';
      }
      return null;
    },
  ),
],
```

- [ ] **Step 3: Fix `_submit` to pass `keyId` for certificate auth**

In `_submit()`, update the `Host` constructor so `keyId` is set for both `privateKey` and `certificate`:

```dart
// BEFORE:
keyId: _authType == AuthType.privateKey ? _selectedKeyId : null,

// AFTER:
keyId: (_authType == AuthType.privateKey || _authType == AuthType.certificate)
    ? _selectedKeyId
    : null,
```

- [ ] **Step 4: Run analyze**

```bash
cd app && flutter analyze
```
Expected: no errors.

- [ ] **Step 5: Run full test suite**

```bash
cd app && flutter test
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/add_host_dialog.dart
git commit -m "feat: add Certificate option to AddHostDialog auth type dropdown"
```

---

## Task 8: Set up dartssh2 local fork with async signing patch

This task patches dartssh2 so `SSHKeyPair.signAsync()` and `_authWithNextPublicKey()` support the async agent signing needed in Task 9. All existing key types get a default `signAsync()` that wraps the sync `sign()`.

**Files:**
- Create: `packages/dartssh2/` (copy from pub cache, patch 3 files)
- Modify: `app/pubspec.yaml`

- [ ] **Step 1: Copy dartssh2 source to local packages directory**

```bash
mkdir -p packages
cp -r ~/.pub-cache/hosted/pub.dev/dartssh2-2.17.1 packages/dartssh2
```

- [ ] **Step 2: Add `signAsync()` default method to `SSHKeyPair`**

In `packages/dartssh2/lib/src/ssh_key_pair.dart`, add this method to the `abstract class SSHKeyPair` (after the existing `sign` declaration):

```dart
// After: SSHSignature sign(Uint8List data);
// Add:
Future<SSHSignature> signAsync(Uint8List data) async => sign(data);
```

- [ ] **Step 3: Export `SSHHostKey` and `SSHSignature` from the fork**

In `packages/dartssh2/lib/dartssh2.dart`, add:

```dart
// Add this line alongside the other exports:
export 'src/ssh_hostkey.dart';
```

- [ ] **Step 4: Make `_authWithNextPublicKey` async in `ssh_client.dart`**

In `packages/dartssh2/lib/src/ssh_client.dart`:

**a) Change the method signature** (line ~1217):

```dart
// BEFORE:
void _authWithNextPublicKey() {
    printDebug?.call('SSHClient._authWithPublicKey');

    final keyPair = _keyPairsLeft.removeFirst();

    final challenge = _transport.composeChallenge(
      username: username,
      service: 'ssh-connection',
      publicKeyAlgorithm: keyPair.type,
      publicKey: keyPair.toPublicKey().encode(),
    );

    _sendMessage(
      SSH_Message_Userauth_Request.publicKey(
        username: username,
        publicKeyAlgorithm: keyPair.type,
        publicKey: keyPair.toPublicKey().encode(),
        signature: keyPair.sign(challenge).encode(),
      ),
    );
  }

// AFTER:
Future<void> _authWithNextPublicKey() async {
    printDebug?.call('SSHClient._authWithPublicKey');

    final keyPair = _keyPairsLeft.removeFirst();

    final challenge = _transport.composeChallenge(
      username: username,
      service: 'ssh-connection',
      publicKeyAlgorithm: keyPair.type,
      publicKey: keyPair.toPublicKey().encode(),
    );

    _sendMessage(
      SSH_Message_Userauth_Request.publicKey(
        username: username,
        publicKeyAlgorithm: keyPair.type,
        publicKey: keyPair.toPublicKey().encode(),
        signature: (await keyPair.signAsync(challenge)).encode(),
      ),
    );
  }
```

**b) Update two call sites in `_tryNextAuthMethod`** — both `return _authWithNextPublicKey();` become fire-and-forget because `_tryNextAuthMethod` is void:

```dart
// BEFORE (two occurrences):
return _authWithNextPublicKey();

// AFTER (both occurrences):
unawaited(_authWithNextPublicKey());
return;
```

Add `import 'dart:async' show unawaited;` at the top of `ssh_client.dart` if not already present.

- [ ] **Step 5: Point `pubspec.yaml` to the local fork**

In `app/pubspec.yaml`, add a `dependency_overrides` section at the end:

```yaml
dependency_overrides:
  dartssh2:
    path: ../packages/dartssh2
```

- [ ] **Step 6: Get dependencies**

```bash
cd app && flutter pub get
```
Expected: resolves successfully with `dartssh2` from local path.

- [ ] **Step 7: Remove the `@override` warning on `signAsync` in `certificate_key_pair.dart`**

Now that the fork exports `signAsync`, the `@override` annotation on `CertificateKeyPair.signAsync` is valid. Check `flutter analyze` is clean:

```bash
cd app && flutter analyze
```
Expected: no errors.

- [ ] **Step 8: Run full test suite**

```bash
cd app && flutter test
```
Expected: all pass.

- [ ] **Step 9: Commit**

```bash
git add packages/dartssh2 app/pubspec.yaml app/pubspec.lock
git commit -m "chore: add local dartssh2 fork with signAsync() for agent auth support"
```

---

## Task 9: Implement `SystemAgentProxy`

**Files:**
- Create: `app/lib/services/system_agent_proxy.dart`
- Create: `app/test/services/system_agent_proxy_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// app/test/services/system_agent_proxy_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/system_agent_proxy.dart';

// Builds an SSH agent wire message: [uint32: body_len][body_bytes]
Uint8List _agentMsg(List<int> body) {
  final header = Uint8List(4);
  ByteData.view(header.buffer).setUint32(0, body.length, Endian.big);
  return Uint8List.fromList([...header, ...body]);
}

// Writes a length-prefixed byte string field.
List<int> _strField(List<int> data) {
  final len = Uint8List(4);
  ByteData.view(len.buffer).setUint32(0, data.length, Endian.big);
  return [...len, ...data];
}

void main() {
  group('SystemAgentProxy', () {
    late ServerSocket server;
    late String socketPath;

    setUp(() async {
      socketPath = '/tmp/yourssh_test_${DateTime.now().millisecondsSinceEpoch}.sock';
      server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
    });

    tearDown(() async {
      await server.close();
      final f = File(socketPath);
      if (await f.exists()) await f.delete();
    });

    test('getIdentities returns one AgentKeyPair with correct type', () async {
      // Mock agent: respond to request identities (11) with one ed25519 key blob.
      final algName = utf8.encode('ssh-ed25519');
      final keyBlob = Uint8List.fromList([
        ..._strField(algName), // algorithm name
        ..._strField(List.filled(32, 0xAB)), // dummy key bytes
      ]);

      unawaited(server.first.then((client) {
        client.listen((_) {
          final nkeys = Uint8List(4);
          ByteData.view(nkeys.buffer).setUint32(0, 1, Endian.big);
          final response = [
            12, // SSH_AGENT_IDENTITIES_ANSWER
            ...nkeys,
            ..._strField(keyBlob),
            ..._strField(utf8.encode('test-key')), // comment
          ];
          client.add(_agentMsg(response));
        });
      }));

      final proxy = await SystemAgentProxy.connectTo(socketPath);
      final identities = await proxy.getIdentities();

      expect(identities.length, 1);
      expect(identities[0].type, 'ssh-ed25519');
      expect(identities[0].toPublicKey().encode(), equals(keyBlob));

      await proxy.close();
    });

    test('getIdentities returns empty list when agent has no keys', () async {
      unawaited(server.first.then((client) {
        client.listen((_) {
          final nkeys = Uint8List(4); // 0 keys
          final response = [12, ...nkeys];
          client.add(_agentMsg(response));
        });
      }));

      final proxy = await SystemAgentProxy.connectTo(socketPath);
      final identities = await proxy.getIdentities();
      expect(identities, isEmpty);
      await proxy.close();
    });

    test('connectTo throws SSHAgentUnavailableException for missing socket', () async {
      await expectLater(
        SystemAgentProxy.connectTo('/tmp/nonexistent_socket_xyz.sock'),
        throwsA(isA<SSHAgentUnavailableException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd app && flutter test test/services/system_agent_proxy_test.dart -v
```
Expected: FAIL — `SystemAgentProxy` does not exist.

- [ ] **Step 3: Implement `SystemAgentProxy`**

Create `app/lib/services/system_agent_proxy.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';

/// Thrown when the SSH agent socket cannot be reached.
class SSHAgentUnavailableException implements Exception {
  final String message;
  const SSHAgentUnavailableException(this.message);
  @override
  String toString() => 'SSHAgentUnavailableException: $message';
}

/// Connects to the system ssh-agent and vends [SSHKeyPair] objects for each
/// identity the agent holds. Each pair signs via the agent socket.
class SystemAgentProxy {
  final _AgentSession _session;

  SystemAgentProxy._(this._session);

  /// Connects using [SSH_AUTH_SOCK] from the environment (macOS / Linux).
  static Future<SystemAgentProxy> connect() async {
    if (Platform.isWindows) {
      final sockPath = Platform.environment['SSH_AUTH_SOCK'];
      if (sockPath == null || sockPath.isEmpty) {
        throw const SSHAgentUnavailableException(
          'SSH_AUTH_SOCK is not set. On Windows, set it via Git Bash, WSL, or the OpenSSH agent.',
        );
      }
      return connectTo(sockPath);
    }
    final sockPath = Platform.environment['SSH_AUTH_SOCK'];
    if (sockPath == null || sockPath.isEmpty) {
      throw const SSHAgentUnavailableException('SSH_AUTH_SOCK is not set');
    }
    return connectTo(sockPath);
  }

  /// Connects to the agent socket at [socketPath]. Primarily for testing.
  static Future<SystemAgentProxy> connectTo(String socketPath) async {
    try {
      final socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      return SystemAgentProxy._(_AgentSession(socket));
    } catch (e) {
      throw SSHAgentUnavailableException('Cannot connect to SSH agent at $socketPath: $e');
    }
  }

  /// Requests all identities from the agent and returns them as [SSHKeyPair]s.
  Future<List<SSHKeyPair>> getIdentities() async {
    // SSH_AGENTC_REQUEST_IDENTITIES = 11
    final req = _AgentWriter()..writeUint8(11);
    _session.write(req.buildMessage());

    final body = await _session.readMessage();
    final reader = _AgentReader(body);
    final type = reader.readUint8();
    if (type != 12) {
      throw SSHAgentUnavailableException('Expected IDENTITIES_ANSWER (12), got $type');
    }

    final nkeys = reader.readUint32();
    final pairs = <SSHKeyPair>[];
    for (var i = 0; i < nkeys; i++) {
      final keyBlob = reader.readBytes();
      reader.readBytes(); // comment — ignored
      pairs.add(_AgentKeyPair(keyBlob, _session));
    }
    return pairs;
  }

  Future<void> close() => _session.close();
}

// ── SSH agent protocol helpers ──────────────────────────────────────────────

class _AgentWriter {
  final _buf = BytesBuilder();

  void writeUint8(int v) => _buf.addByte(v);

  void writeUint32(int v) {
    final b = Uint8List(4);
    ByteData.view(b.buffer).setUint32(0, v, Endian.big);
    _buf.add(b);
  }

  void writeBytes(List<int> data) {
    writeUint32(data.length);
    _buf.add(data);
  }

  /// Wraps the buffered body with a 4-byte length prefix.
  Uint8List buildMessage() {
    final body = _buf.toBytes();
    final header = Uint8List(4);
    ByteData.view(header.buffer).setUint32(0, body.length, Endian.big);
    return Uint8List.fromList([...header, ...body]);
  }
}

class _AgentReader {
  final Uint8List _data;
  int _offset = 0;

  _AgentReader(this._data);

  int readUint8() => _data[_offset++];

  int readUint32() {
    final v = ByteData.view(
      _data.buffer, _data.offsetInBytes + _offset, 4,
    ).getUint32(0, Endian.big);
    _offset += 4;
    return v;
  }

  Uint8List readBytes() {
    final len = readUint32();
    final result = _data.sublist(_offset, _offset + len);
    _offset += len;
    return result;
  }
}

/// Buffers incoming socket data and supports async reads of exact byte counts.
class _AgentSession {
  final Socket _socket;
  final _buffer = <int>[];
  Completer<void>? _dataWaiter;
  late final StreamSubscription<List<int>> _sub;

  _AgentSession(this._socket) {
    _sub = _socket.listen((chunk) {
      _buffer.addAll(chunk);
      _dataWaiter?.complete();
      _dataWaiter = null;
    });
  }

  void write(List<int> data) => _socket.add(data);

  Future<Uint8List> _readExact(int count) async {
    while (_buffer.length < count) {
      _dataWaiter = Completer();
      await _dataWaiter!.future;
    }
    final result = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return result;
  }

  Future<Uint8List> readMessage() async {
    final header = await _readExact(4);
    final len = ByteData.view(header.buffer).getUint32(0, Endian.big);
    return _readExact(len);
  }

  Future<void> close() async {
    await _sub.cancel();
    await _socket.close();
  }
}

// ── Agent-backed key pair ────────────────────────────────────────────────────

class _AgentKeyPair implements SSHKeyPair {
  final Uint8List _keyBlob;
  final _AgentSession _session;

  _AgentKeyPair(this._keyBlob, this._session);

  @override
  String get name => type;

  @override
  String get type {
    if (_keyBlob.length < 4) throw FormatException('Key blob too short');
    final nameLen = ByteData.view(
      _keyBlob.buffer, _keyBlob.offsetInBytes, 4,
    ).getUint32(0, Endian.big);
    return utf8.decode(_keyBlob.sublist(4, 4 + nameLen));
  }

  @override
  SSHHostKey toPublicKey() => _RawBlobHostKey(_keyBlob);

  @override
  SSHSignature sign(Uint8List data) {
    throw UnsupportedError('_AgentKeyPair requires signAsync() — use the patched dartssh2 fork');
  }

  @override
  Future<SSHSignature> signAsync(Uint8List data) async {
    // SSH_AGENTC_SIGN_REQUEST = 13
    final req = _AgentWriter()
      ..writeUint8(13)
      ..writeBytes(_keyBlob)
      ..writeBytes(data)
      ..writeUint32(0); // flags: 0 for default (RSA SHA-1 compat; SHA-256 = flag 4)
    _session.write(req.buildMessage());

    final body = await _session.readMessage();
    final reader = _AgentReader(body);
    final type = reader.readUint8();
    if (type != 14) {
      if (type == 5) throw Exception('SSH agent refused to sign (agent returned failure)');
      throw Exception('Unexpected agent response: $type');
    }
    final sig = reader.readBytes();
    return _RawSignature(sig);
  }

  @override
  String toPem() => throw UnsupportedError('Agent keys cannot be serialized to PEM');
}

class _RawBlobHostKey implements SSHHostKey {
  final Uint8List _bytes;
  const _RawBlobHostKey(this._bytes);
  @override
  Uint8List encode() => _bytes;
}

class _RawSignature implements SSHSignature {
  final Uint8List _bytes;
  const _RawSignature(this._bytes);
  @override
  Uint8List encode() => _bytes;
}
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
cd app && flutter test test/services/system_agent_proxy_test.dart -v
```
Expected: all 3 tests PASS.

- [ ] **Step 5: Run full suite**

```bash
cd app && flutter test
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/services/system_agent_proxy.dart app/test/services/system_agent_proxy_test.dart
git commit -m "feat: add SystemAgentProxy for SSH agent auth via SSH_AUTH_SOCK"
```

---

## Task 10: Wire `SystemAgentProxy` into `SshService`

**Files:**
- Modify: `app/lib/services/ssh_service.dart`

- [ ] **Step 1: Add a proxy registry and import**

In `app/lib/services/ssh_service.dart`:

Add the import:
```dart
import 'system_agent_proxy.dart';
```

Add a proxy map next to `_clients`:
```dart
final Map<String, SystemAgentProxy> _agentProxies = {};
```

- [ ] **Step 2: Handle `AuthType.agent` in `connect()`**

In the `connect()` method, add an `else if` branch for agent auth after the certificate branch:

```dart
} else if (host.authType == AuthType.agent) {
  final proxy = await SystemAgentProxy.connect();
  _agentProxies[host.id] = proxy;
  identities = await proxy.getIdentities();
  if (identities.isEmpty) {
    throw Exception(
      'SSH agent has no identities. Run "ssh-add <private-key>" to add one.',
    );
  }
}
```

- [ ] **Step 3: Close proxy on disconnect**

In `disconnect(String hostId)`, add proxy cleanup:

```dart
void disconnect(String hostId) {
  _shells.removeWhere((k, _) => k.startsWith(hostId));
  _clients[hostId]?.close();
  _clients.remove(hostId);
  _agentProxies[hostId]?.close(); // close the agent socket
  _agentProxies.remove(hostId);
}
```

- [ ] **Step 4: Apply same agent identity logic to `testConnection()`**

In `testConnection()`, add the agent branch (without storing a proxy since test connections are ephemeral):

```dart
} else if (host.authType == AuthType.agent) {
  try {
    final proxy = await SystemAgentProxy.connect();
    identities = await proxy.getIdentities();
    await proxy.close();
  } on SSHAgentUnavailableException catch (e) {
    return (success: false, latencyMs: 0, error: e.message);
  }
}
```

- [ ] **Step 5: Run analyze**

```bash
cd app && flutter analyze
```
Expected: no errors.

- [ ] **Step 6: Run full test suite**

```bash
cd app && flutter test
```
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add app/lib/services/ssh_service.dart
git commit -m "feat: wire SystemAgentProxy into SshService for AuthType.agent"
```

---

## Manual Verification Checklist

After all tasks complete:

**Certificate auth:**
- [ ] Add a key in Keychain; click "Link certificate…"; pick a real `-cert.pub` file → badge shows "CERT"
- [ ] Add a host with auth type "Certificate", select the key with cert → connects successfully to a server with `TrustedUserCAKeys` configured
- [ ] Add host with cert auth but cert file deleted → clear error message shown in session

**Agent auth:**
- [ ] Run `ssh-add ~/.ssh/id_ed25519` in terminal → agent has identity
- [ ] Add a host with auth type "SSH Agent" → connects successfully
- [ ] Run `ssh-add -D` (clear agent) → connect shows "SSH agent has no identities" error
- [ ] `SSH_AUTH_SOCK` unset → connect shows the unavailable error message

**Regressions:**
- [ ] Password auth still works
- [ ] Private key auth still works
- [ ] SFTP, port forwarding, and sync features still work
