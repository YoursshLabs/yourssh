# Jump Host / Bastion Proxy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow any saved host to route its SSH connection through a designated jump/bastion host, configurable via a dropdown in the host detail panel.

**Architecture:** The `dartssh2` library's `SSHClient.forwardLocal()` returns `SSHForwardChannel` which implements `SSHSocket`, making it a drop-in transport for a second `SSHClient`. `SshService` manages a separate `_jumpClients` map for cached bastion connections and a `_hostToJump` map for reference counting at disconnect time. The `SessionProvider` resolves the jump host object and its key entry before calling `SshService.connect()`. The `HostDetailPanel` adds a dropdown that sets `Host.jumpHostId`.

**Tech Stack:** Flutter/Dart, `dartssh2` (`SSHClient.forwardLocal`, `SSHForwardChannel`), `provider` package.

---

## Files

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `app/lib/models/host.dart` | Add `jumpHostId: String?` field |
| Modify | `app/test/models/host_test.dart` | Tests for new field |
| Modify | `app/lib/services/ssh_service.dart` | `_jumpClients`, `_hostToJump`, `_ensureJumpClient`, update `connect`/`disconnect`/`testConnection` |
| Modify | `app/lib/providers/session_provider.dart` | Add `jumpHostLookup` callback, update `_doConnect` |
| Modify | `app/lib/main.dart` | Wire `jumpHostLookup` callback |
| Modify | `app/lib/widgets/host_detail_panel.dart` | Add `_selectedJumpHostId` state, dropdown, update `_save` and `_test` |

---

## Task 1: Add `jumpHostId` to `Host` model

