# Known Hosts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement SSH host key verification (TOFU + mismatch dialog + Known Hosts management screen).

**Architecture:** `KnownHostsProvider` owns all host-key state and exposes `verifyHostKey()`, which is passed as a callback through `SessionProvider` → `SshService.connect()` → `onVerifyHostKey`. For host-key mismatches, the provider creates a `HostKeyChallenge` (Completer wrapper) and notifies; `_MainScreenState` watches the provider and shows a blocking dialog, then resolves the completer.

**Tech Stack:** Flutter / Dart, dartssh2 ^2.9.0, shared_preferences, provider.

---

## File Map

| Action | Path | Responsibility |
|--------|------|---------------|
| Create | `app/lib/models/known_host.dart` | `KnownHost` model, `HostKeyChallenge`, fingerprint helper |
| Create | `app/lib/providers/known_hosts_provider.dart` | TOFU/verify logic, `pendingChallenge` state |
| Create | `app/lib/widgets/known_hosts_screen.dart` | List UI with delete |
| Create | `app/test/models/known_host_test.dart` | Model serialization tests |
| Create | `app/test/providers/known_hosts_provider_test.dart` | Verify logic tests |
| Modify | `app/lib/services/storage_service.dart` | Add `loadKnownHosts` / `saveKnownHosts` |
| Modify | `app/lib/services/ssh_service.dart` | Add optional `verifyHostKey` param to `connect()` |
| Modify | `app/lib/providers/session_provider.dart` | Add `hostKeyVerifier` field, pass to `connect()` |
| Modify | `app/lib/main.dart` | Register `KnownHostsProvider`, wire to `SessionProvider` |
| Modify | `app/lib/screens/main_screen.dart` | Add screen case, dialog listener |

---

### Task 1: KnownHost model + HostKeyChallenge

**Files:**
- Create: `app/lib/models/known_host.dart`
- Create: `app/test/models/known_host_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models/known_host_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/known_host.dart';

void main() {
  group('KnownHost', () {
    test('toJson/fromJson round-trips all fields', () {
      final h = KnownHost(
        host: '192.168.1.1',
        port: 22,
        keyType: 'ecdsa-sha2-nistp256',
        fingerprint: 'ab:cd:ef',
        addedAt: DateTime.utc(2026, 5, 29),
      );
      final decoded = KnownHost.fromJson(h.toJson());
      expect(decoded.host, '192.168.1.1');
      expect(decoded.port, 22);
      expect(decoded.keyType, 'ecdsa-sha2-nistp256');
      expect(decoded.fingerprint, 'ab:cd:ef');
      expect(decoded.lookupKey, '192.168.1.1:22:ecdsa-sha2-nistp256');
    });

    test('bytesToFingerprint converts bytes to colon-hex', () {
      final bytes = Uint8List.fromList([0xab, 0xcd, 0x0f]);
      expect(KnownHost.bytesToFingerprint(bytes), 'ab:cd:0f');
    });
  });

  group('HostKeyChallenge', () {
    test('resolve(true) completes result as true', () async {
      final c = HostKeyChallenge(
        host: 'h', port: 22, keyType: 'k',
        oldFingerprint: 'old', newFingerprint: 'new',
      );
      c.resolve(true);
      expect(await c.result, true);
    });

    test('second resolve is a no-op', () async {
      final c = HostKeyChallenge(
        host: 'h', port: 22, keyType: 'k',
        oldFingerprint: 'old', newFingerprint: 'new',
      );
      c.resolve(true);
      c.resolve(false); // must not throw or overwrite
      expect(await c.result, true);
    });
  });
}
```

- [ ] **Step 2: Run test — expect compile failure (class missing)**

```bash
cd app && flutter test test/models/known_host_test.dart
```

Expected: `Error: Cannot find 'KnownHost'`

- [ ] **Step 3: Create the model**

