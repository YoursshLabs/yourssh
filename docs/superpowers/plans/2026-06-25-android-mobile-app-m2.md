# Android Mobile App — Milestone 2 (Hosts + Terminal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Android, list/add hosts, connect over SSH, and use a working terminal with a mobile accessory key bar and pinch-to-zoom.

**Architecture:** A mobile-specific bootstrap (`lib/mobile/mobile_bootstrap.dart`) constructs the *existing* platform-agnostic services/providers (`StorageService`, `SshService`, `HostProvider`, `KeyProvider`, `SettingsProvider`, `KnownHostsProvider`, `SessionProvider`) and wires the minimal callbacks needed to connect — deliberately NOT touching the fragile desktop `_YourSSHAppState` bootstrap (zero desktop regression risk; the *classes* are reused, only the wiring is mobile-scoped). Mobile screens consume these via `provider`. The terminal renders the same xterm fork `Terminal` that `SshSession` already owns.

**Tech Stack:** Flutter, `provider`, `xterm` (local fork), existing `SshService`/`SessionProvider`.

## Global Constraints

- Dart package `yourssh`; imports `package:yourssh/...` (tests) and relative (lib).
- App is dark-only; colors from `app/lib/theme/app_theme.dart` (`AppColors`: `bg`, `card`, `accent`, `textPrimary`, `textSecondary`, `border`).
- Reuse existing classes; do NOT modify desktop `main.dart` bootstrap or desktop widgets.
- TOFU: first-connect auto-trusts (`KnownHostsProvider.verifyHostKey` adds + returns true); the *mismatch* challenge UI is deferred to M5 (a fresh mobile install has empty known-hosts, so M2 connects never block).
- Desktop builds + full `flutter test` + `flutter analyze` MUST stay green.
- No Claude attribution. Commit after each task. Branch: `feat/android-mobile-app`.

## Key existing APIs (verified)

- `SshService(StorageService storage, {hookBus, shellIntegration})` — extras optional.
- `HostProvider(storage)` auto-loads; `allHosts` (List<Host>), `addHost(Host, {String? password})`, `groups`, `updateDetectedOs(id, os)`.
- `KeyProvider()` auto-loads; `keys` (List<SshKeyEntry>), `findById(id)`, `savePassphrase` settable.
- `SettingsProvider()` auto-loads; `autoReconnect`, `reconnectAttempts`, `tmuxEnabled`, `terminalType`.
- `KnownHostsProvider(storage)`; `load()`, `verifyHostKey(host, port, keyType, fp)`.
- `SessionProvider(SshService, TabMetadataService)`; `sessions` (List<AppSession>), `sshSessions`, `activeSession`, `setActive(id)`, `connectAny(Host)`, callbacks: `keyLookup`, `jumpHostLookup`, `autoReconnectEnabled`, `reconnectAttempts`, `tmuxEnabled`, `terminalType`, `hostKeyVerifier`, `onOsDetected`.
- `SshSession` (implements AppSession): `terminal` (xterm `Terminal`), `status` (`SessionStatus.{connecting,connected,disconnected,error}`), `errorMessage`, `host`, `tabLabel`, `statusLabel`.
- `Host({required label, required host, port=22, required username, authType=AuthType.password, keyId, ...})`.
- xterm `Terminal.keyInput(TerminalKey key, {shift, alt, ctrl})` and `Terminal.textInput(String)`.

---

## Phase M2.1 — Bootstrap + Hosts + Connect

### Task 1: Mobile bootstrap (`mobile_bootstrap.dart`)

**Files:**
- Create: `app/lib/mobile/mobile_bootstrap.dart`
- Modify: `app/lib/mobile/mobile_app.dart` (wrap shell in `MultiProvider`)
- Test: `app/test/mobile/mobile_bootstrap_test.dart`

**Interfaces:**
- Produces: `class MobileBootstrap` with public fields `storage`, `ssh`, `hostProvider`, `keyProvider`, `settings`, `knownHosts`, `sessions`, and `List<SingleChildWidget> get providers`. Constructed once in `YourSSHMobileApp`.

- [ ] **Step 1: Write the failing test**

Create `app/test/mobile/mobile_bootstrap_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/mobile_bootstrap.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('constructs services and wires SessionProvider callbacks', () {
    final b = MobileBootstrap();

    // Connect-critical callbacks must be wired.
    expect(b.sessions.keyLookup, isNotNull);
    expect(b.sessions.hostKeyVerifier, isNotNull);
    expect(b.sessions.autoReconnectEnabled, isNotNull);
    expect(b.sessions.terminalType, isNotNull);
    expect(b.ssh.defaultHostKeyVerifier, isNotNull);
    expect(b.ssh.defaultKeyLookup, isNotNull);

    // Exposes a provider list for the widget tree.
    expect(b.providers, isNotEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/mobile_bootstrap_test.dart`