**Files:**
- Modify: `app/lib/models/host.dart`
- Modify: `app/test/models/host_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `app/test/models/host_test.dart` inside `group('Host', () {`:

```dart
test('jumpHostId round-trips through JSON', () {
  final h = Host(
    label: 'Target',
    host: '10.0.0.5',
    username: 'admin',
    jumpHostId: 'bastion-id-123',
  );
  final decoded = Host.fromJson(h.toJson());
  expect(decoded.jumpHostId, 'bastion-id-123');
});

test('jumpHostId defaults to null', () {
  final h = Host(label: 'x', host: 'y', username: 'z');
  expect(h.jumpHostId, isNull);
  final decoded = Host.fromJson(h.toJson());
  expect(decoded.jumpHostId, isNull);
});

test('copyWith preserves jumpHostId when not overridden', () {
  final h = Host(
    label: 'x', host: 'y', username: 'z', jumpHostId: 'jid',
  );
  final copy = h.copyWith(label: 'new label');
  expect(copy.jumpHostId, 'jid');
});

test('copyWith can clear jumpHostId', () {
  final h = Host(
    label: 'x', host: 'y', username: 'z', jumpHostId: 'jid',
  );
  final copy = h.copyWith(jumpHostId: null);
  expect(copy.jumpHostId, isNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app && flutter test test/models/host_test.dart
```

Expected: compile error or failures because `jumpHostId` doesn't exist yet.

- [ ] **Step 3: Add `jumpHostId` to `Host`**

In `app/lib/models/host.dart`, make these changes:

Add field after `autoRecord`:
```dart
String? jumpHostId;
```

Update constructor (add after `autoRecord = false`):
```dart
this.jumpHostId,
```

Update `toJson` (add after `'autoRecord': autoRecord`):
```dart
'jumpHostId': jumpHostId,
```

Update `fromJson` (add after `autoRecord: ...`):
```dart
jumpHostId: json['jumpHostId'] as String?,
```

Update `copyWith` signature (add after `bool? autoRecord`):
```dart
Object? jumpHostId = const _Unset(),
```

Add sentinel class before or after `Host`:
```dart
class _Unset { const _Unset(); }
```

Update `copyWith` body (add after `autoRecord: autoRecord ?? this.autoRecord`):
```dart
jumpHostId: jumpHostId is _Unset ? this.jumpHostId : jumpHostId as String?,
```

> **Why sentinel?** `copyWith(jumpHostId: null)` must clear the field; a plain nullable param can't distinguish "not passed" from "pass null". The `_Unset` sentinel handles this.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd app && flutter test test/models/host_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/host.dart app/test/models/host_test.dart
git commit -m "feat: add jumpHostId field to Host model"
```

---

## Task 2: Update `SshService` with jump client support

**Files:**
- Modify: `app/lib/services/ssh_service.dart`

- [ ] **Step 1: Add jump state maps and `_ensureJumpClient`**

In `app/lib/services/ssh_service.dart`, after the existing map declarations (`_clients`, `_shells`, `_agentProxies`), add:

```dart
final Map<String, SSHClient> _jumpClients = {};
final Map<String, String> _hostToJump = {}; // target hostId → jump hostId
```

Add the private helper method after the `connect` method (before `testConnection`):

```dart
Future<SSHClient> _ensureJumpClient(
  Host jumpHost, {
  SshKeyEntry? keyEntry,
  Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
}) async {
  if (_jumpClients.containsKey(jumpHost.id)) {
    return _jumpClients[jumpHost.id]!;
  }
  final password = await _storage.loadPassword(jumpHost.id);

  List<SSHKeyPair> identities = [];
  if (jumpHost.authType == AuthType.privateKey && keyEntry != null) {
    final keyFile = File(keyEntry.privateKeyPath);
    if (await keyFile.exists()) {
      final pem = await keyFile.readAsString();
      final passphrase = await _storage.loadPassphrase(keyEntry.id);
      identities = SSHKeyPair.fromPem(pem, passphrase ?? '');
    }
  } else if (jumpHost.authType == AuthType.certificate && keyEntry != null) {
    final certPath = keyEntry.certificatePath;
    if (certPath == null || !await File(certPath).exists()) {
      throw Exception('Jump host certificate file missing or not linked');
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

  final jumpClient = SSHClient(
    await SSHSocket.connect(jumpHost.host, jumpHost.port),
    username: jumpHost.username,
    onPasswordRequest: () => password ?? '',
    identities: identities.isNotEmpty ? identities : null,
    onVerifyHostKey: (type, fp) async {
      if (verifyHostKey != null) return verifyHostKey(type.toString(), fp);
      return true;
    },
  );
  await jumpClient.authenticated;
  _jumpClients[jumpHost.id] = jumpClient;
  return jumpClient;
}
```

- [ ] **Step 2: Update `connect()` to accept optional jump params**

Change the `connect` signature from:

```dart
Future<SSHClient> connect(
  Host host, {
  SshKeyEntry? keyEntry,
  Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
}) async {
```

To:

```dart
Future<SSHClient> connect(
  Host host, {
  SshKeyEntry? keyEntry,
  Host? jumpHost,
  SshKeyEntry? jumpKeyEntry,
  Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
}) async {
```

Replace the line that creates the socket inside `connect`:

```dart
      client = SSHClient(
        await SSHSocket.connect(host.host, host.port),
```

With:

```dart
      final SSHSocket socket;
      if (jumpHost != null) {
        final jc = await _ensureJumpClient(
          jumpHost,
          keyEntry: jumpKeyEntry,
          verifyHostKey: verifyHostKey,
        );
        socket = await jc.forwardLocal(host.host, host.port);
        _hostToJump[host.id] = jumpHost.id;
      } else {
        socket = await SSHSocket.connect(host.host, host.port);
      }
      client = SSHClient(
        socket,
```

- [ ] **Step 3: Update `disconnect()` to clean up jump client**

Replace the entire `disconnect` method body with:

```dart
void disconnect(String hostId) {
  final jumpHostId = _hostToJump.remove(hostId);

  final removed = _shells.keys.where((k) => k.startsWith(hostId)).toList();
  _shells.removeWhere((k, _) => k.startsWith(hostId));
  for (final id in removed) {
    NotificationService.instance.removeSession(id);
  }
  _clients[hostId]?.close();
  _clients.remove(hostId);
  unawaited(_agentProxies[hostId]?.close() ?? Future.value());
  _agentProxies.remove(hostId);

  if (jumpHostId != null && !_hostToJump.values.contains(jumpHostId)) {
    _jumpClients[jumpHostId]?.close();
    _jumpClients.remove(jumpHostId);
  }
}
```

- [ ] **Step 4: Update `testConnection()` to support jump**

Change the `testConnection` signature from:

```dart
Future<({bool success, int latencyMs, String? error})> testConnection(
  Host host, {
  String? password,
  SshKeyEntry? keyEntry,
}) async {
```

To:

```dart
Future<({bool success, int latencyMs, String? error})> testConnection(
  Host host, {
  String? password,
  SshKeyEntry? keyEntry,
  Host? jumpHost,
  SshKeyEntry? jumpKeyEntry,
}) async {
```

Inside `testConnection`, in the `try` block, replace:

```dart
      final socket = await SSHSocket.connect(host.host, host.port)
          .timeout(const Duration(seconds: 10));
```

With:

```dart
      SSHSocket socket;
      SSHClient? jumpClient;
      if (jumpHost != null) {
        final jumpPassword = await _storage.loadPassword(jumpHost.id);
        List<SSHKeyPair> jumpIdentities = [];
        if (jumpHost.authType == AuthType.privateKey && jumpKeyEntry != null) {
          final keyFile = File(jumpKeyEntry.privateKeyPath);
          if (await keyFile.exists()) {
            final pem = await keyFile.readAsString();
            final passphrase = await _storage.loadPassphrase(jumpKeyEntry.id);
            jumpIdentities = SSHKeyPair.fromPem(pem, passphrase ?? '');
          }
        }
        jumpClient = SSHClient(
          await SSHSocket.connect(jumpHost.host, jumpHost.port)
              .timeout(const Duration(seconds: 10)),
          username: jumpHost.username,
          onPasswordRequest: () => jumpPassword ?? '',
          identities: jumpIdentities.isNotEmpty ? jumpIdentities : null,
          onVerifyHostKey: (_, _) async => true,
        );
        await jumpClient.authenticated.timeout(const Duration(seconds: 10));
        socket = await jumpClient.forwardLocal(host.host, host.port)
            .timeout(const Duration(seconds: 10));
      } else {
        socket = await SSHSocket.connect(host.host, host.port)
            .timeout(const Duration(seconds: 10));
      }
```

Add `jumpClient?.close();` to the `finally` block, before `client?.close()`:

```dart
    } finally {
      client?.close();
      jumpClient?.close();
      await agentProxy?.close();
    }
```

> **Note:** `jumpClient` must be declared outside the try block so `finally` can access it. Declare `SSHClient? jumpClient;` before the `try {` line.

- [ ] **Step 5: Run analyze**

```bash
cd app && flutter analyze lib/services/ssh_service.dart
```

Expected: no errors. Fix any type issues.

- [ ] **Step 6: Commit**

```bash
git add app/lib/services/ssh_service.dart
git commit -m "feat: add jump host support to SshService"
```

---

## Task 3: Wire jump host resolution in `SessionProvider` and `main.dart`

**Files:**
- Modify: `app/lib/providers/session_provider.dart`
- Modify: `app/lib/main.dart`

- [ ] **Step 1: Add `jumpHostLookup` callback to `SessionProvider`**

In `app/lib/providers/session_provider.dart`, add the callback field alongside the existing ones (`keyLookup`, `autoReconnectEnabled`, etc.):

```dart
Host? Function(String jumpHostId)? jumpHostLookup;
```

- [ ] **Step 2: Update `_doConnect` to resolve and pass jump host**

In `_doConnect`, replace:

```dart
      final keyEntry = host.keyId != null ? keyLookup?.call(host.keyId!) : null;
      await _ssh.connect(
        host,
        keyEntry: keyEntry,
        verifyHostKey: hostKeyVerifier != null
            ? (keyType, fp) => hostKeyVerifier!(host.host, host.port, keyType, fp)
            : null,
      );
```

With:

```dart
      final keyEntry = host.keyId != null ? keyLookup?.call(host.keyId!) : null;
      Host? jumpHost;
      SshKeyEntry? jumpKeyEntry;
      if (host.jumpHostId != null) {
        jumpHost = jumpHostLookup?.call(host.jumpHostId!);
        if (jumpHost != null && jumpHost.keyId != null) {
          jumpKeyEntry = keyLookup?.call(jumpHost.keyId!);
        }
      }
      await _ssh.connect(
        host,
        keyEntry: keyEntry,
        jumpHost: jumpHost,
        jumpKeyEntry: jumpKeyEntry,
        verifyHostKey: hostKeyVerifier != null
            ? (keyType, fp) => hostKeyVerifier!(host.host, host.port, keyType, fp)
            : null,
      );
```

- [ ] **Step 3: Wire callback in `main.dart`**

In `app/lib/main.dart`, after the existing `_sessionProvider.keyLookup` line:

```dart
    _sessionProvider.keyLookup = (id) => _keyProvider.findById(id);
```

Add:

```dart
    _sessionProvider.jumpHostLookup = (id) =>
        _hostProvider.allHosts.where((h) => h.id == id).firstOrNull;
```

- [ ] **Step 4: Run analyze**

```bash
cd app && flutter analyze lib/providers/session_provider.dart lib/main.dart
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/session_provider.dart app/lib/main.dart app/pubspec.yaml app/pubspec.lock
git commit -m "feat: wire jump host resolution in SessionProvider and main"
```

---

## Task 4: Update `HostDetailPanel` — jump host UI

**Files:**
- Modify: `app/lib/widgets/host_detail_panel.dart`

- [ ] **Step 1: Add `_selectedJumpHostId` state**

In `_HostDetailPanelState`, add the field after `_autoRecord`:

```dart
String? _selectedJumpHostId;
```

In `initState`, after `_autoRecord = h?.autoRecord ?? false;`, add:

```dart
_selectedJumpHostId = h?.jumpHostId;
```

- [ ] **Step 2: Update `_save()` to include `jumpHostId`**

In `_save()`, change the `Host(...)` constructor call to include `jumpHostId`:

```dart
    final host = Host(
      id: widget.existing?.id,
      label: _labelCtrl.text.trim().isEmpty ? _hostCtrl.text.trim() : _labelCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text) ?? 22,
      username: _usernameCtrl.text.trim(),
      authType: _authType,
      keyId: _authType == AuthType.privateKey ? _selectedKeyId : null,
      group: _groupCtrl.text.trim(),
      tags: tags,
      autoRecord: _autoRecord,
      jumpHostId: _selectedJumpHostId,
    );
```

- [ ] **Step 3: Update `_test()` to resolve jump host and pass it**

In `_test()`, after the line that sets `keyEntry`, add jump resolution:

```dart
    final allHosts = context.read<HostProvider>().allHosts;
    Host? jumpHost;
    if (_selectedJumpHostId != null) {
      jumpHost = allHosts.where((h) => h.id == _selectedJumpHostId).firstOrNull;
    }
    final jumpKeyEntry = (jumpHost != null && jumpHost.keyId != null)
        ? context.read<KeyProvider>().findById(jumpHost.keyId!)
        : null;
```

Also update the `Host` built in `_test()` to include `jumpHostId`:

```dart
    final host = Host(
      id: widget.existing?.id,
      label: _hostCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text) ?? 22,
      username: _usernameCtrl.text.trim(),
      authType: _authType,
      keyId: _authType == AuthType.privateKey ? _selectedKeyId : null,
      group: '',
      tags: const [],
      jumpHostId: _selectedJumpHostId,
    );
```

Update the `testConnection` call to pass jump params:

```dart
    final result = await context.read<SshService>().testConnection(
      host,
      password: _passwordCtrl.text,
      keyEntry: keyEntry,
      jumpHost: jumpHost,
      jumpKeyEntry: jumpKeyEntry,
    );
```

Add the `HostProvider` import at the top of `host_detail_panel.dart` if not already present:

```dart
import '../providers/host_provider.dart';
```

- [ ] **Step 4: Add the jump host dropdown to the form**

In `build()`, the form's `ListView` children include a `_sectionLabel('RECORDING')` section. Insert the jump host section **before** `_sectionLabel('RECORDING')`:

```dart
                  const SizedBox(height: 16),
                  _sectionLabel('JUMP HOST'),
                  const SizedBox(height: 6),
                  Builder(builder: (context) {
                    final allHosts = context.watch<HostProvider>().allHosts;
                    final existingId = widget.existing?.id;
                    final otherHosts = allHosts
                        .where((h) => h.id != existingId)
                        .toList();
                    if (otherHosts.isEmpty) return const SizedBox.shrink();
                    return _Card(children: [
                      _DropdownRow(
                        icon: Icons.hive_outlined,
                        child: DropdownButton<String?>(
                          value: _selectedJumpHostId,
                          isExpanded: true,
                          hint: const Text(
                            'None (direct connection)',
                            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                          ),
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                          dropdownColor: AppColors.card,
                          underline: const SizedBox(),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('None (direct connection)',
                                  style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
                            ),
                            ...otherHosts.map((h) => DropdownMenuItem<String?>(
                              value: h.id,
                              child: Text(
                                '${h.label} (${h.username}@${h.host})',
                                style: const TextStyle(fontSize: 13),
                              ),
                            )),
                          ],
                          onChanged: (v) => setState(() => _selectedJumpHostId = v),
                        ),
                      ),
                    ]);
                  }),
```

- [ ] **Step 5: Run analyze**

```bash
cd app && flutter analyze lib/widgets/host_detail_panel.dart
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/host_detail_panel.dart
git commit -m "feat: add jump host dropdown to HostDetailPanel"
```

---

## Task 5: Update README and roadmap

**Files:**
- Modify: `README.md`
- Modify: `docs/PLAN.md`

- [ ] **Step 1: Add jump host to README features**

In `README.md`, under `### Terminal & Connectivity`, add after the `Port forwarding` bullet:

```markdown
- **Jump host / bastion proxy** — connect to internal servers via a bastion host; select any saved host as the jump hop in the host detail panel
```

- [ ] **Step 2: Update roadmap**

In `docs/PLAN.md`, find the Jump Host entry (if it exists as a planned item) and mark it as shipped, or add a shipped entry.

- [ ] **Step 3: Commit**

```bash
git add README.md docs/PLAN.md
git commit -m "docs: add jump host to README and mark shipped in roadmap"
```

---

## Manual Test Checklist

After all tasks complete, verify end-to-end:

1. **Add jump host:** Create a bastion host entry (e.g., `bastion.example.com`). Open a second host's detail panel → "Jump Host" dropdown shows the bastion.
2. **Save and connect:** Select the bastion as jump host, save, connect. Session opens through the bastion.
3. **Shared jump client:** Open a second host with the same jump host. Verify only one bastion connection is made (check with `ss -tnp` on the bastion).
4. **Disconnect cleanup:** Disconnect both targets. Jump client is closed.
5. **Test Connection:** Click "TEST CONNECTION" on a host with a jump host configured. Should succeed if both bastion and target are reachable.
6. **SFTP:** Open SFTP panel on the jump-proxied host. Files should load.
7. **None option:** Set jump host to `None`. Direct connection works again.
