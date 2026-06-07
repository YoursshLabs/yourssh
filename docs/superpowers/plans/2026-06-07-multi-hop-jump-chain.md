# Multi-hop Jump Chain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single `Host.jumpHostId` with an ordered hop list; dial the chain sequentially in `SshService`; let `HostChainEditor` append/remove hops.

**Architecture:** `Host` gains `List<String> jumpHostIds` (legacy `jumpHostId` kept as a first-hop getter and dual-written to JSON for cross-version sync). `SshService.connect` takes `List<JumpHop> jumpChain` and dials hop-by-hop — each hop's `forwardLocal` is the next hop's socket — caching clients by chain-prefix key and tearing them down deepest-first by refcount. The editor renders the full chain with a persistent Add button and per-hop remove.

**Tech Stack:** dartssh2 fork (`SSHClient.forwardLocal`, `SSHSocket.connect`), provider, existing fake-client test patterns.

**Spec:** `docs/superpowers/specs/2026-06-07-multi-hop-jump-chain-design.md`

---

## File map

| File | Change |
|---|---|
| `app/lib/models/host.dart` | `jumpHostIds` list + `jumpHostId` getter + dual JSON + copyWith |
| `app/lib/services/ssh_service.dart` | `JumpHop` typedef; `connect(jumpChain:)`; sequential dial; prefix-keyed cache; teardown; cycle guard; `ensureClient` resolves the list |
| `app/lib/providers/session_provider.dart` | `_doConnect` builds the chain, fails on unresolved hop |
| `app/lib/widgets/host_chain_editor.dart` | `chain` list, persistent Add, per-hop remove, `onChanged(List<String>)` |
| `app/lib/widgets/host_detail_panel.dart` | `_selectedJumpHostId` → `_jumpHostIds`; chain editor + `_test()` wiring |
| Tests | `host_test.dart` (migrate + add), `ssh_service_jump_auto_connect_test.dart` (migrate fake), `ssh_service_jump_chain_test.dart` (new), `session_provider_jump_test.dart` (new), `host_chain_editor_test.dart` (migrate), `host_detail_panel_chain_test.dart` (migrate) |
| `CLAUDE.md` | document the multi-hop chain |

Facts locked during exploration (`ssh_service.dart`): jump state is `_jumpClients`/`_jumpAgentProxies` keyed by jump id + `_hostToJump: Map<String,String>` (line 40-42); single-hop dial at 186-193; failed-connect teardown 233-239; `_ensureJumpClient` 248-289; `ensureClient` jump resolution 744-756; `disconnect` teardown 1011/1032-1036. Existing `_RecordingSshService` fake overrides `connect` with `jumpHost`/`jumpKeyEntry` (must migrate). `HostChainEditor` is presentational, `onSelect: ValueChanged<Host?>`; panel callsite at host_detail_panel.dart:404-438 builds `otherHosts` (excludes the edited host). `Host` is exported broadly; `copyWith` uses an `_Unset` sentinel for nullables.

All commands run from `app/`.

---

### Task 1: Host model — jumpHostIds list

**Files:**
- Modify: `app/lib/models/host.dart`
- Test: `app/test/models/host_test.dart` (migrate the 4 jump cases + add)

- [ ] **Step 1: Update the failing tests**

In `app/test/models/host_test.dart`, replace the four `jumpHostId` tests (lines ~52-86) with:

```dart
    test('jumpHostIds round-trips through JSON', () {
      final h = Host(
        label: 'Target',
        host: '10.0.0.5',
        username: 'admin',
        jumpHostIds: ['b1', 'b2'],
      );
      final decoded = Host.fromJson(h.toJson());
      expect(decoded.jumpHostIds, ['b1', 'b2']);
      expect(decoded.jumpHostId, 'b1'); // getter = first hop
    });

    test('toJson dual-writes jumpHostId (first hop) for old apps', () {
      final json =
          Host(label: 'x', host: 'y', username: 'z', jumpHostIds: ['b1', 'b2'])
              .toJson();
      expect(json['jumpHostIds'], ['b1', 'b2']);
      expect(json['jumpHostId'], 'b1');
    });

    test('legacy jumpHostId payload migrates to a one-element list', () {
      final decoded = Host.fromJson({
        'host': 'y',
        'username': 'z',
        'jumpHostId': 'old-bastion',
      });
      expect(decoded.jumpHostIds, ['old-bastion']);
    });

    test('jumpHostIds defaults to empty; jumpHostId getter null', () {
      final h = Host(label: 'x', host: 'y', username: 'z');
      expect(h.jumpHostIds, isEmpty);
      expect(h.jumpHostId, isNull);
      expect(Host.fromJson(h.toJson()).jumpHostIds, isEmpty);
    });

    test('malformed jumpHostIds degrades to empty', () {
      final decoded = Host.fromJson(
          {'host': 'y', 'username': 'z', 'jumpHostIds': 'garbage'});
      expect(decoded.jumpHostIds, isEmpty);
    });

    test('copyWith preserves jumpHostIds when not overridden', () {
      final h =
          Host(label: 'x', host: 'y', username: 'z', jumpHostIds: ['jid']);
      expect(h.copyWith(label: 'new').jumpHostIds, ['jid']);
    });

    test('copyWith clears jumpHostIds with an empty list', () {
      final h =
          Host(label: 'x', host: 'y', username: 'z', jumpHostIds: ['jid']);
      expect(h.copyWith(jumpHostIds: const []).jumpHostIds, isEmpty);
    });

    test('jumpHostIds is an owned growable copy', () {
      final h = Host(
          label: 'x', host: 'y', username: 'z', jumpHostIds: const ['a']);
      expect(() => h.jumpHostIds.add('b'), returnsNormally);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models/host_test.dart`
Expected: FAIL — `jumpHostIds` not defined.

- [ ] **Step 3: Implement**

In `host.dart`:

Field — replace `String? jumpHostId;` with:

```dart
  /// Ordered jump-host chain (bastion → … → target). Empty = direct.
  List<String> jumpHostIds;
```

Constructor — replace `this.jumpHostId,` with `Iterable<String> jumpHostIds = const [],`
and in the initializer list (next to `tags = List.of(tags)`):

```dart
        jumpHostIds = List.of(jumpHostIds),
```

Getter (after the constructor / `hasTemplateSetup`):

```dart
  /// First hop, for "has a bastion?" consumers and cross-version JSON.
  String? get jumpHostId => jumpHostIds.isEmpty ? null : jumpHostIds.first;
```

`toJson` — replace the `'jumpHostId': jumpHostId,` line with both:

```dart
        'jumpHostIds': jumpHostIds,
        // Dual-write the first hop so an older app reading a synced payload
        // keeps a working single-hop bastion instead of losing it.
        'jumpHostId': jumpHostId,
```

`fromJson` — add a local parser next to the others:

```dart
    List<String> parseJumpHostIds() {
      final raw = json['jumpHostIds'];
      if (raw is List) return raw.map((e) => e.toString()).toList();
      // Legacy single-hop payload.
      final legacy = json['jumpHostId'];
      return legacy is String && legacy.isNotEmpty ? [legacy] : const [];
    }
```

and in the returned `Host(...)` replace `jumpHostId: json['jumpHostId'] as String?,` with:

```dart
      jumpHostIds: parseJumpHostIds(),
```

`copyWith` — replace the `Object? jumpHostId = const _Unset(),` param with
`List<String>? jumpHostIds,` and the forwarding line with:

```dart
        jumpHostIds: jumpHostIds ?? this.jumpHostIds,
```

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/models/host_test.dart`
Expected: PASS. (Other files won't compile yet — that's fixed in later tasks.)

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/host.dart app/test/models/host_test.dart
git commit -m "feat: Host.jumpHostIds chain list (legacy jumpHostId migrates)"
```

---

### Task 2: SshService — sequential chain dial

**Files:**
- Modify: `app/lib/services/ssh_service.dart`
- Test: `app/test/services/ssh_service_jump_chain_test.dart` (new)

- [ ] **Step 1: Write the failing test**

Create `app/test/services/ssh_service_jump_chain_test.dart`:

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

/// Records forwardLocal targets and whether it was closed.
class _FakeClient implements SSHClient {
  _FakeClient(this.label, this._sockets);
  final String label;
  final List<String> _sockets; // shared dial-order log
  bool closed = false;

  @override
  Future<SSHSocket> forwardLocal(String host, int port,
      {String? localHost, int? localPort}) async {
    _sockets.add('$label->$host:$port');
    return _FakeSocket();
  }