Expected: FAIL — `mobile_bootstrap.dart` URI doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `app/lib/mobile/mobile_bootstrap.dart`:
```dart
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../providers/host_provider.dart';
import '../providers/key_provider.dart';
import '../providers/known_hosts_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../services/ssh_service.dart';
import '../services/storage_service.dart';
import '../services/tab_metadata_service.dart';

/// Constructs the platform-agnostic services/providers the Android app needs
/// and wires the minimal callbacks required to connect over SSH. Mirrors the
/// desktop wiring in `main.dart` but only for the mobile-relevant subset —
/// kept separate so the desktop bootstrap stays untouched.
class MobileBootstrap {
  late final StorageService storage;
  late final SshService ssh;
  late final HostProvider hostProvider;
  late final KeyProvider keyProvider;
  late final SettingsProvider settings;
  late final KnownHostsProvider knownHosts;
  late final SessionProvider sessions;

  MobileBootstrap() {
    storage = StorageService();
    ssh = SshService(storage);
    hostProvider = HostProvider(storage);
    keyProvider = KeyProvider()..savePassphrase = storage.savePassphrase;
    settings = SettingsProvider();
    knownHosts = KnownHostsProvider(storage)..load();
    sessions = SessionProvider(ssh, TabMetadataService());
    _wire();
  }

  void _wire() {
    sessions.keyLookup = (id) => keyProvider.findById(id);
    sessions.jumpHostLookup =
        (id) => hostProvider.allHosts.where((h) => h.id == id).firstOrNull;
    sessions.autoReconnectEnabled = () => settings.autoReconnect;
    sessions.reconnectAttempts = () => settings.reconnectAttempts;
    sessions.tmuxEnabled = () => settings.tmuxEnabled;
    sessions.terminalType = () => settings.terminalType;
    sessions.hostKeyVerifier = knownHosts.verifyHostKey;
    sessions.onOsDetected = (id, os) => hostProvider.updateDetectedOs(id, os);

    ssh.defaultHostKeyVerifier = knownHosts.verifyHostKey;
    ssh.defaultKeyLookup = (id) => keyProvider.findById(id);
    ssh.defaultJumpHostLookup =
        (id) => hostProvider.allHosts.where((h) => h.id == id).firstOrNull;
  }

  List<SingleChildWidget> get providers => [
        Provider.value(value: storage),
        Provider.value(value: ssh),
        ChangeNotifierProvider.value(value: hostProvider),
        ChangeNotifierProvider.value(value: keyProvider),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: knownHosts),
        ChangeNotifierProvider.value(value: sessions),
      ];
}
```

> If `provider/single_child_widget.dart` import fails, use `package:nested/nested.dart` or type the getter as `List<dynamic>`; verify the real export at execution.

- [ ] **Step 4: Wire into `YourSSHMobileApp`**

Modify `app/lib/mobile/mobile_app.dart` — make it stateful, hold a `MobileBootstrap`, wrap the home in `MultiProvider`:
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import 'mobile_bootstrap.dart';
import 'screens/mobile_home_shell.dart';

class YourSSHMobileApp extends StatefulWidget {
  const YourSSHMobileApp({super.key});

  @override
  State<YourSSHMobileApp> createState() => _YourSSHMobileAppState();
}

class _YourSSHMobileAppState extends State<YourSSHMobileApp> {
  final _bootstrap = MobileBootstrap();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: _bootstrap.providers,
      child: MaterialApp(
        title: 'YourSSH',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: buildAppTheme(),
        home: const MobileHomeShell(),
      ),
    );
  }
}
```

- [ ] **Step 5: Run tests + analyze**

Run: `cd app && flutter test test/mobile/mobile_bootstrap_test.dart && flutter analyze lib/mobile`
Expected: PASS; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/mobile/mobile_bootstrap.dart app/lib/mobile/mobile_app.dart app/test/mobile/mobile_bootstrap_test.dart
git commit -m "feat(mobile): bootstrap providers + SSH wiring"
```

---

### Task 2: Hosts screen (list + search + connect + add FAB)

**Files:**
- Create: `app/lib/mobile/screens/mobile_hosts_screen.dart`
- Test: `app/test/mobile/mobile_hosts_screen_test.dart`

**Interfaces:**
- Consumes: `HostProvider.allHosts`, `SessionProvider.connectAny`.
- Produces: `class MobileHostsScreen extends StatefulWidget` — searchable host list; tapping a row calls `context.read<SessionProvider>().connectAny(host)` then invokes an injected `onConnected` callback (the shell switches to the Sessions tab). A FAB opens the add-host form via injected `onAddHost`.