```dart
// app/lib/models/known_host.dart
import 'dart:async';
import 'dart:typed_data';

class KnownHost {
  final String host;
  final int port;
  final String keyType;
  final String fingerprint;
  final DateTime addedAt;

  const KnownHost({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    required this.addedAt,
  });

  String get lookupKey => '$host:$port:$keyType';

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'keyType': keyType,
        'fingerprint': fingerprint,
        'addedAt': addedAt.toIso8601String(),
      };

  factory KnownHost.fromJson(Map<String, dynamic> json) => KnownHost(
        host: json['host'] as String,
        port: json['port'] as int,
        keyType: json['keyType'] as String,
        fingerprint: json['fingerprint'] as String,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );

  static String bytesToFingerprint(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
}

class HostKeyChallenge {
  final String host;
  final int port;
  final String keyType;
  final String oldFingerprint;
  final String newFingerprint;
  final _completer = Completer<bool>();

  HostKeyChallenge({
    required this.host,
    required this.port,
    required this.keyType,
    required this.oldFingerprint,
    required this.newFingerprint,
  });

  void resolve(bool trust) {
    if (!_completer.isCompleted) _completer.complete(trust);
  }

  Future<bool> get result => _completer.future;
}
```

- [ ] **Step 4: Run test — expect all pass**

```bash
cd app && flutter test test/models/known_host_test.dart
```

Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/known_host.dart app/test/models/known_host_test.dart
git commit -m "feat: add KnownHost model and HostKeyChallenge"
```

---

### Task 2: StorageService — known hosts CRUD

**Files:**
- Modify: `app/lib/services/storage_service.dart`

- [ ] **Step 1: Add import and two methods**

In `app/lib/services/storage_service.dart`, add `import '../models/known_host.dart';` at the top, then append after the `deletePassword`/`savePassphrase`/`loadPassphrase` block:

```dart
  // ── Known Hosts ────────────────────────────────────────────

  static const _knownHostsKey = 'yourssh.known_hosts';

  Future<List<KnownHost>> loadKnownHosts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_knownHostsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => KnownHost.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveKnownHosts(List<KnownHost> hosts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _knownHostsKey, jsonEncode(hosts.map((h) => h.toJson()).toList()));
  }