  @override
  void close() => closed = true;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSocket implements SSHSocket {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Exposes the chain-dial internals without real auth: overrides the two
/// dial primitives so we can observe order + caching.
class _ProbeSshService extends SshService {
  _ProbeSshService(super.storage, this.dialLog);
  final List<String> dialLog;
  final List<_FakeClient> made = [];

  @override
  Future<SSHClient> debugDialHop(Host hop, SSHSocket? over,
      {SshKeyEntry? keyEntry,
      Future<bool> Function(String, Uint8List)? verifyHostKey}) async {
    dialLog.add(over == null
        ? 'connect ${hop.host}'
        : 'tunnel ${hop.host}');
    final c = _FakeClient(hop.host, dialLog);
    made.add(c);
    return c;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  Host h(String id, String host) =>
      Host(id: id, label: id, host: host, username: 'u');

  test('dialChain dials hop0 direct, each next over the previous', () async {
    final log = <String>[];
    final svc = _ProbeSshService(StorageService(), log);
    final client = await svc.debugDialChain(
      target: h('t', '10.0.0.9'),
      chain: [
        (host: h('a', '10.0.0.1'), keyEntry: null),
        (host: h('b', '10.0.0.2'), keyEntry: null),
      ],
      verifyHostKey: null,
    );
    expect(log, [
      'connect 10.0.0.1', // hop0 direct
      'a->10.0.0.2', //  hop1 over hop0
      'b->10.0.0.9', //  target over hop1
    ]);
    expect(client, isA<SSHClient>());
  });

  test('cycle guard: target id inside the chain throws', () async {
    final svc = _ProbeSshService(StorageService(), []);
    await expectLater(
      svc.debugDialChain(
        target: h('t', '10.0.0.9'),
        chain: [(host: h('t', '10.0.0.9'), keyEntry: null)],
        verifyHostKey: null,
      ),
      throwsArgumentError,
    );
  });

  test('cycle guard: duplicate hop ids throw', () async {
    final svc = _ProbeSshService(StorageService(), []);
    await expectLater(
      svc.debugDialChain(
        target: h('t', '10.0.0.9'),
        chain: [
          (host: h('a', '10.0.0.1'), keyEntry: null),
          (host: h('a', '10.0.0.1'), keyEntry: null),
        ],
        verifyHostKey: null,
      ),
      throwsArgumentError,
    );
  });

  test('prefix cache: two targets sharing hop0 reuse one hop0 client',
      () async {
    final log = <String>[];
    final svc = _ProbeSshService(StorageService(), log);
    final chain = [(host: h('a', '10.0.0.1'), keyEntry: null)];
    await svc.debugDialChain(
        target: h('t1', '10.0.0.8'), chain: chain, verifyHostKey: null);
    await svc.debugDialChain(
        target: h('t2', '10.0.0.9'), chain: chain, verifyHostKey: null);
    // hop0 'connect' happens once; both targets tunnel over it.
    expect(log.where((l) => l == 'connect 10.0.0.1').length, 1);
    expect(log.where((l) => l.startsWith('a->')).length, 2);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/ssh_service_jump_chain_test.dart`
Expected: FAIL — `debugDialChain`/`debugDialHop` not defined.

- [ ] **Step 3: Implement the chain dial**

In `ssh_service.dart`:

Add the typedef near the top (after imports):

```dart
/// One hop in a jump chain: the bastion host plus its resolved key.
typedef JumpHop = ({Host host, SshKeyEntry? keyEntry});
```

Re-key the jump state (line ~40-42):

```dart
  // Keyed by chain-prefix ('a' for hop0, 'a>b' for hop1 through a, …): a
  // client to B *through A* is distinct from a direct client to B.
  final Map<String, SSHClient> _jumpClients = {};
  final Map<String, SystemAgentProxy> _jumpAgentProxies = {};
  // target hostId → its chain-prefix keys (deepest last), for teardown.
  final Map<String, List<String>> _hostToJump = {};
```

Add the dial helpers (replace `_ensureJumpClient`, keep `_resolveIdentities`
usage). `debugDialHop`/`debugDialChain` are `@visibleForTesting` seams the
production path also calls:

```dart
  /// Opens one hop. [over] null = direct TCP (hop0); otherwise the socket
  /// is the previous client's forwardLocal channel. Test seam.
  @visibleForTesting
  Future<SSHClient> debugDialHop(
    Host hop,
    SSHSocket? over, {
    SshKeyEntry? keyEntry,
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    final password = await _storage.loadPassword(hop.id);
    final resolution =
        await _resolveIdentities(hop, keyEntry, jumpHostLabel: hop.label);
    if (resolution.agentProxy != null) {
      // Stored under the prefix key by the caller; park on host id for now.
      _jumpAgentProxies[hop.id] = resolution.agentProxy!;
    }
    final client = SSHClient(
      over ?? await SSHSocket.connect(hop.host, hop.port),
      username: hop.username,
      onPasswordRequest: () => password ?? '',
      identities:
          resolution.identities.isNotEmpty ? resolution.identities : null,
      onVerifyHostKey: (type, fp) async {
        if (verifyHostKey != null) return verifyHostKey(type.toString(), fp);
        return true;
      },
    );
    await client.authenticated;
    return client;
  }

  /// Dials [chain] sequentially and returns the LAST hop's client, ready to
  /// forwardLocal to [target]. Caches each hop by its chain-prefix key.
  /// Test seam; production connect() uses it. Returns null chain → throws
  /// (callers guard); callers open the target socket via the returned
  /// client's forwardLocal.
  @visibleForTesting
  Future<SSHClient> debugDialChain({
    required Host target,
    required List<JumpHop> chain,
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    // Cycle guard — the picker prevents this, but sync/import may not.
    final seen = <String>{};
    for (final hop in chain) {
      if (hop.host.id == target.id) {
        throw ArgumentError('Jump chain contains the target host: ${hop.host.id}');
      }
      if (!seen.add(hop.host.id)) {
        throw ArgumentError('Jump chain has a duplicate hop: ${hop.host.id}');
      }
    }

    final keys = <String>[];
    SSHClient? prev;
    for (var i = 0; i < chain.length; i++) {
      final hop = chain[i];
      final prefix = chain.take(i + 1).map((h) => h.host.id).join('>');
      keys.add(prefix);
      final cached = _jumpClients[prefix];
      if (cached != null) {
        prev = cached;
        continue;
      }
      final socket = prev == null
          ? null
          : await prev.forwardLocal(hop.host.host, hop.host.port);
      final client = await debugDialHop(hop.host, socket,
          keyEntry: hop.keyEntry, verifyHostKey: verifyHostKey);
      _jumpClients[prefix] = client;
      prev = client;
    }
    _hostToJump[target.id] = keys;
    return prev!;
  }
```

Rewrite `connect`'s signature + jump section. Replace the
`jumpHost`/`jumpKeyEntry` params with `List<JumpHop> jumpChain = const []`,
and the socket block (lines 185-196) with:

```dart
      final SSHSocket socket;
      if (jumpChain.isNotEmpty) {
        final lastHop =
            await debugDialChain(target: host, chain: jumpChain, verifyHostKey: verifyHostKey);
        socket = await lastHop.forwardLocal(host.host, host.port);
      } else {
        socket = await SSHSocket.connect(host.host, host.port);
      }
```

Replace the failed-connect jump teardown (lines 233-239) with a call to a
shared helper:

```dart
      _teardownJumpChain(host.id);
```

Add the teardown helper (deepest-first, refcounted) and call it from
`disconnect` too (replacing lines 1032-1036, and remove the now-unused
`final jumpHostId = _hostToJump.remove(hostId);` single-id logic at 1011 in
favor of this helper):

```dart
  /// Releases a host's jump-chain prefix clients, deepest-first, closing a
  /// prefix only when no other host still references it.
  void _teardownJumpChain(String hostId) {
    final keys = _hostToJump.remove(hostId);
    if (keys == null) return;
    for (final prefix in keys.reversed) {
      final stillUsed = _hostToJump.values.any((ks) => ks.contains(prefix));
      if (stillUsed) continue;
      _jumpClients.remove(prefix)?.close();
      // Agent proxies are parked on the deepest hop id (last segment).
      final hopId = prefix.split('>').last;
      unawaited(_jumpAgentProxies.remove(hopId)?.close() ?? Future.value());
    }
  }
```

In `disconnect`, replace the old `if (jumpHostId != null && …)` block
(1032-1036) and the line-1011 `_hostToJump.remove` with a single
`_teardownJumpChain(hostId);` at the end (keep the rest of disconnect
intact). Add `import 'package:flutter/foundation.dart' show visibleForTesting;`
if not already importing it.

Rewrite `ensureClient`'s jump resolution (lines 742-756):

```dart
    final chain = <JumpHop>[];
    for (final jid in host.jumpHostIds) {
      final jh = defaultJumpHostLookup?.call(jid);
      if (jh == null) {
        throw StateError('Jump host not found: $jid');
      }
      final jk = jh.keyId == null ? null : defaultKeyLookup?.call(jh.keyId!);
      chain.add((host: jh, keyEntry: jk));
    }
    return connect(
      host,
      keyEntry: keyEntry,
      jumpChain: chain,
      verifyHostKey: (keyType, fp) => verifier(host.host, host.port, keyType, fp),
    );
```

Delete the old `_ensureJumpClient` method (its logic now lives in
`debugDialHop`/`debugDialChain`).

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/services/ssh_service_jump_chain_test.dart && flutter test test/services/ssh_service_open_shell_test.dart`
Expected: chain tests PASS; open-shell tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/ssh_service.dart app/test/services/ssh_service_jump_chain_test.dart
git commit -m "feat: SshService dials multi-hop jump chains with prefix-keyed cache"
```

---

### Task 3: Migrate the existing jump auto-connect test + SessionProvider

**Files:**
- Modify: `app/test/services/ssh_service_jump_auto_connect_test.dart`
- Modify: `app/lib/providers/session_provider.dart` (`_doConnect` ~135-151)
- Test: `app/test/providers/session_provider_jump_test.dart` (new)

- [ ] **Step 1: Migrate the auto-connect fake to jumpChain**

In `ssh_service_jump_auto_connect_test.dart`, change the fake's override
and assertions:

```dart
class _RecordingSshService extends SshService {
  _RecordingSshService(super.storage);

  List<JumpHop> capturedChain = const [];

  @override
  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    List<JumpHop> jumpChain = const [],
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    capturedChain = jumpChain;
    throw _Sentinel();
  }
}
```

Update the two tests' host construction (`jumpHostId: 'jump-id'` →
`jumpHostIds: ['jump-id']`) and assertions:

```dart
    await expectLater(svc.ensureClient(target), throwsA(isA<_Sentinel>()));
    expect(svc.capturedChain.single.host.id, 'jump-id');
    expect(svc.capturedChain.single.keyEntry?.id, 'k1');
```

For the direct-host test: `expect(svc.capturedChain, isEmpty);` and drop
the `fail('must not be called')` lookup (ensureClient now iterates an empty
list, never calling the lookup). Add `import` for `JumpHop` is unneeded —
it's exported from `ssh_service.dart` already imported.

- [ ] **Step 2: Run it (fails until SessionProvider compiles)**

Run: `cd app && flutter test test/services/ssh_service_jump_auto_connect_test.dart`
Expected: FAIL to compile until SessionProvider is migrated (Step 3) — they
share the `connect` signature.

- [ ] **Step 3: Write the SessionProvider failing test**

Create `app/test/providers/session_provider_jump_test.dart`:

```dart
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

class _CapturingSsh extends SshService {
  _CapturingSsh() : super(StorageService());
  List<JumpHop>? capturedChain;

  @override
  Future<SSHClient> connect(
    Host host, {
    SshKeyEntry? keyEntry,
    List<JumpHop> jumpChain = const [],
    Future<bool> Function(String keyType, Uint8List fingerprint)? verifyHostKey,
  }) async {
    capturedChain = jumpChain;
    throw Exception('stop-before-shell');
  }
}

Host _bastion(String id) =>
    Host(id: id, label: id, host: '$id.com', username: 'u', detectedOs: 'ubuntu');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('_doConnect resolves the full chain in order', () async {
    final ssh = _CapturingSsh();
    final p = SessionProvider(ssh, TabMetadataService());
    final a = _bastion('a'), b = _bastion('b');
    p.jumpHostLookup = (id) => {'a': a, 'b': b}[id];

    await p.connect(Host(
        label: 't',
        host: 't.com',
        username: 'u',
        detectedOs: 'ubuntu',
        jumpHostIds: ['a', 'b']));

    expect(ssh.capturedChain?.map((h) => h.host.id), ['a', 'b']);
    p.dispose();
  });

  test('an unresolved hop fails the connect (no silent skip)', () async {
    final ssh = _CapturingSsh();
    final p = SessionProvider(ssh, TabMetadataService());
    p.jumpHostLookup = (_) => null; // hop missing

    await p.connect(Host(
        label: 't',
        host: 't.com',
        username: 'u',
        detectedOs: 'ubuntu',
        jumpHostIds: ['gone']));

    // connect never reached: chain resolution threw first.
    expect(ssh.capturedChain, isNull);
    expect(p.sshSessions.single.status, SessionStatus.error);
    p.dispose();
  });
}
```

- [ ] **Step 4: Implement in SessionProvider**

Replace the jump block in `_doConnect` (lines ~134-151):

```dart
      final keyEntry = host.keyId != null ? keyLookup?.call(host.keyId!) : null;
      final jumpChain = <JumpHop>[];
      for (final jid in host.jumpHostIds) {
        final jh = jumpHostLookup?.call(jid);
        if (jh == null) {
          throw StateError('Jump host not found: $jid');
        }
        final jk = jh.keyId == null ? null : keyLookup?.call(jh.keyId!);
        jumpChain.add((host: jh, keyEntry: jk));
      }
      await _ssh.connect(
        host,
        keyEntry: keyEntry,
        jumpChain: jumpChain,
        verifyHostKey: hostKeyVerifier != null
            ? (keyType, fp) => hostKeyVerifier!(host.host, host.port, keyType, fp)
            : null,
      );
```

Add `import '../services/ssh_service.dart';` already present — `JumpHop` is
exported from it.

- [ ] **Step 5: Run tests**

Run: `cd app && flutter test test/providers/session_provider_jump_test.dart test/services/ssh_service_jump_auto_connect_test.dart test/providers/session_provider_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/lib/providers/session_provider.dart app/test/providers/session_provider_jump_test.dart app/test/services/ssh_service_jump_auto_connect_test.dart
git commit -m "feat: SessionProvider builds the jump chain, fails on missing hop"
```

---

### Task 4: HostChainEditor — append/remove hops

**Files:**
- Modify: `app/lib/widgets/host_chain_editor.dart`
- Test: `app/test/widgets/host_chain_editor_test.dart` (migrate + add)

- [ ] **Step 1: Migrate + extend the widget test**

Rewrite `app/test/widgets/host_chain_editor_test.dart` to the new API
(`chain` + `onChanged`). Keep the `wrap`/`makeHost` helpers; replace the
body:

```dart
  testWidgets('empty chain shows Add a Host', (tester) async {
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'target',
      chain: const [],
      candidates: [makeHost('h1', 'bastion')],
      onChanged: (_) {},
    )));
    expect(find.text('Add a Host'), findsOneWidget);
    expect(find.text('Clear'), findsNothing);
  });

  testWidgets('chain shows hops, Add stays visible, Clear present',
      (tester) async {
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'target',
      chain: [makeHost('h1', 'bastion')],
      candidates: [makeHost('h1', 'bastion'), makeHost('h2', 'b2')],
      onChanged: (_) {},
    )));
    expect(find.text('bastion'), findsOneWidget);
    expect(find.text('Add a Host'), findsOneWidget); // append more
    expect(find.text('Clear'), findsOneWidget);
  });

  testWidgets('appending a hop calls onChanged with both ids',
      (tester) async {
    List<String>? got;
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'target',
      chain: [makeHost('h1', 'bastion')],
      candidates: [makeHost('h1', 'bastion'), makeHost('h2', 'b2')],
      onChanged: (ids) => got = ids,
    )));
    await tester.tap(find.text('Add a Host'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('b2').last);
    await tester.pumpAndSettle();
    expect(got, ['h1', 'h2']);
  });

  testWidgets('candidates exclude hosts already in the chain',
      (tester) async {
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'target',
      chain: [makeHost('h1', 'bastion')],
      candidates: [makeHost('h1', 'bastion'), makeHost('h2', 'b2')],
      onChanged: (_) {},
    )));
    await tester.tap(find.text('Add a Host'));
    await tester.pumpAndSettle();
    // h1 is already a hop → only h2 offered in the picker.
    expect(find.text('b2'), findsWidgets);
    expect(
        find.descendant(
            of: find.byType(Dialog), matching: find.text('bastion')),
        findsNothing);
  });

  testWidgets('Clear empties the chain', (tester) async {
    List<String>? got;
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'target',
      chain: [makeHost('h1', 'bastion')],
      candidates: [makeHost('h1', 'bastion')],
      onChanged: (ids) => got = ids,
    )));
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(got, isEmpty);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/host_chain_editor_test.dart`
Expected: FAIL — `chain`/`onChanged` not defined.

- [ ] **Step 3: Implement the editor**

Rewrite `host_chain_editor.dart`'s API and chain rendering. Replace the
props block:

```dart
  final String currentHostLabel;
  final String? currentHostOs;

  /// Ordered jump chain (bastion → … ); empty = direct.
  final List<Host> chain;

  /// Shows the key glyph on the LAST hop when agent forwarding is on
  /// (forwarding terminates at the destination, served via the final hop).
  final bool agentForwarding;

  /// Hosts selectable as a hop (caller excludes the edited host).
  final List<Host> candidates;

  /// Fires the full ordered id list after any add/remove/clear.
  final ValueChanged<List<String>> onChanged;

  const HostChainEditor({
    super.key,
    required this.currentHostLabel,
    this.currentHostOs,
    this.chain = const [],
    this.agentForwarding = false,
    required this.candidates,
    required this.onChanged,
  });

  Future<void> _addHop(BuildContext context) async {
    final chosenIds = chain.map((h) => h.id).toSet();
    final pickable =
        candidates.where((h) => !chosenIds.contains(h.id)).toList();
    final picked = await showDialog<Host>(
      context: context,
      builder: (_) => _HostPickerDialog(candidates: pickable),
    );
    if (picked != null) onChanged([...chain.map((h) => h.id), picked.id]);
  }

  void _removeAt(int i) {
    final ids = chain.map((h) => h.id).toList()..removeAt(i);
    onChanged(ids);
  }

  @override
  Widget build(BuildContext context) {
    return chain.isEmpty ? _emptyState(context) : _chainView(context);
  }