- [ ] **Step 1: Write the failing test**

Create `app/test/mobile/mobile_hosts_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/mobile/screens/mobile_hosts_screen.dart';
import 'package:yourssh/services/storage_service.dart';

Future<void> _pump(WidgetTester tester, HostProvider hosts) async {
  await tester.pumpWidget(MaterialApp(
    home: ChangeNotifierProvider.value(
      value: hosts,
      child: MobileHostsScreen(onConnected: () {}, onAddHost: () {}),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists hosts and filters by search', (tester) async {
    final hosts = HostProvider(StorageService());
    await hosts.addHost(Host(label: 'prod-web', host: '10.0.0.1', username: 'root'));
    await hosts.addHost(Host(label: 'db-1', host: '10.0.0.2', username: 'admin'));

    await _pump(tester, hosts);
    expect(find.text('prod-web'), findsOneWidget);
    expect(find.text('db-1'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'prod');
    await tester.pumpAndSettle();
    expect(find.text('prod-web'), findsOneWidget);
    expect(find.text('db-1'), findsNothing);
  });

  testWidgets('shows empty state with no hosts', (tester) async {
    await _pump(tester, HostProvider(StorageService()));
    expect(find.textContaining('No hosts'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/mobile_hosts_screen_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `app/lib/mobile/screens/mobile_hosts_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/host.dart';
import '../../providers/host_provider.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';

/// Hosts tab: searchable list of saved hosts; tap to connect, FAB to add.
class MobileHostsScreen extends StatefulWidget {
  final VoidCallback onConnected;
  final VoidCallback onAddHost;

  const MobileHostsScreen({
    super.key,
    required this.onConnected,
    required this.onAddHost,
  });

  @override
  State<MobileHostsScreen> createState() => _MobileHostsScreenState();
}