```

- [ ] **Step 2: Analyze to confirm no compile errors**

```bash
cd app && flutter analyze lib/services/storage_service.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/services/storage_service.dart
git commit -m "feat: add known hosts storage to StorageService"
```

---

### Task 3: KnownHostsProvider

**Files:**
- Create: `app/lib/providers/known_hosts_provider.dart`
- Create: `app/test/providers/known_hosts_provider_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// app/test/providers/known_hosts_provider_test.dart
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
      expect(provider.hosts.length, 1); // no duplicate added
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

  group('remove', () {
    test('removes matching entry', () async {
      final provider = KnownHostsProvider.forTest([_entry(host, 'aa:bb:cc')]);
      await provider.remove(provider.hosts.first);
      expect(provider.hosts, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test — expect compile failure**

```bash
cd app && flutter test test/providers/known_hosts_provider_test.dart
```

Expected: `Error: Cannot find 'KnownHostsProvider'`

- [ ] **Step 3: Create the provider**

```dart
// app/lib/providers/known_hosts_provider.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/known_host.dart';
import '../services/storage_service.dart';

class KnownHostsProvider extends ChangeNotifier {
  final StorageService? _storage;
  List<KnownHost> _hosts;
  HostKeyChallenge? _pendingChallenge;

  KnownHostsProvider(StorageService storage)
      : _storage = storage,
        _hosts = [];

  // For unit tests only — no storage, pre-loaded hosts.
  KnownHostsProvider.forTest(List<KnownHost> initial)
      : _storage = null,
        _hosts = List.of(initial);

  List<KnownHost> get hosts => List.unmodifiable(_hosts);
  HostKeyChallenge? get pendingChallenge => _pendingChallenge;

  Future<void> load() async {
    if (_storage == null) return;
    _hosts = await _storage.loadKnownHosts();
    notifyListeners();
  }

  Future<void> remove(KnownHost entry) async {
    _hosts.removeWhere((h) =>
        h.host == entry.host && h.port == entry.port && h.keyType == entry.keyType);
    await _storage?.saveKnownHosts(_hosts);
    notifyListeners();
  }

  Future<bool> verifyHostKey(
      String host, int port, String keyType, Uint8List fingerprint) async {
    final fp = KnownHost.bytesToFingerprint(fingerprint);
    final existing = _hosts
        .where((h) => h.host == host && h.port == port && h.keyType == keyType)
        .firstOrNull;

    if (existing == null) {
      _hosts.add(KnownHost(
          host: host, port: port, keyType: keyType, fingerprint: fp, addedAt: DateTime.now()));
      await _storage?.saveKnownHosts(_hosts);
      notifyListeners();
      return true;
    }

    if (existing.fingerprint == fp) return true;

    // Key mismatch — raise challenge; block until UI resolves it.
    final challenge = HostKeyChallenge(
      host: host, port: port, keyType: keyType,
      oldFingerprint: existing.fingerprint, newFingerprint: fp,
    );
    _pendingChallenge = challenge;
    notifyListeners();

    final trusted = await challenge.result;
    _pendingChallenge = null;

    if (trusted) {
      _hosts.removeWhere(
          (h) => h.host == host && h.port == port && h.keyType == keyType);
      _hosts.add(KnownHost(
          host: host, port: port, keyType: keyType, fingerprint: fp, addedAt: DateTime.now()));
      await _storage?.saveKnownHosts(_hosts);
    }

    notifyListeners();
    return trusted;
  }
}
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
cd app && flutter test test/providers/known_hosts_provider_test.dart
```

Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/known_hosts_provider.dart app/test/providers/known_hosts_provider_test.dart
git commit -m "feat: add KnownHostsProvider with TOFU verification and challenge bridge"
```

---

### Task 4: SshService — wire verifyHostKey callback

**Files:**
- Modify: `app/lib/services/ssh_service.dart`

- [ ] **Step 1: Update `connect()` signature and `onVerifyHostKey` body**

Replace the existing `connect` method in `app/lib/services/ssh_service.dart` (`Future<SSHClient> connect(Host host, {SshKeyEntry? keyEntry})`) with:

```dart
  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    final password = await _storage.loadPassword(host.id);

    List<SSHKeyPair> identities = [];
    if (host.authType == AuthType.privateKey && keyEntry != null) {
      final keyFile = File(keyEntry.privateKeyPath);
      if (await keyFile.exists()) {
        final pem = await keyFile.readAsString();
        final passphrase = await _storage.loadPassphrase(keyEntry.id);
        identities = SSHKeyPair.fromPem(pem, passphrase ?? '');
      }
    }

    final client = SSHClient(
      await SSHSocket.connect(host.host, host.port),
      username: host.username,
      onPasswordRequest: () => password ?? '',
      identities: identities.isNotEmpty ? identities : null,
      onVerifyHostKey: (type, fp) async {
        if (verifyHostKey != null) return verifyHostKey(type.name, fp);
        return true;
      },
    );

    await client.authenticated;
    _clients[host.id] = client;
    return client;
  }
```

> **Note:** `type.name` comes from dartssh2's `SSHHostKeyType` class which exposes a `String name` field. If the analyzer reports `name` not found, use `type.toString()` instead.

- [ ] **Step 2: Analyze**

```bash
cd app && flutter analyze lib/services/ssh_service.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/services/ssh_service.dart
git commit -m "feat: add optional verifyHostKey callback to SshService.connect"
```

---

### Task 5: SessionProvider — hostKeyVerifier field

**Files:**
- Modify: `app/lib/providers/session_provider.dart`

- [ ] **Step 1: Add import and field**

Add to imports at top of `app/lib/providers/session_provider.dart`:

```dart
import 'dart:typed_data';
```

Add field alongside the other callback fields (`keyLookup`, `autoReconnectEnabled`, etc.):

```dart
  Future<bool> Function(String host, int port, String keyType, Uint8List fp)? hostKeyVerifier;
```

- [ ] **Step 2: Pass it to `_ssh.connect()`**

In `_doConnect`, change the `_ssh.connect` call from:

```dart
      await _ssh.connect(host, keyEntry: keyEntry);
```

to:

```dart
      await _ssh.connect(
        host,
        keyEntry: keyEntry,
        verifyHostKey: hostKeyVerifier != null
            ? (keyType, fp) => hostKeyVerifier!(host.host, host.port, keyType, fp)
            : null,
      );
```

- [ ] **Step 3: Analyze**

```bash
cd app && flutter analyze lib/providers/session_provider.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add app/lib/providers/session_provider.dart
git commit -m "feat: wire hostKeyVerifier callback through SessionProvider"
```

---

### Task 6: main.dart — register provider and wire callback

**Files:**
- Modify: `app/lib/main.dart`

- [ ] **Step 1: Add import**

```dart
import 'providers/known_hosts_provider.dart';
```

- [ ] **Step 2: Add field**

Alongside the other `late final` fields in `_YourSSHAppState`:

```dart
  late final KnownHostsProvider _knownHostsProvider;
```

- [ ] **Step 3: Initialize and wire in `initState`**

After the `_sessionProvider` setup lines (after `_sessionProvider.tmuxEnabled = ...`), add:

```dart
    _knownHostsProvider = KnownHostsProvider(_storage);
    _knownHostsProvider.load();
    _sessionProvider.hostKeyVerifier = _knownHostsProvider.verifyHostKey;
```

- [ ] **Step 4: Dispose**

In `dispose()`, add before `super.dispose()`:

```dart
    _knownHostsProvider.dispose();
```

- [ ] **Step 5: Register in MultiProvider**

Inside the `providers:` list, add:

```dart
        ChangeNotifierProvider.value(value: _knownHostsProvider),
```

(place it after `ChangeNotifierProvider.value(value: _sessionProvider)`)

- [ ] **Step 6: Analyze**

```bash
cd app && flutter analyze lib/main.dart
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/main.dart
git commit -m "feat: register KnownHostsProvider and wire hostKeyVerifier"
```

---

### Task 7: KnownHostsScreen UI

**Files:**
- Create: `app/lib/widgets/known_hosts_screen.dart`

- [ ] **Step 1: Create the screen**

```dart
// app/lib/widgets/known_hosts_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/known_host.dart';
import '../providers/known_hosts_provider.dart';
import '../theme/app_theme.dart';

class KnownHostsScreen extends StatefulWidget {
  const KnownHostsScreen({super.key});

  @override
  State<KnownHostsScreen> createState() => _KnownHostsScreenState();
}

class _KnownHostsScreenState extends State<KnownHostsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<KnownHostsProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<KnownHostsProvider>();
    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          _TopBar(),
          Expanded(
            child: provider.hosts.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(24),
                    itemCount: provider.hosts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _HostTile(entry: provider.hosts[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: const Align(
        alignment: Alignment.centerLeft,
        child: Text('Known Hosts',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fact_check_outlined, size: 48, color: AppColors.textTertiary),
          SizedBox(height: 12),
          Text('No known hosts yet',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          SizedBox(height: 4),
          Text('Connect to a server to add one.',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _HostTile extends StatelessWidget {
  final KnownHost entry;
  const _HostTile({required this.entry});

  String _shortFp(String fp) {
    final parts = fp.split(':');
    if (parts.length <= 4) return fp;
    return '${parts.take(4).join(':')}…';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text('${entry.host}:${entry.port}',
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Text(entry.keyType,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ),
          Expanded(
            flex: 3,
            child: Tooltip(
              message: entry.fingerprint,
              child: Text(_shortFp(entry.fingerprint),
                  style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      fontFamily: 'monospace')),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.content_copy,
                size: 14, color: AppColors.textTertiary),
            tooltip: 'Copy fingerprint',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: entry.fingerprint)),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 16, color: AppColors.textTertiary),
            tooltip: 'Remove',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => context.read<KnownHostsProvider>().remove(entry),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
cd app && flutter analyze lib/widgets/known_hosts_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/known_hosts_screen.dart
git commit -m "feat: add KnownHostsScreen widget"
```

---

### Task 8: MainScreen — add screen case + host-key mismatch dialog

**Files:**
- Modify: `app/lib/screens/main_screen.dart`

- [ ] **Step 1: Add imports**

At the top of `app/lib/screens/main_screen.dart`, add:

```dart
import '../models/known_host.dart';
import '../providers/known_hosts_provider.dart';
import '../widgets/known_hosts_screen.dart';
```

- [ ] **Step 2: Add `KnownHostsScreen` to the body switch**

In `_buildBody()`, add the case before `_ =>`:

```dart
      NavSection.knownHosts => const KnownHostsScreen(),
```

- [ ] **Step 3: Add listener fields to `_MainScreenState`**

Alongside `SessionProvider? _sessionProvider;`, add:

```dart
  KnownHostsProvider? _knownHostsProvider;
  bool _hostKeyDialogShowing = false;
```

- [ ] **Step 4: Wire listener in `didChangeDependencies`**

The existing `didChangeDependencies` already handles `SessionProvider`. Add the same pattern for `KnownHostsProvider` inside the method, after the SessionProvider block:

```dart
    final knownHostsProvider = context.read<KnownHostsProvider>();
    if (_knownHostsProvider != knownHostsProvider) {
      _knownHostsProvider?.removeListener(_onKnownHostsChanged);
      _knownHostsProvider = knownHostsProvider;
      knownHostsProvider.addListener(_onKnownHostsChanged);
    }
```

- [ ] **Step 5: Add `_onKnownHostsChanged` and dialog handler**

Add these two methods to `_MainScreenState` alongside `_onSessionsChanged`:

```dart
  void _onKnownHostsChanged() {
    final challenge = _knownHostsProvider?.pendingChallenge;
    if (challenge != null && !_hostKeyDialogShowing && mounted) {
      _hostKeyDialogShowing = true;
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _HostKeyDialog(challenge: challenge),
      ).then((trusted) {
        challenge.resolve(trusted ?? false);
        _hostKeyDialogShowing = false;
      });
    }
  }
```

- [ ] **Step 6: Remove listener in `dispose`**

In the existing `dispose()`, add alongside `_sessionProvider?.removeListener(...)`:

```dart
    _knownHostsProvider?.removeListener(_onKnownHostsChanged);
```

- [ ] **Step 7: Add `_HostKeyDialog` and `_FpRow` to the file**

Append at the bottom of `app/lib/screens/main_screen.dart` (before the last `}`):

```dart
// ── Host Key Mismatch Dialog ──────────────────────────────

class _HostKeyDialog extends StatelessWidget {
  final HostKeyChallenge challenge;
  const _HostKeyDialog({required this.challenge});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          SizedBox(width: 8),
          Text('Host key changed',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${challenge.host}:${challenge.port}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          _FpRow(label: 'Old', fp: challenge.oldFingerprint),
          const SizedBox(height: 4),
          _FpRow(label: 'New', fp: challenge.newFingerprint),
          const SizedBox(height: 12),
          const Text(
            'This could indicate a man-in-the-middle attack. '
            'Only trust the new key if you know the server key changed.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.orange),
          child: const Text('Trust new key'),
        ),
      ],
    );
  }
}

class _FpRow extends StatelessWidget {
  final String label;
  final String fp;
  const _FpRow({required this.label, required this.fp});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Text('$label:',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ),
        Expanded(
          child: Text(fp,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontFamily: 'monospace')),
        ),
      ],
    );
  }
}
```

- [ ] **Step 8: Full analyze**

```bash
cd app && flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 9: Run all tests**

```bash
cd app && flutter test
```

Expected: `All tests passed.`

- [ ] **Step 10: Commit**

```bash
git add app/lib/screens/main_screen.dart
git commit -m "feat: wire KnownHostsScreen and host-key mismatch dialog in MainScreen"
```

---

## Self-Review Checklist

- [x] **Spec: TOFU** — Task 3 `verifyHostKey`: unknown host → save + return true ✓  
- [x] **Spec: matching key** — Task 3 `verifyHostKey`: same fingerprint → return true ✓  
- [x] **Spec: mismatch dialog** — Task 3 challenge bridge + Task 8 dialog ✓  
- [x] **Spec: trust updates entry** — Task 3 removes old, adds new on `resolve(true)` ✓  
- [x] **Spec: Known Hosts screen** — Task 7 list with delete ✓  
- [x] **Spec: storage** — Task 2 SharedPreferences JSON ✓  
- [x] **Spec: nav case** — Task 8 adds `NavSection.knownHosts => KnownHostsScreen()` ✓  
- [x] **Spec: wiring in main.dart** — Task 6 registers provider, wires `hostKeyVerifier` ✓  
- [x] **Type consistency** — `verifyHostKey(String, int, String, Uint8List)` matches across Tasks 3, 4, 5, 6 ✓  
- [x] **No placeholders** ✓