```

Keep `_emptyState` but point its button at `_addHop`. Replace `_chain`
with `_chainView` that renders each hop with a remove button, an arrow
between rows, the destination card, then a persistent **Add a Host** row
and a **Clear** row:

```dart
  Widget _chainView(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < chain.length; i++) {
      final hop = chain[i];
      if (i > 0) rows.add(_arrow());
      rows.add(_HostCard(
        label: hop.label.isNotEmpty ? hop.label : '${hop.username}@${hop.host}',
        detectedOs: hop.detectedOs,
        trailing: (agentForwarding && i == chain.length - 1)
            ? const Tooltip(
                message:
                    'Agent forwarding on — the destination uses your local keys',
                child: Icon(Icons.key, size: 14, color: AppColors.accent))
            : _RemoveButton(onTap: () => _removeAt(i)),
      ));
    }
    rows.add(_arrow());
    rows.add(_HostCard(label: currentHostLabel, detectedOs: currentHostOs));
    rows.add(const SizedBox(height: 10));
    rows.add(_actionButton(
        label: 'Add a Host',
        color: AppColors.textPrimary,
        bg: AppColors.cardHover,
        onTap: () => _addHop(context)));
    rows.add(const SizedBox(height: 6));
    rows.add(_actionButton(
        label: 'Clear',
        color: AppColors.red,
        bg: AppColors.red.withValues(alpha: 0.12),
        onTap: () => onChanged(const [])));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  Widget _arrow() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Icon(Icons.arrow_downward, size: 16, color: AppColors.textTertiary),
      );

  Widget _actionButton(
      {required String label,
      required Color color,
      required Color bg,
      required VoidCallback onTap}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 32,
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
```

In `_emptyState`, change the button `onTap: () => _pick(context)` →
`onTap: () => _addHop(context)` and remove the now-unused `_pick` method.
Add a small `_RemoveButton` widget:

```dart
class _RemoveButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RemoveButton({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: const Tooltip(
          message: 'Remove hop',
          child: Icon(Icons.close, size: 14, color: AppColors.textTertiary),
        ),
      );
}
```

Update the doc comment (single-hop → ordered chain; `onChanged`).

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/widgets/host_chain_editor_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/host_chain_editor.dart app/test/widgets/host_chain_editor_test.dart
git commit -m "feat: HostChainEditor appends/removes multi-hop chain"
```

---

### Task 5: HostDetailPanel — chain list state

**Files:**
- Modify: `app/lib/widgets/host_detail_panel.dart`
- Test: `app/test/widgets/host_detail_panel_chain_test.dart` (migrate)

- [ ] **Step 1: Migrate the panel chain test**

In `host_detail_panel_chain_test.dart`, update assertions to the list field
(saved `Host.jumpHostIds` instead of `jumpHostId`). Read the file first;
change each `saved.jumpHostId` expectation to `saved!.jumpHostIds` and any
`jumpHostId: 'x'` existing-host construction to `jumpHostIds: ['x']`. If a
test selects a jump host and asserts it saved, assert
`saved!.jumpHostIds, ['picked-id']`.

- [ ] **Step 2: Run it to verify it fails**

Run: `cd app && flutter test test/widgets/host_detail_panel_chain_test.dart`
Expected: FAIL — panel still writes `jumpHostId`.

- [ ] **Step 3: Implement the panel changes**

In `host_detail_panel.dart`:

- State field: replace `String? _selectedJumpHostId;` with
  `List<String> _jumpHostIds = [];`
- initState (line ~104): `_jumpHostIds = List.of(h?.jumpHostIds ?? const []);`
- Both `Host(...)` constructions (`_save` ~175, `_test` ~236): replace
  `jumpHostId: _selectedJumpHostId,` with `jumpHostIds: _jumpHostIds,`
- Chain editor callsite (404-438): resolve the chain from ids, drop stale
  ids, and pass the list:

```dart
                    final chainHosts = _jumpHostIds
                        .map((id) =>
                            otherHosts.where((h) => h.id == id).firstOrNull)
                        .whereType<Host>()
                        .toList();
                    // Prune ids that no longer resolve (host deleted).
                    if (chainHosts.length != _jumpHostIds.length) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() => _jumpHostIds =
                              chainHosts.map((h) => h.id).toList());
                        }
                      });
                    }
                    return ListenableBuilder(
                      listenable: Listenable.merge(
                          [_labelCtrl, _usernameCtrl, _hostCtrl]),
                      builder: (context, _) => HostChainEditor(
                        currentHostLabel: _currentHostLabel(),
                        currentHostOs: widget.existing?.detectedOs,
                        chain: chainHosts,
                        agentForwarding: _agentForwarding,
                        candidates: otherHosts,
                        onChanged: (ids) =>
                            setState(() => _jumpHostIds = ids),
                      ),
                    );
```

- [ ] **Step 4: Run tests**

Run: `cd app && flutter test test/widgets/host_detail_panel_chain_test.dart test/widgets/host_detail_panel_agent_forwarding_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/host_detail_panel.dart app/test/widgets/host_detail_panel_chain_test.dart
git commit -m "feat: host panel edits a multi-hop jump chain"
```

---

### Task 6: Full verification + docs

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Full sweep for stragglers**

Run: `cd app && grep -rn "jumpHostId\b" lib/ test/ | grep -v "jumpHostIds\|jumpHostId =>\|// "`
Expected: only the getter definition and intentional first-hop reads remain
(e.g. workspace save, sync payload strip). Fix any writer still using the
old scalar (assign a list instead). Check `add_host_dialog_edit_preserve_test.dart`
references — update `jumpHostId: 'x'` → `jumpHostIds: ['x']` if present.

- [ ] **Step 2: Full analyze + test**

Run: `cd app && flutter analyze && flutter test`
Expected: 0 issues, all tests pass.

- [ ] **Step 3: Update CLAUDE.md**

- `Host` model bullet: replace the `jumpHostId` mention with
  "`jumpHostIds` ordered jump chain (bastion → … → target; legacy
  `jumpHostId` migrates and is dual-written to JSON for cross-version
  sync; `jumpHostId` getter = first hop)".