class _MobileHostsScreenState extends State<MobileHostsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = context.watch<HostProvider>().allHosts;
    final q = _query.trim().toLowerCase();
    final hosts = q.isEmpty
        ? all
        : all
            .where((h) =>
                h.label.toLowerCase().contains(q) ||
                h.host.toLowerCase().contains(q) ||
                h.username.toLowerCase().contains(q))
            .toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: widget.onAddHost,
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search hosts',
                  prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: hosts.isEmpty
                  ? const Center(
                      child: Text('No hosts yet — tap + to add one',
                          style: TextStyle(color: AppColors.textSecondary)))
                  : ListView.builder(
                      itemCount: hosts.length,
                      itemBuilder: (_, i) => _HostRow(
                        host: hosts[i],
                        onTap: () => _connect(hosts[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connect(Host host) async {
    // Fire the connect (async) and immediately switch to the Sessions tab so
    // the user watches it come up live.
    context.read<SessionProvider>().connectAny(host);
    widget.onConnected();
  }
}

class _HostRow extends StatelessWidget {
  final Host host;
  final VoidCallback onTap;
  const _HostRow({required this.host, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: const Icon(Icons.dns_outlined, color: AppColors.textSecondary),
      title: Text(host.label, style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: Text('${host.username}@${host.host}:${host.port}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/mobile/mobile_hosts_screen_test.dart`
Expected: PASS (both tests).

> The connect test path isn't exercised here (needs SessionProvider); covered in Task 5's integration via the shell. The list/search/empty behavior is what this task guarantees.

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/screens/mobile_hosts_screen.dart app/test/mobile/mobile_hosts_screen_test.dart
git commit -m "feat(mobile): hosts screen with search and connect"
```

---

### Task 3: Minimal add-host form

**Files:**
- Create: `app/lib/mobile/screens/mobile_add_host_screen.dart`
- Test: `app/test/mobile/mobile_add_host_screen_test.dart`

**Interfaces:**
- Consumes: `HostProvider.addHost(Host, {password})`, `KeyProvider.keys`.
- Produces: `class MobileAddHostScreen extends StatefulWidget` — label/host/port/username + auth (password text OR pick a saved key) + Save. On save, builds a `Host` and calls `HostProvider.addHost`, then pops.

- [ ] **Step 1: Write the failing test**

Create `app/test/mobile/mobile_add_host_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/mobile/screens/mobile_add_host_screen.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('saving creates a host in the provider', (tester) async {
    final hosts = HostProvider(StorageService());
    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: hosts),
          ChangeNotifierProvider(create: (_) => KeyProvider()),
        ],
        child: const MobileAddHostScreen(),
      ),
    ));

    await tester.enterText(find.byKey(const Key('host-label')), 'edge-1');
    await tester.enterText(find.byKey(const Key('host-address')), '192.168.1.9');
    await tester.enterText(find.byKey(const Key('host-username')), 'pi');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(hosts.allHosts.any((h) => h.label == 'edge-1' && h.host == '192.168.1.9'),
        isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/mobile_add_host_screen_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `app/lib/mobile/screens/mobile_add_host_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/host.dart';
import '../../models/ssh_key.dart';
import '../../providers/host_provider.dart';
import '../../providers/key_provider.dart';
import '../../theme/app_theme.dart';

/// Minimal add-host form for mobile: label/host/port/username + password or a
/// saved key. Full editor (tags, proxy, jump chain, RDP/VNC) is desktop-only.
class MobileAddHostScreen extends StatefulWidget {
  const MobileAddHostScreen({super.key});

  @override
  State<MobileAddHostScreen> createState() => _MobileAddHostScreenState();
}

class _MobileAddHostScreenState extends State<MobileAddHostScreen> {
  final _label = TextEditingController();
  final _address = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _useKey = false;
  String? _keyId;

  @override
  void dispose() {
    for (final c in [_label, _address, _port, _username, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    final address = _address.text.trim();
    final username = _username.text.trim();
    if (label.isEmpty || address.isEmpty || username.isEmpty) return;

    final host = Host(
      label: label,
      host: address,
      port: int.tryParse(_port.text.trim()) ?? 22,
      username: username,
      authType: _useKey ? AuthType.privateKey : AuthType.password,
      keyId: _useKey ? _keyId : null,
    );
    await context.read<HostProvider>().addHost(
          host,
          password: _useKey ? null : _password.text,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<KeyProvider>().keys;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Add host'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(_label, 'Label', key: 'host-label'),
            _field(_address, 'Host / IP', key: 'host-address'),
            _field(_port, 'Port', key: 'host-port',
                keyboard: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly]),
            _field(_username, 'Username', key: 'host-username'),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _useKey,
              onChanged: keys.isEmpty ? null : (v) => setState(() => _useKey = v),
              title: const Text('Use SSH key',
                  style: TextStyle(color: AppColors.textPrimary)),
              subtitle: keys.isEmpty
                  ? const Text('No keys imported — using password',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12))
                  : null,
            ),
            if (_useKey)
              DropdownButtonFormField<String>(
                initialValue: _keyId,
                items: [
                  for (final SshKeyEntry k in keys)
                    DropdownMenuItem(value: k.id, child: Text(k.name)),
                ],
                onChanged: (v) => setState(() => _keyId = v),
                decoration: const InputDecoration(labelText: 'Key'),
              )
            else
              _field(_password, 'Password', key: 'host-password', obscure: true),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    required String key,
    bool obscure = false,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: Key(key),
        controller: c,
        obscureText: obscure,
        keyboardType: keyboard,
        inputFormatters: formatters,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
```

> Verify at execution: `SshKeyEntry` has `id` and `name` (or `label`) fields — adjust the dropdown accordingly. `AuthType.privateKey` is the enum value used by `Host`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/mobile/mobile_add_host_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/screens/mobile_add_host_screen.dart app/test/mobile/mobile_add_host_screen_test.dart
git commit -m "feat(mobile): minimal add-host form"
```

---

### Task 4: Sessions screen (strip + terminal/status)

**Files:**
- Create: `app/lib/mobile/screens/mobile_sessions_screen.dart`
- Test: `app/test/mobile/mobile_sessions_screen_test.dart`

**Interfaces:**
- Consumes: `SessionProvider.sshSessions`, `activeSession`, `setActive(id)`; `SshSession.terminal/status/tabLabel/statusLabel`.
- Produces: `class MobileSessionsScreen extends StatelessWidget` — a horizontally scrollable session strip (chips) + a body that, for the active SSH session, shows `TerminalView(session.terminal)` when `connected`, else a centered status (`statusLabel` + spinner while connecting + error text). Empty state when no sessions.

- [ ] **Step 1: Write the failing test**

Create `app/test/mobile/mobile_sessions_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/mobile/screens/mobile_sessions_screen.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('empty state with no sessions', (tester) async {
    final sp = SessionProvider(SshService(StorageService()), TabMetadataService());
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider.value(
        value: sp,
        child: const MobileSessionsScreen(),
      ),
    ));
    expect(find.textContaining('No active sessions'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/mobile_sessions_screen_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `app/lib/mobile/screens/mobile_sessions_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../../models/ssh_session.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';

/// Sessions tab: a session strip + the active SSH session's terminal (when
/// connected) or its connection status. The accessory key bar (M2.2) docks
/// below the terminal.
class MobileSessionsScreen extends StatelessWidget {
  const MobileSessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SessionProvider>();
    final ssh = sp.sshSessions;

    if (ssh.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Text('No active sessions — connect from Hosts',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    final active = sp.activeSession is SshSession
        ? sp.activeSession as SshSession
        : ssh.last;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _SessionStrip(sessions: ssh, activeId: active.id),
            const Divider(height: 1, color: AppColors.border),
            Expanded(child: _SessionBody(session: active)),
          ],
        ),
      ),
    );
  }
}

class _SessionStrip extends StatelessWidget {
  final List<SshSession> sessions;
  final String activeId;
  const _SessionStrip({required this.sessions, required this.activeId});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          for (final s in sessions)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(s.tabLabel),
                selected: s.id == activeId,
                onSelected: (_) => context.read<SessionProvider>().setActive(s.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionBody extends StatelessWidget {
  final SshSession session;
  const _SessionBody({required this.session});

  @override
  Widget build(BuildContext context) {
    if (session.status == SessionStatus.connected) {
      return TerminalView(session.terminal);
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (session.status == SessionStatus.connecting)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: CircularProgressIndicator(),
            ),
          Text(session.statusLabel,
              style: const TextStyle(color: AppColors.textSecondary)),
          if (session.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(session.errorMessage!,
                style: const TextStyle(color: AppColors.red, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
```

> Verify at execution: `AppColors.red` exists (used by `session_connecting_view.dart`). `TerminalView` is exported by `package:xterm/xterm.dart`. `SshSession` must `extends ChangeNotifier` (or be listenable) for the strip/body to rebuild on status change — the screen `context.watch<SessionProvider>()` rebuilds when the provider notifies, which `SessionProvider` does on connect; if per-session status changes don't notify the provider, wrap `_SessionBody` in an `AnimatedBuilder`/`ListenableBuilder(listenable: session)`.

- [ ] **Step 4: Run test + analyze**

Run: `cd app && flutter test test/mobile/mobile_sessions_screen_test.dart && flutter analyze lib/mobile`
Expected: PASS; `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/screens/mobile_sessions_screen.dart app/test/mobile/mobile_sessions_screen_test.dart
git commit -m "feat(mobile): sessions screen with terminal + status"
```

---

### Task 5: Wire Hosts + Sessions into the shell

**Files:**
- Modify: `app/lib/mobile/screens/mobile_home_shell.dart`
- Test: update `app/test/mobile/mobile_home_shell_test.dart` (now needs providers)

**Interfaces:**
- Consumes: `MobileHostsScreen`, `MobileSessionsScreen`, `MobileAddHostScreen`.
- Produces: shell that shows the real Hosts (index 0) and Sessions (index 1) screens; SFTP/Settings stay placeholders. Tapping a host connects and switches to Sessions; FAB pushes the add-host route.

- [ ] **Step 1: Update the shell test**

Replace `app/test/mobile/mobile_home_shell_test.dart` with a provider-backed pump (the shell now reads `HostProvider`/`SessionProvider`):
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/screens/mobile_home_shell.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

Future<void> _pump(WidgetTester tester) async {
  final storage = StorageService();
  final ssh = SshService(storage);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => HostProvider(storage)),
      ChangeNotifierProvider(create: (_) => KeyProvider()),
      ChangeNotifierProvider(create: (_) => SessionProvider(ssh, TabMetadataService())),
    ],
    child: const MaterialApp(home: MobileHomeShell()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows four destinations; Hosts first', (tester) async {
    await _pump(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.textContaining('No hosts'), findsOneWidget); // Hosts screen body
  });

  testWidgets('switches to SFTP placeholder', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('SFTP').last);
    await tester.pumpAndSettle();
    expect(find.text('SFTP — coming soon'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/mobile_home_shell_test.dart`
Expected: FAIL — the current shell shows `'Hosts — coming soon'`, not the hosts list.

- [ ] **Step 3: Update `MobileHomeShell`**

Replace the body builder so indices 0/1 render real screens:
```dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'mobile_add_host_screen.dart';
import 'mobile_hosts_screen.dart';
import 'mobile_sessions_screen.dart';

class MobileHomeShell extends StatefulWidget {
  const MobileHomeShell({super.key});

  @override
  State<MobileHomeShell> createState() => _MobileHomeShellState();
}

class _MobileHomeShellState extends State<MobileHomeShell> {
  int _index = 0;

  static const _labels = ['Hosts', 'Sessions', 'SFTP', 'Settings'];
  static const _icons = [
    Icons.dns_outlined,
    Icons.terminal_outlined,
    Icons.folder_outlined,
    Icons.settings_outlined,
  ];

  void _openAddHost() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MobileAddHostScreen()),
    );
  }

  Widget _body() {
    switch (_index) {
      case 0:
        return MobileHostsScreen(
          onConnected: () => setState(() => _index = 1),
          onAddHost: _openAddHost,
        );
      case 1:
        return const MobileSessionsScreen();
      default:
        return Center(
          child: Text('${_labels[_index]} — coming soon',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _body(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (var i = 0; i < _labels.length; i++)
            NavigationDestination(icon: Icon(_icons[i]), label: _labels[i]),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/mobile/`
Expected: PASS (all mobile tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/screens/mobile_home_shell.dart app/test/mobile/mobile_home_shell_test.dart
git commit -m "feat(mobile): wire hosts + sessions into shell"
```

---

## Phase M2.2 — Accessory key bar + pinch-zoom

### Task 6: Accessory bar controller (sticky modifiers) — pure logic

**Files:**
- Create: `app/lib/mobile/terminal/accessory_bar_controller.dart`
- Test: `app/test/mobile/accessory_bar_controller_test.dart`

**Interfaces:**
- Produces: `class AccessoryBarController` — holds sticky `ctrl`/`alt` arm state; `armCtrl()`, `armAlt()` toggle; `consumeModifiers()` returns `({bool ctrl, bool alt})` and clears the arm (one-shot). Decouples the sticky logic from the widget so it is unit-testable.

- [ ] **Step 1: Write the failing test**

Create `app/test/mobile/accessory_bar_controller_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/terminal/accessory_bar_controller.dart';

void main() {
  test('modifiers default off and consume returns false', () {
    final c = AccessoryBarController();
    final m = c.consumeModifiers();
    expect(m.ctrl, isFalse);
    expect(m.alt, isFalse);
  });

  test('armed ctrl is one-shot: consumed once then cleared', () {
    final c = AccessoryBarController();
    c.armCtrl();
    expect(c.ctrlArmed, isTrue);
    final m1 = c.consumeModifiers();
    expect(m1.ctrl, isTrue);
    expect(c.ctrlArmed, isFalse); // cleared after consume
    final m2 = c.consumeModifiers();
    expect(m2.ctrl, isFalse);
  });

  test('arm toggles off when armed again', () {
    final c = AccessoryBarController();
    c.armCtrl();
    c.armCtrl();
    expect(c.ctrlArmed, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/accessory_bar_controller_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `app/lib/mobile/terminal/accessory_bar_controller.dart`:
```dart
import 'package:flutter/foundation.dart';

/// Sticky Ctrl/Alt state for the mobile terminal accessory bar. Modifiers are
/// one-shot: arming sets the flag, the next emitted key consumes and clears it
/// (mstsc/Termux-style). A [ChangeNotifier] so the bar highlights armed keys.
class AccessoryBarController extends ChangeNotifier {
  bool _ctrl = false;
  bool _alt = false;

  bool get ctrlArmed => _ctrl;
  bool get altArmed => _alt;

  void armCtrl() {
    _ctrl = !_ctrl;
    notifyListeners();
  }

  void armAlt() {
    _alt = !_alt;
    notifyListeners();
  }

  /// Returns the currently-armed modifiers and clears them (one-shot).
  ({bool ctrl, bool alt}) consumeModifiers() {
    final m = (ctrl: _ctrl, alt: _alt);
    if (_ctrl || _alt) {
      _ctrl = false;
      _alt = false;
      notifyListeners();
    }
    return m;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/mobile/accessory_bar_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/terminal/accessory_bar_controller.dart app/test/mobile/accessory_bar_controller_test.dart
git commit -m "feat(mobile): accessory bar sticky-modifier controller"
```

---

### Task 7: Accessory bar widget + wire to terminal

**Files:**
- Create: `app/lib/mobile/terminal/accessory_key_bar.dart`
- Modify: `app/lib/mobile/screens/mobile_sessions_screen.dart` (dock the bar under the terminal when connected)
- Test: `app/test/mobile/accessory_key_bar_test.dart`

**Interfaces:**
- Consumes: `AccessoryBarController`, an `onKey(TerminalKey, {ctrl, alt})` callback and an `onText(String)` callback.
- Produces: `class AccessoryKeyBar extends StatelessWidget` — a horizontally scrollable row: Esc, Tab, Ctrl (sticky), Alt (sticky), ←↑↓→, and chars `/ - | ~`. Special keys call `onKey` with consumed modifiers; chars call `onText` (consuming modifiers — when ctrl armed, a char routes via `onKey` for the letter so Ctrl+C works).

- [ ] **Step 1: Write the failing test**

Create `app/test/mobile/accessory_key_bar_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/mobile/terminal/accessory_bar_controller.dart';
import 'package:yourssh/mobile/terminal/accessory_key_bar.dart';

void main() {
  testWidgets('Esc taps emit escape key', (tester) async {
    TerminalKey? got;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccessoryKeyBar(
          controller: AccessoryBarController(),
          onKey: (k, {ctrl = false, alt = false}) => got = k,
          onText: (_) {},
        ),
      ),
    ));
    await tester.tap(find.text('Esc'));
    expect(got, TerminalKey.escape);
  });

  testWidgets('Ctrl then arrow emits ctrl-modified key', (tester) async {
    bool? gotCtrl;
    final c = AccessoryBarController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccessoryKeyBar(
          controller: c,
          onKey: (k, {ctrl = false, alt = false}) => gotCtrl = ctrl,
          onText: (_) {},
        ),
      ),
    ));
    await tester.tap(find.text('Ctrl'));
    await tester.pump();
    await tester.tap(find.byTooltip('Up'));
    expect(gotCtrl, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/accessory_key_bar_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `app/lib/mobile/terminal/accessory_key_bar.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../theme/app_theme.dart';
import 'accessory_bar_controller.dart';

/// Mobile terminal accessory bar: special keys + sticky Ctrl/Alt above the
/// soft keyboard. Emits xterm [TerminalKey]s (with consumed modifiers) via
/// [onKey] and literal characters via [onText].
class AccessoryKeyBar extends StatelessWidget {
  final AccessoryBarController controller;
  final void Function(TerminalKey key, {bool ctrl, bool alt}) onKey;
  final void Function(String text) onText;

  const AccessoryKeyBar({
    super.key,
    required this.controller,
    required this.onKey,
    required this.onText,
  });

  void _key(TerminalKey k) {
    final m = controller.consumeModifiers();
    onKey(k, ctrl: m.ctrl, alt: m.alt);
  }

  void _text(String s) {
    final m = controller.consumeModifiers();
    if (m.ctrl && s.length == 1) {
      // Route a Ctrl+<letter> through keyInput so control codes are produced.
      final k = _letterKey(s);
      if (k != null) {
        onKey(k, ctrl: true, alt: m.alt);
        return;
      }
    }
    onText(s);
  }

  TerminalKey? _letterKey(String s) {
    final lower = s.toLowerCase();
    if (lower.length != 1 || lower.codeUnitAt(0) < 0x61 || lower.codeUnitAt(0) > 0x7a) {
      return null;
    }
    final index = lower.codeUnitAt(0) - 0x61; // a..z
    return TerminalKey.values.firstWhere(
      (k) => k.name == 'key${s.toUpperCase()}',
      orElse: () => TerminalKey.keyA,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          height: 46,
          color: AppColors.card,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            children: [
              _btn('Esc', onTap: () => _key(TerminalKey.escape)),
              _btn('Tab', onTap: () => _key(TerminalKey.tab)),
              _btn('Ctrl', armed: controller.ctrlArmed, onTap: controller.armCtrl),
              _btn('Alt', armed: controller.altArmed, onTap: controller.armAlt),
              _icon(Icons.keyboard_arrow_left, 'Left',
                  () => _key(TerminalKey.arrowLeft)),
              _icon(Icons.keyboard_arrow_up, 'Up', () => _key(TerminalKey.arrowUp)),
              _icon(Icons.keyboard_arrow_down, 'Down',
                  () => _key(TerminalKey.arrowDown)),
              _icon(Icons.keyboard_arrow_right, 'Right',
                  () => _key(TerminalKey.arrowRight)),
              for (final ch in const ['/', '-', '|', '~', ':'])
                _btn(ch, onTap: () => _text(ch)),
            ],
          ),
        );
      },
    );
  }

  Widget _btn(String label, {required VoidCallback onTap, bool armed = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: armed ? AppColors.accent : AppColors.bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  color: armed ? Colors.black : AppColors.textPrimary,
                  fontSize: 14)),
        ),
      ),
    );
  }

  Widget _icon(IconData icon, String tooltip, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 20),
          ),
        ),
      ),
    );
  }
}
```

> Verify at execution: `TerminalKey` enum member names (`escape`, `tab`, `arrowUp`, `keyA`…). If `firstWhere` by name is brittle, build a small `const` map `{'c': TerminalKey.keyC, ...}` for the common Ctrl letters (c, d, z, l, a, e, k, u, r) instead.

- [ ] **Step 4: Dock the bar in the sessions screen**

In `mobile_sessions_screen.dart`, give the screen an `AccessoryBarController` (StatefulWidget) and, when the active session is connected, place `AccessoryKeyBar` below the `TerminalView`, wiring:
```dart
AccessoryKeyBar(
  controller: _accessory,
  onKey: (k, {ctrl = false, alt = false}) =>
      session.terminal.keyInput(k, ctrl: ctrl, alt: alt),
  onText: (s) => session.terminal.textInput(s),
)
```
(Convert `MobileSessionsScreen` to `StatefulWidget`; create `_accessory = AccessoryBarController()` in `initState`; dispose it. Wrap the `Column`'s terminal area in `Expanded(child: TerminalView(...))` and add the bar as the last child so it sits above the soft keyboard.)

- [ ] **Step 5: Run tests + analyze**

Run: `cd app && flutter test test/mobile/ && flutter analyze lib/mobile`
Expected: PASS; `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add app/lib/mobile/terminal/accessory_key_bar.dart app/lib/mobile/screens/mobile_sessions_screen.dart app/test/mobile/accessory_key_bar_test.dart
git commit -m "feat(mobile): accessory key bar wired to terminal"
```

---

### Task 8: Pinch-to-zoom terminal font

**Files:**
- Modify: `app/lib/mobile/screens/mobile_sessions_screen.dart`
- Test: manual (gesture-driven; covered by analyze + on-device check)

**Interfaces:**
- Produces: a `GestureDetector` (scale) around the `TerminalView` that adjusts a local `_fontSize` (clamped 8–28) and passes `TerminalView(..., textStyle: TerminalStyle(fontSize: _fontSize))`.

- [ ] **Step 1: Add pinch-zoom state**

In `_MobileSessionsScreenState`, add `double _fontSize = 14;` and a scale gesture:
```dart
GestureDetector(
  onScaleStart: (_) => _scaleBase = _fontSize,
  onScaleUpdate: (d) {
    if (d.scale == 1.0) return;
    setState(() => _fontSize = (_scaleBase * d.scale).clamp(8.0, 28.0));
  },
  child: TerminalView(
    session.terminal,
    textStyle: TerminalStyle(fontSize: _fontSize),
  ),
)
```
(Add `double _scaleBase = 14;`.)

- [ ] **Step 2: Analyze + full mobile tests**

Run: `cd app && flutter analyze lib/mobile && flutter test test/mobile/`
Expected: `No issues found!`; tests PASS.

- [ ] **Step 3: Commit**

```bash
git add app/lib/mobile/screens/mobile_sessions_screen.dart
git commit -m "feat(mobile): pinch-to-zoom terminal font"
```

---

### Task 9: Build, regression, on-device check

**Files:** none (verification)

- [ ] **Step 1: Full test suite (desktop regression)**

Run: `cd app && flutter test`
Expected: all tests pass (desktop unaffected; mobile tests added).

- [ ] **Step 2: Analyze whole repo**

Run: `cd app && flutter analyze`
Expected: no NEW issues (the 2 pre-existing `integration_test` probe warnings may remain).

- [ ] **Step 3: Build the APK**

Run: `cd app && flutter build apk --debug`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 4: On-device (user, when a device/emulator is available)**

```
cd app && flutter run -d <android>
```
Manual checklist: add a host → tap → Sessions tab shows it connecting → on connect the terminal renders → type with the soft keyboard → Esc/Ctrl+C/arrows from the accessory bar work → pinch zoom resizes the font.

---

## Self-Review

**Spec coverage (M2 portion):**
- "Hosts list + detail + connect" → Tasks 2, 3, 5. ✓
- "mobile TerminalView" → Task 4. ✓
- "accessory key bar (sticky Ctrl/Alt)" → Tasks 6, 7. ✓
- "multi-session strip" → Task 4 (`_SessionStrip`). ✓
- "pinch-zoom" → Task 8. ✓
- "shared provider bootstrap" → Task 1 (mobile-scoped reuse of the existing classes; desktop bootstrap untouched — documented refinement). ✓

**Placeholder scan:** No "TBD/handle errors" steps; code is complete. The three `> Verify at execution` notes name a concrete fallback each (provider export, `SshKeyEntry` field names, `TerminalKey` member names) — verification instructions, not placeholders.

**Type consistency:** `MobileBootstrap` field/getter names (Task 1) match their use. `MobileHostsScreen(onConnected, onAddHost)` (Task 2) matches the shell wiring (Task 5). `AccessoryBarController.armCtrl/armAlt/consumeModifiers/ctrlArmed/altArmed` (Task 6) match the bar widget (Task 7). `onKey(TerminalKey, {ctrl, alt})` / `onText(String)` consistent across Tasks 7–8 and the terminal wiring.

## Deferred to later milestones

- TOFU **mismatch** challenge dialog → M5 (first-connect auto-trusts in M2).
- Host edit/delete, tags, proxy, jump-chain, RDP/VNC host forms → not on mobile v1 / later.
- Snippets + command-history insert → M4.
- SFTP → M4. Settings (appearance, app-lock) → M5.
