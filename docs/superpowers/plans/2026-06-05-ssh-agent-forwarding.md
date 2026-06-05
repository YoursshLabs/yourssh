# SSH Agent Forwarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-host SSH Agent Forwarding (issue #49) — forwarded `auth-agent@openssh.com` channels are served by the local system agent, falling back to app-Keychain keys.

**Architecture:** The `dartssh2` fork already sends `auth-agent-req@openssh.com` and accepts server-opened agent channels when `SSHClient.agentHandler` is set. We add a new `AgentForwardingHandler` (app layer) that relays each request verbatim over a fresh `SystemAgentProxy` connection, falling back to dartssh2's `SSHKeyPairAgent` built from Keychain keys. A new `Host.agentForwarding` bool (default false) gates the handler in `SshService.connect()`; a `SwitchListTile` in `HostDetailPanel` exposes it. One fork fix: a server refusing the forwarding request must not kill the session.

**Spec:** `docs/superpowers/specs/2026-06-05-ssh-agent-forwarding-design.md`

**Tech Stack:** Flutter/Dart, local `dartssh2` fork, `flutter_test`.

**Conventions:**
- All test commands run from `app/` (`cd app && flutter test …`) except the fork's (`cd packages/dartssh2 && dart test …`).
- Agent-socket tests use the fake Unix-socket agent pattern from `app/test/services/system_agent_proxy_test.dart` and are skipped on Windows.

---

### Task 1: `Host.agentForwarding` model field

**Files:**
- Test: `app/test/models/host_agent_forwarding_test.dart` (create)
- Modify: `app/lib/models/host.dart`

- [ ] **Step 1: Write the failing test**

Create `app/test/models/host_agent_forwarding_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

void main() {
  Host base() => Host(label: 'srv', host: '1.2.3.4', username: 'u');

  group('Host.agentForwarding', () {
    test('defaults to false', () {
      expect(base().agentForwarding, isFalse);
    });

    test('round-trips through JSON', () {
      final host = Host(
        label: 'srv',
        host: '1.2.3.4',
        username: 'u',
        agentForwarding: true,
      );
      final restored = Host.fromJson(host.toJson());
      expect(restored.agentForwarding, isTrue);
    });

    test('absent JSON key parses as false (backward compat)', () {
      final json = base().toJson()..remove('agentForwarding');
      final restored = Host.fromJson(json);
      expect(restored.agentForwarding, isFalse);
    });

    test('copyWith toggles and preserves', () {
      final on = base().copyWith(agentForwarding: true);
      expect(on.agentForwarding, isTrue);
      // Unrelated copyWith leaves it untouched.
      expect(on.copyWith(label: 'x').agentForwarding, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/models/host_agent_forwarding_test.dart`
Expected: FAIL — `No named parameter with the name 'agentForwarding'` (compile error).

- [ ] **Step 3: Implement the field**

In `app/lib/models/host.dart`, make four edits following the `shellIntegration` pattern:

Field declaration (after `bool shellIntegration;`, line 25):

```dart
  bool shellIntegration;
  bool agentForwarding;
```

Constructor (after `this.shellIntegration = true,`):

```dart
    this.shellIntegration = true,
    this.agentForwarding = false,
```

`toJson()` (after `'shellIntegration': shellIntegration,`):

```dart
        'shellIntegration': shellIntegration,
        'agentForwarding': agentForwarding,
```

`fromJson()` (after the `shellIntegration:` line):

```dart
      shellIntegration: (json['shellIntegration'] as bool?) ?? true,
      agentForwarding: (json['agentForwarding'] as bool?) ?? false,
```

`copyWith()` — parameter (after `bool? shellIntegration,`) and body (after the `shellIntegration:` line):

```dart
    bool? shellIntegration,
    bool? agentForwarding,
```