- `SshService` bullet: note "multi-hop jump chains — `connect(jumpChain:)`
  dials each hop over the previous hop's `forwardLocal`, caches clients by
  chain-prefix key, tears down deepest-first by refcount; cycle-guarded".
- `HostChainEditor` bullet: "Termius-style multi-hop chain (append/remove
  per hop, `onChanged(List<String>)`)".
- Update the roadmap line in P0 if desired (leave to `/yourssh-roadmap`).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: multi-hop jump chain in CLAUDE.md"
```

---

## Self-review notes (already applied)

- **Spec coverage:** model list + dual JSON + migration (T1), sequential
  dial + prefix cache + teardown + cycle guard (T2), ensureClient +
  SessionProvider chain build + fail-on-missing (T2/T3), editor
  append/remove/clear + candidate exclusion (T4), panel list state +
  stale-id prune (T5), docs (T6).
- **Type consistency:** `JumpHop = ({Host host, SshKeyEntry? keyEntry})`
  (T2) used in T3 fakes and SessionProvider; `onChanged(List<String>)`
  (T4) consumed by the panel (T5); `_teardownJumpChain` shared by
  failed-connect and disconnect (T2).
- **Known risks:** `debugDialHop`/`debugDialChain` are `@visibleForTesting`
  seams the production path calls — agent-proxy parking by hop id is a
  simplification (single agent proxy per hop id across prefixes); acceptable
  since a hop reached via two prefixes is rare and the proxy is idempotent
  to close. The fake `_FakeClient`/`_FakeSocket` only implement
  `forwardLocal`/`close`; if `debugDialHop`'s real `SSHClient(...)` can't be
  bypassed in `debugDialChain` for the cache/order tests, the test overrides
  `debugDialHop` (it does) so no real socket is opened.