```dart
        shellIntegration: shellIntegration ?? this.shellIntegration,
        agentForwarding: agentForwarding ?? this.agentForwarding,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/models/host_agent_forwarding_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Run the other host model tests (serialization didn't break)**

Run: `cd app && flutter test test/models/host_test.dart test/models/host_sftp_mode_test.dart test/models/host_detected_os_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/lib/models/host.dart app/test/models/host_agent_forwarding_test.dart
git commit -m "feat(model): Host.agentForwarding flag (issue #49)"
```

---

### Task 2: `SystemAgentProxy.roundtrip`

**Files:**
- Test: `app/test/services/system_agent_proxy_test.dart` (modify — add one test)
- Modify: `app/lib/services/system_agent_proxy.dart`

- [ ] **Step 1: Write the failing test**

Add inside the existing `group('SystemAgentProxy', …)` in
`app/test/services/system_agent_proxy_test.dart` (after the `signAsync` test):

```dart
    test('roundtrip frames the request and unframes the response', () async {
      // Fake agent: expect framed [11] (REQUEST_IDENTITIES), reply with an
      // empty IDENTITIES_ANSWER (type 12, count 0).
      final received = <int>[];
      unawaited(server.first.then((client) {
        client.listen((data) {
          received.addAll(data);
          final nkeys = Uint8List(4); // count = 0
          client.add(_agentMsg([12, ...nkeys]));
        });
      }));

      final proxy = await SystemAgentProxy.connectTo(socketPath);
      final response = await proxy.roundtrip(Uint8List.fromList([11]));

      // Request on the wire: 4-byte length prefix + body.
      expect(received, equals([0, 0, 0, 1, 11]));
      // Response comes back unframed: type byte + uint32 count.
      expect(response, equals([12, 0, 0, 0, 0]));

      await proxy.close();
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/services/system_agent_proxy_test.dart`
Expected: FAIL — `The method 'roundtrip' isn't defined for the type 'SystemAgentProxy'`.

- [ ] **Step 3: Implement `roundtrip`**

In `app/lib/services/system_agent_proxy.dart`, add to the `SystemAgentProxy`
class (between `getIdentities()` and `close()`):

```dart
  /// Sends one raw (unframed) agent-protocol request and returns the raw
  /// (unframed) response body. Length-prefix framing is handled internally.
  /// Used by AgentForwardingHandler to relay forwarded agent requests
  /// verbatim — the payload is never parsed, so agent extensions work.
  Future<Uint8List> roundtrip(Uint8List requestBody) async {
    final header = Uint8List(4);
    ByteData.view(header.buffer).setUint32(0, requestBody.length, Endian.big);
    _session.write(Uint8List.fromList([...header, ...requestBody]));
    return _session.readMessage();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/services/system_agent_proxy_test.dart`
Expected: PASS (5 tests; suite is skipped wholesale on Windows — unchanged).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/system_agent_proxy.dart app/test/services/system_agent_proxy_test.dart
git commit -m "feat(agent): SystemAgentProxy.roundtrip raw passthrough"
```

---

### Task 3: `AgentForwardingHandler`

**Files:**
- Create: `app/lib/services/agent_forwarding_handler.dart`
- Test: `app/test/services/agent_forwarding_handler_test.dart` (create)

- [ ] **Step 1: Write the failing tests**

Create `app/test/services/agent_forwarding_handler_test.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/agent_forwarding_handler.dart';
import 'package:yourssh/services/system_agent_proxy.dart';

Uint8List _agentMsg(List<int> body) {
  final header = Uint8List(4);
  ByteData.view(header.buffer).setUint32(0, body.length, Endian.big);
  return Uint8List.fromList([...header, ...body]);
}

void main() {
  group('AgentForwardingHandler', () {
    late ServerSocket server;
    late String socketPath;

    setUp(() async {
      socketPath =
          '/tmp/yourssh_fwd_test_${DateTime.now().microsecondsSinceEpoch}.sock';
      server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      // Fake system agent: answer every request on every connection with an
      // empty IDENTITIES_ANSWER (type 12, count 0).
      server.listen((client) {
        client.listen((_) {
          client.add(_agentMsg([12, 0, 0, 0, 0]));
        });
      });
    });

    tearDown(() async {
      await server.close();
      final f = File(socketPath);
      if (await f.exists()) await f.delete();
    });

    test('relays request to the system agent and returns its response',
        () async {
      var loaderCalls = 0;
      final handler = AgentForwardingHandler(
        connectSystemAgent: () => SystemAgentProxy.connectTo(socketPath),
        loadKeychainIdentities: () async {
          loaderCalls++;
          return const <SSHKeyPair>[];
        },
      );

      final response =
          await handler.handleRequest(Uint8List.fromList([11]));
      expect(response, equals([12, 0, 0, 0, 0]));
      // System agent answered — Keychain fallback never touched.
      expect(loaderCalls, 0);
    });

    test('falls back to Keychain agent when system agent is unavailable, '
        'and caches the fallback across requests', () async {
      var loaderCalls = 0;
      final handler = AgentForwardingHandler(
        connectSystemAgent: () async =>
            throw const SSHAgentUnavailableException('none'),
        loadKeychainIdentities: () async {
          loaderCalls++;
          return const <SSHKeyPair>[];
        },
      );

      // SSHKeyPairAgent with zero keys answers REQUEST_IDENTITIES (11)
      // with IDENTITIES_ANSWER (12) and count 0.
      final r1 = await handler.handleRequest(Uint8List.fromList([11]));
      expect(r1[0], SSHAgentProtocol.identitiesAnswer);
      final r2 = await handler.handleRequest(Uint8List.fromList([11]));
      expect(r2[0], SSHAgentProtocol.identitiesAnswer);
      // Built once, reused.
      expect(loaderCalls, 1);
    });

    test('retries the system agent on each request (recovers mid-session)',
        () async {
      var attempt = 0;
      final handler = AgentForwardingHandler(
        connectSystemAgent: () {
          attempt++;
          if (attempt == 1) {
            throw const SSHAgentUnavailableException('not yet');
          }
          return SystemAgentProxy.connectTo(socketPath);
        },
        loadKeychainIdentities: () async => const <SSHKeyPair>[],
      );

      await handler.handleRequest(Uint8List.fromList([11])); // fallback
      final response =
          await handler.handleRequest(Uint8List.fromList([11]));
      // Second request reached the fake system agent (raw relay shape).
      expect(response, equals([12, 0, 0, 0, 0]));
      expect(attempt, 2);
    });

    test('propagates failures that happen after connect succeeded', () async {
      // Agent accepts the connection then dies before replying.
      await server.close();
      server = await ServerSocket.bind(
        InternetAddress('$socketPath.dead', type: InternetAddressType.unix),
        0,
      );
      server.listen((client) {
        client.destroy(); // connect OK, then immediate close
      });

      var loaderCalls = 0;
      final handler = AgentForwardingHandler(
        connectSystemAgent: () =>
            SystemAgentProxy.connectTo('$socketPath.dead'),
        loadKeychainIdentities: () async {
          loaderCalls++;
          return const <SSHKeyPair>[];
        },
      );

      await expectLater(
        handler.handleRequest(Uint8List.fromList([11])),
        throwsA(isA<SSHAgentUnavailableException>()),
      );
      // Post-connect failure must NOT switch key sources mid-request.
      expect(loaderCalls, 0);

      final f = File('$socketPath.dead');
      if (await f.exists()) await f.delete();
    });
  },
      // Fake agent binds a Unix domain socket — unavailable on Windows CI.
      skip: Platform.isWindows
          ? 'Unix domain sockets unavailable on Windows'
          : false);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/services/agent_forwarding_handler_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:yourssh/services/agent_forwarding_handler.dart'`.

- [ ] **Step 3: Implement the handler**

Create `app/lib/services/agent_forwarding_handler.dart`:

```dart
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'system_agent_proxy.dart';

/// Serves forwarded `auth-agent@openssh.com` channels (issue #49).
///
/// Primary path: relay each agent request verbatim over a fresh
/// [SystemAgentProxy] connection (the agent protocol is strictly serial per
/// connection, so connection-per-request sidesteps interleaving between
/// concurrent forwarded channels and stale sockets after agent restarts —
/// the same model `ssh-add` uses).
///
/// Fallback: when no system agent is reachable, app-Keychain keys are served
/// through dartssh2's [SSHKeyPairAgent], built lazily on first use and cached
/// for the lifetime of this handler (one SSH connection). The fallback only
/// triggers on connect failure — a request that fails *after* connecting
/// propagates instead, so we never switch key sources mid-request.
class AgentForwardingHandler implements SSHAgentHandler {
  AgentForwardingHandler({
    Future<SystemAgentProxy> Function() connectSystemAgent =
        SystemAgentProxy.connect,
    required Future<List<SSHKeyPair>> Function() loadKeychainIdentities,
  })  : _connectSystemAgent = connectSystemAgent,
        _loadKeychainIdentities = loadKeychainIdentities;

  final Future<SystemAgentProxy> Function() _connectSystemAgent;
  final Future<List<SSHKeyPair>> Function() _loadKeychainIdentities;

  SSHKeyPairAgent? _fallback;

  @override
  Future<Uint8List> handleRequest(Uint8List request) async {
    final SystemAgentProxy proxy;
    try {
      proxy = await _connectSystemAgent();
    } on SSHAgentUnavailableException {
      final fallback =
          _fallback ??= SSHKeyPairAgent(await _loadKeychainIdentities());
      return fallback.handleRequest(request);
    }
    try {
      return await proxy.roundtrip(request);
    } finally {
      await proxy.close();
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/services/agent_forwarding_handler_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/agent_forwarding_handler.dart app/test/services/agent_forwarding_handler_test.dart
git commit -m "feat(agent): AgentForwardingHandler — system agent relay with Keychain fallback"
```

---

### Task 4: Keychain identity loader + test key fixtures

**Files:**
- Modify: `app/lib/services/agent_forwarding_handler.dart` (add top-level function)
- Test: `app/test/services/agent_forwarding_handler_test.dart` (add group)
- Create: `app/test/fixtures/keys/id_ed25519` and `app/test/fixtures/keys/id_ed25519_enc` (test-only throwaway keys, generated below)

- [ ] **Step 1: Generate throwaway fixture keys**

These are test-only keys, never used anywhere real — same precedent as
`packages/dartssh2/test/fixtures/ssh-rsa/id_rsa`.

```bash
mkdir -p app/test/fixtures/keys
ssh-keygen -t ed25519 -f app/test/fixtures/keys/id_ed25519 -N '' -C 'yourssh-test-fixture' -q
ssh-keygen -t ed25519 -f app/test/fixtures/keys/id_ed25519_enc -N 'test-passphrase' -C 'yourssh-test-fixture-enc' -q
rm app/test/fixtures/keys/id_ed25519.pub app/test/fixtures/keys/id_ed25519_enc.pub
```

- [ ] **Step 2: Write the failing tests**

Append a second top-level group to
`app/test/services/agent_forwarding_handler_test.dart` (inside `main()`, after
the `AgentForwardingHandler` group; it has no socket dependency so it lives
outside the Windows skip — pass the same `skip:` only on the *first* group,
which is already the case since `skip:` is attached per `group` call):

```dart
  group('loadKeychainKeyPairs', () {
    SshKeyEntry entry(String path) => SshKeyEntry(
          label: 'k',
          algorithm: KeyAlgorithm.ed25519,
          publicKey: '',
          privateKeyPath: path,
        );

    test('loads an unencrypted key', () async {
      final pairs = await loadKeychainKeyPairs(
        [entry('test/fixtures/keys/id_ed25519')],
        (_) async => null,
      );
      expect(pairs, hasLength(1));
      expect(pairs.single.type, 'ssh-ed25519');
    });

    test('loads an encrypted key using the stored passphrase', () async {
      final pairs = await loadKeychainKeyPairs(
        [entry('test/fixtures/keys/id_ed25519_enc')],
        (_) async => 'test-passphrase',
      );
      expect(pairs, hasLength(1));
    });

    test('skips entries that cannot load, keeps the rest', () async {
      final dir = await Directory.systemTemp.createTemp('yourssh_keys');
      addTearDown(() => dir.delete(recursive: true));
      final garbage = File('${dir.path}/garbage')
        ..writeAsStringSync('not a pem');

      final pairs = await loadKeychainKeyPairs(
        [
          entry('${dir.path}/missing'), // file does not exist
          entry(garbage.path), // unparseable
          entry('test/fixtures/keys/id_ed25519_enc'), // wrong passphrase
          entry('test/fixtures/keys/id_ed25519'), // good
        ],
        (_) async => null,
      );
      expect(pairs, hasLength(1));
      expect(pairs.single.type, 'ssh-ed25519');
    });
  });
```

Add the missing import at the top of the test file:

```dart
import 'package:yourssh/models/ssh_key.dart';
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd app && flutter test test/services/agent_forwarding_handler_test.dart`
Expected: FAIL — `The function 'loadKeychainKeyPairs' isn't defined`.

- [ ] **Step 4: Implement the loader**

In `app/lib/services/agent_forwarding_handler.dart`, add imports:

```dart
import 'dart:io';
```

and (after the existing imports):

```dart
import '../models/ssh_key.dart';
```

Then append the top-level function after the class:

```dart
/// Loads every Keychain key that opens without user interaction —
/// unencrypted, or encrypted with a stored passphrase. Entries that fail
/// (missing file, wrong/missing passphrase, parse error) are skipped so one
/// broken entry never blocks the rest of the Keychain. Certificates are not
/// served in v1 (private keys only).
Future<List<SSHKeyPair>> loadKeychainKeyPairs(
  Iterable<SshKeyEntry> entries,
  Future<String?> Function(String keyId) loadPassphrase,
) async {
  final pairs = <SSHKeyPair>[];
  for (final entry in entries) {
    try {
      final pem = await File(entry.privateKeyPath).readAsString();
      final passphrase = await loadPassphrase(entry.id);
      pairs.addAll(SSHKeyPair.fromPem(
        pem,
        passphrase?.isNotEmpty == true ? passphrase : null,
      ));
    } catch (_) {
      // Skipped by design — forwarding serves whatever is loadable.
    }
  }
  return pairs;
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd app && flutter test test/services/agent_forwarding_handler_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 6: Commit**

```bash
git add app/lib/services/agent_forwarding_handler.dart app/test/services/agent_forwarding_handler_test.dart app/test/fixtures/keys/
git commit -m "feat(agent): Keychain key loader for agent-forwarding fallback"
```

---

### Task 5: dartssh2 fork — agent-forwarding refusal is non-fatal

**Files:**
- Modify: `packages/dartssh2/lib/src/ssh_client.dart:448-454` (in `exec()`) and `:515-521` (in `shell()`)

A hardened sshd with `AllowAgentForwarding no` refuses `auth-agent-req@openssh.com`;
OpenSSH warns and continues, but the fork currently throws and closes the channel,
killing the whole session. No unit test: the fork's client tests are
integration-only (tagged `integration`, hitting external servers), so this
change is covered by the analyzer, the existing fork test suite, and the
manual verification in Task 8.

- [ ] **Step 1: Apply the fix to both call sites**

In `packages/dartssh2/lib/src/ssh_client.dart`, replace **both** occurrences
(one in `exec()` ~line 448, one in `shell()` ~line 515) of:

```dart
    if (agentHandler != null) {
      final agentOk = await channelController.sendAgentForwardingRequest();
      if (!agentOk) {
        channelController.close();
        throw SSHChannelRequestError('Failed to request agent forwarding');
      }
    }
```

with:

```dart
    if (agentHandler != null) {
      final agentOk = await channelController.sendAgentForwardingRequest();
      if (!agentOk) {
        // OpenSSH treats a refused auth-agent-req as a warning, not an error
        // (e.g. sshd with AllowAgentForwarding no). Keep the session alive.
        printDebug?.call('Agent forwarding refused by server');
      }
    }
```

- [ ] **Step 2: Run the fork's non-integration tests**

Run: `cd packages/dartssh2 && dart test --exclude-tags integration`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add packages/dartssh2/lib/src/ssh_client.dart
git commit -m "fix(dartssh2): refused auth-agent-req is non-fatal, matching OpenSSH"
```

---

### Task 6: Wire the handler into `SshService`, `main.dart`, `AddHostDialog`

**Files:**
- Modify: `app/lib/services/ssh_service.dart` (field + `connect()`)
- Modify: `app/lib/main.dart` (~line 182, after `defaultKeyLookup`)
- Modify: `app/lib/widgets/add_host_dialog.dart:52-65` (preserve flag on edit)

No new unit test: `connect()` requires a live socket (existing
`ssh_service_connect_test.dart` only covers pre-network failures), and all
handler logic is already covered by Task 3/4 tests. The wiring is exercised
by manual verification in Task 8.

- [ ] **Step 1: Add the loader callback field to `SshService`**

In `app/lib/services/ssh_service.dart`, add the import:

```dart
import 'agent_forwarding_handler.dart';
```

and add after the `defaultKeyLookup` field (~line 47):

```dart
  /// Loads app-Keychain keys served through a forwarded agent when no system
  /// agent is available. Set from main.dart (KeyProvider + stored
  /// passphrases); null means the fallback serves an empty identity list.
  Future<List<SSHKeyPair>> Function()? keychainIdentitiesLoader;
```

- [ ] **Step 2: Pass the handler in `connect()`**

In the `SSHClient(...)` construction inside `connect()` (~line 163), add after
the `identities:` argument:

```dart
        identities: resolution.identities.isNotEmpty ? resolution.identities : null,
        agentHandler: host.agentForwarding
            ? AgentForwardingHandler(
                loadKeychainIdentities:
                    keychainIdentitiesLoader ?? () async => const <SSHKeyPair>[],
              )
            : null,
```

Do NOT touch `_ensureJumpClient` or `testConnection` — forwarding terminates
at the destination client only (spec: ProxyJump semantics).

- [ ] **Step 3: Wire the loader in `main.dart`**

In `app/lib/main.dart`, add after `_ssh.defaultKeyLookup = …` (~line 182):

```dart
    _ssh.keychainIdentitiesLoader = () =>
        loadKeychainKeyPairs(_keyProvider.keys, _storage.loadPassphrase);
```

and add the import alongside the other service imports:

```dart
import 'services/agent_forwarding_handler.dart';
```

- [ ] **Step 4: Preserve the flag in `AddHostDialog`**

`AddHostDialog` (the quick add/edit dialog used by `host_list.dart`) rebuilds
the `Host` without the advanced toggles; without this line, editing a host
there would silently reset `agentForwarding` to false. In
`app/lib/widgets/add_host_dialog.dart`, inside the `Host(` construction
(~line 52), add:

```dart
      sftpServerCommand:
          _sftpMode == SftpMode.custom ? _sftpCommand.text.trim() : null,
      agentForwarding: widget.existing?.agentForwarding ?? false,
```

(Note: the dialog already drops `autoRecord`/`group`/`tags`/`jumpHostId` on
edit — pre-existing bug, out of scope here; flagged separately.)

- [ ] **Step 5: Analyze and run service tests**

Run: `cd app && flutter analyze && flutter test test/services/`
Expected: analyze clean; tests PASS.

- [ ] **Step 6: Commit**

```bash
git add app/lib/services/ssh_service.dart app/lib/main.dart app/lib/widgets/add_host_dialog.dart
git commit -m "feat(ssh): wire agent forwarding handler into connect() (issue #49)"
```

---

### Task 7: UI toggle in `HostDetailPanel`

**Files:**
- Test: `app/test/widgets/host_detail_panel_agent_forwarding_test.dart` (create)
- Modify: `app/lib/widgets/host_detail_panel.dart` (state ~line 46, initState ~line 67, save ~line 103, toggles ~line 446, section label ~line 414)

- [ ] **Step 1: Write the failing widget test**

Create `app/test/widgets/host_detail_panel_agent_forwarding_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/host_detail_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Host? saved;

  Future<void> pumpPanel(WidgetTester tester, {Host? existing}) async {
    saved = null;
    await tester.binding.setSurfaceSize(const Size(500, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<KeyProvider>(create: (_) => KeyProvider()),
          ChangeNotifierProvider<HostProvider>(
              create: (_) => HostProvider(StorageService())),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: HostDetailPanel(
              existing: existing,
              onClose: () {},
              onSave: (host, _) async => saved = host,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Host existingHost({bool agentForwarding = false}) => Host(
        label: 'srv',
        host: '1.2.3.4',
        username: 'root',
        agentForwarding: agentForwarding,
      );

  testWidgets('toggle defaults off and saves true after switching on',
      (tester) async {
    await pumpPanel(tester, existing: existingHost());

    final toggle = find.widgetWithText(SwitchListTile, 'Agent forwarding');
    await tester.ensureVisible(toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    final save = find.text('SAVE ONLY');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.agentForwarding, isTrue);
  });

  testWidgets('editing a host with forwarding on shows the switch on',
      (tester) async {
    await pumpPanel(tester, existing: existingHost(agentForwarding: true));

    final toggle = find.widgetWithText(SwitchListTile, 'Agent forwarding');
    await tester.ensureVisible(toggle);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/host_detail_panel_agent_forwarding_test.dart`
Expected: FAIL — `Agent forwarding` SwitchListTile not found.

- [ ] **Step 3: Implement the toggle**

In `app/lib/widgets/host_detail_panel.dart`:

State field (after `bool _shellIntegration = true;`, ~line 46):

```dart
  bool _shellIntegration = true;
  bool _agentForwarding = false;
```

`initState()` (after `_shellIntegration = …`, ~line 67):

```dart
    _shellIntegration = h?.shellIntegration ?? true;
    _agentForwarding = h?.agentForwarding ?? false;
```

`_save()` `Host(` construction (after `shellIntegration: _shellIntegration,`, ~line 103):

```dart
      shellIntegration: _shellIntegration,
      agentForwarding: _agentForwarding,
```

Section label (~line 414) — the card now holds session behaviour toggles, not
just recording, so rename:

```dart
                  _sectionLabel('SESSION'),
```

New `SwitchListTile` after the Shell integration tile (after its closing `),`
~line 446, still inside the same `_Card(children: [...])`):

```dart
                    SwitchListTile(
                      value: _agentForwarding,
                      onChanged: (v) => setState(() => _agentForwarding = v),
                      title: const Text(
                        'Agent forwarding',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Forward your local SSH agent to this host (like ssh -A)',
                        style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                      ),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      activeThumbColor: AppColors.accent,
                    ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/widgets/host_detail_panel_agent_forwarding_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/host_detail_panel.dart app/test/widgets/host_detail_panel_agent_forwarding_test.dart
git commit -m "feat(ui): agent forwarding toggle in host detail panel (issue #49)"
```

---

### Task 8: Full verification + changelog

**Files:**
- Modify: `CHANGELOG.md` (`[Unreleased]` section)

- [ ] **Step 1: Run the full app test suite and analyzer**

Run: `cd app && flutter analyze && flutter test`
Expected: analyze clean, all tests PASS.

- [ ] **Step 2: Manual verification (macOS)**

1. `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/<some-key>` in a local terminal,
   then launch the app from that shell (`cd app && flutter run -d macos`) so it
   inherits `SSH_AUTH_SOCK`.
2. Edit a host → enable **Agent forwarding** → connect → on the remote shell:
   `echo $SSH_AUTH_SOCK` (non-empty) and `ssh-add -l` (lists the local key).
3. From that remote shell, `ssh` to a second host that trusts the key — hop
   succeeds without a key file on the first host.
4. Toggle off → reconnect → `ssh-add -l` reports no agent.
5. Fallback: `ssh-add -D; kill $SSH_AGENT_PID`, relaunch app without
   `SSH_AUTH_SOCK`, add a key in Keychain, connect with forwarding on →
   `ssh-add -l` on the remote lists the Keychain key.

- [ ] **Step 3: Update CHANGELOG**

Add under `## [Unreleased]` in `CHANGELOG.md` (create an `### Added` heading
if absent):

```markdown
### Added
- SSH Agent Forwarding (per-host toggle, like `ssh -A`): forwarded agent
  channels are served by the local system agent (`SSH_AUTH_SOCK` / Windows
  OpenSSH agent pipe), falling back to keys stored in the app Keychain when
  no system agent is running. A server refusing the forwarding request no
  longer aborts the session. ([#49](https://github.com/YoursshLabs/yourssh/issues/49))
```

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): SSH agent forwarding (issue #49)"
```

---

## Out of scope / follow-ups

- `AddHostDialog` drops `autoRecord`, `group`, `tags`, `jumpHostId`,
  `createdAt`, `detectedOs` when editing (pre-existing data-loss bug) — file a
  separate issue; this plan only preserves the new `agentForwarding` flag there.
- Serving Keychain SSH certificates through the forwarded agent (spec v1 scope).
- GitHub issue #49 hygiene (labels, linked commits, closing comment in
  Vietnamese) happens at PR time per repo workflow.
