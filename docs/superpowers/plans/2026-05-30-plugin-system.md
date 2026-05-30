# Plugin System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a pub.dev-compatible plugin system for YourSSH, extract the DevOps Hub as the first installable plugin, and add a Plugin Marketplace screen.

**Architecture:** A `yourssh_plugin_api` Flutter package defines the `YourSSHPlugin` abstract interface and `YourSSHPluginContext`. A `yourssh_devops` package implements this interface and ships the DevOps Hub screens. The app has a single `plugin_registry.dart` file that lists installed plugins; `PluginProvider` manages enabled/disabled state persisted to SharedPreferences. SSH-dependent DevOps screens (Cloudflare, MCP, Mail Catcher, Network Tools) are passed as widget slots via `DevOpsPluginConfig` to avoid circular dependencies between the app and the plugin package.

**Tech Stack:** Flutter/Dart, provider ^6.1.2, shared_preferences ^2.3.2, monorepo path dependencies

---

## File Map

### New files — `packages/yourssh_plugin_api/`
| File | Responsibility |
|---|---|
| `pubspec.yaml` | Package manifest, depends on `flutter` SDK only |
| `lib/yourssh_plugin_api.dart` | Barrel export |
| `lib/src/plugin.dart` | `YourSSHPlugin` abstract class |
| `lib/src/plugin_context.dart` | `YourSSHPluginContext` abstract class |
| `lib/src/ssh_session_proxy.dart` | `SSHSessionProxy` data class |
| `lib/src/plugin_ssh_exception.dart` | `PluginSSHException` |

### New files — `packages/yourssh_devops/`
| File | Responsibility |
|---|---|
| `pubspec.yaml` | Package manifest |
| `lib/yourssh_devops.dart` | Barrel export |
| `lib/src/devops_plugin.dart` | `YourSSHDevOpsPlugin` implements `YourSSHPlugin` |
| `lib/src/devops_plugin_config.dart` | `DevOpsPluginConfig` (widget slots for SSH-dependent screens) |
| `lib/src/screens/devops_hub_screen.dart` | Hub container + sub-nav (moved from app, accepts config) |
| `lib/src/screens/s3_browser_screen.dart` | Moved from `app/lib/widgets/` |
| `lib/src/screens/lan_share_screen.dart` | Moved from `app/lib/widgets/` |
| `lib/src/services/s3_service.dart` | Moved from `app/lib/services/` |
| `lib/src/services/lan_share_service.dart` | Moved from `app/lib/services/` |
| `lib/src/models/s3_bucket_config.dart` | Moved from `app/lib/models/` |
| `lib/src/models/s3_bucket_entry.dart` | Moved from `app/lib/models/` |

### New files — `app/lib/`
| File | Responsibility |
|---|---|
| `plugins/plugin_registry.dart` | Single file listing `kRegisteredPlugins` |
| `plugins/plugin_context_impl.dart` | `PluginContextImpl` implements `YourSSHPluginContext` |
| `providers/plugin_provider.dart` | Enabled state, `List<YourSSHPlugin> enabledPlugins` |
| `widgets/plugin_marketplace_screen.dart` | List + toggle all registered plugins |

### Modified files — `app/`
| File | Change |
|---|---|
| `pubspec.yaml` | Add path deps: `yourssh_plugin_api`, `yourssh_devops` |
| `lib/main.dart` | Add `PluginProvider` to `MultiProvider` |
| `lib/screens/main_screen.dart` | Remove `NavSection.devOps`; add dynamic plugin nav + content; add Plugins nav item |
| `lib/providers/settings_provider.dart` | Remove `showDevOps` field, prefs key, save param |
| `lib/widgets/settings_screen.dart` | Remove DevOps toggle |

### Deleted files — `app/`
- `lib/widgets/devops_hub_screen.dart`
- `lib/widgets/s3_browser_screen.dart`
- `lib/widgets/lan_share_screen.dart`
- `lib/models/s3_bucket_config.dart`
- `lib/models/s3_bucket_entry.dart`
- `lib/services/s3_service.dart`
- `lib/services/lan_share_service.dart`

---

## Task 1: Create `yourssh_plugin_api` package

**Files:**
- Create: `packages/yourssh_plugin_api/pubspec.yaml`
- Create: `packages/yourssh_plugin_api/lib/yourssh_plugin_api.dart`
- Create: `packages/yourssh_plugin_api/lib/src/ssh_session_proxy.dart`
- Create: `packages/yourssh_plugin_api/lib/src/plugin_ssh_exception.dart`
- Create: `packages/yourssh_plugin_api/lib/src/plugin_context.dart`
- Create: `packages/yourssh_plugin_api/lib/src/plugin.dart`

- [ ] **Step 1: Create package directory + pubspec**

```bash
mkdir -p packages/yourssh_plugin_api/lib/src
```

`packages/yourssh_plugin_api/pubspec.yaml`:
```yaml
name: yourssh_plugin_api
description: Public plugin API for YourSSH — implement YourSSHPlugin to build tools.
version: 1.0.0
publish_to: none

environment:
  sdk: ^3.12.0

dependencies:
  flutter:
    sdk: flutter
```

- [ ] **Step 2: Create `SSHSessionProxy`**

`packages/yourssh_plugin_api/lib/src/ssh_session_proxy.dart`:
```dart
class SSHSessionProxy {
  final String sessionId;
  final String hostLabel;
  final bool isConnected;

  const SSHSessionProxy({
    required this.sessionId,
    required this.hostLabel,
    required this.isConnected,
  });
}
```

- [ ] **Step 3: Create `PluginSSHException`**

`packages/yourssh_plugin_api/lib/src/plugin_ssh_exception.dart`:
```dart
class PluginSSHException implements Exception {
  final String message;
  const PluginSSHException(this.message);

  @override
  String toString() => 'PluginSSHException: $message';
}
```

- [ ] **Step 4: Create `YourSSHPluginContext`**

`packages/yourssh_plugin_api/lib/src/plugin_context.dart`:
```dart
import 'ssh_session_proxy.dart';

abstract class YourSSHPluginContext {
  List<SSHSessionProxy> get activeSessions;

  /// Runs [command] on the given session. Throws [PluginSSHException] on failure.
  Future<String> execCommand(String sessionId, String command);

  /// Preferences are auto-namespaced by plugin ID.
  Future<void> savePreference(String key, String value);
  Future<String?> getPreference(String key);
}
```

- [ ] **Step 5: Create `YourSSHPlugin`**

`packages/yourssh_plugin_api/lib/src/plugin.dart`:
```dart
import 'package:flutter/material.dart';
import 'plugin_context.dart';

abstract class YourSSHPlugin {
  /// Reverse-domain unique ID, e.g. "dev.yourssh.devops"
  String get id;
  String get name;
  String get description;
  IconData get icon;
  String get version;

  /// Minimum yourssh_plugin_api version required, e.g. "1.0.0"
  String get minApiVersion;

  Widget buildUI(BuildContext context, YourSSHPluginContext pluginContext);

  void onActivate(YourSSHPluginContext ctx) {}
  void onDeactivate() {}
}
```

- [ ] **Step 6: Create barrel export**

`packages/yourssh_plugin_api/lib/yourssh_plugin_api.dart`:
```dart
export 'src/plugin.dart';
export 'src/plugin_context.dart';
export 'src/ssh_session_proxy.dart';
export 'src/plugin_ssh_exception.dart';
```

- [ ] **Step 7: Verify package resolves**

```bash
cd packages/yourssh_plugin_api && flutter pub get
```

Expected: `Got dependencies!`

- [ ] **Step 8: Commit**

```bash
git add packages/yourssh_plugin_api
git commit -m "feat: add yourssh_plugin_api package with plugin interface"
```

---

## Task 2: Create `PluginProvider` + `plugin_registry.dart` in app

**Files:**
- Create: `app/lib/providers/plugin_provider.dart`
- Create: `app/lib/plugins/plugin_registry.dart`
- Create: `app/lib/plugins/plugin_context_impl.dart`
- Modify: `app/pubspec.yaml`
- Create: `app/test/providers/plugin_provider_test.dart`

- [ ] **Step 1: Add `yourssh_plugin_api` dep to app pubspec**

In `app/pubspec.yaml`, add under `dependencies:` (after `http: ^1.2.0`):
```yaml
  # Plugin system
  yourssh_plugin_api:
    path: ../packages/yourssh_plugin_api
```

- [ ] **Step 2: Run pub get**

```bash
cd app && flutter pub get
```

Expected: `Got dependencies!`

- [ ] **Step 3: Write failing test for PluginProvider**

Create `app/test/providers/plugin_provider_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/plugin_provider.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'package:flutter/material.dart';

class _FakePlugin extends YourSSHPlugin {
  @override String get id => 'test.fake';
  @override String get name => 'Fake';
  @override String get description => 'A fake plugin';
  @override IconData get icon => Icons.star;
  @override String get version => '1.0.0';
  @override String get minApiVersion => '1.0.0';
  @override Widget buildUI(BuildContext context, YourSSHPluginContext ctx) => const SizedBox();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('plugin disabled by default', () async {
    final provider = PluginProvider(plugins: [_FakePlugin()]);
    await provider.loadFromPrefs();
    expect(provider.isEnabled('test.fake'), false);
    expect(provider.enabledPlugins, isEmpty);
  });

  test('toggle enables plugin', () async {
    final provider = PluginProvider(plugins: [_FakePlugin()]);
    await provider.loadFromPrefs();
    await provider.toggle('test.fake');
    expect(provider.isEnabled('test.fake'), true);
    expect(provider.enabledPlugins, hasLength(1));
  });

  test('toggle twice disables plugin', () async {
    final provider = PluginProvider(plugins: [_FakePlugin()]);
    await provider.loadFromPrefs();
    await provider.toggle('test.fake');
    await provider.toggle('test.fake');
    expect(provider.isEnabled('test.fake'), false);
  });

  test('enabled state persists across instances', () async {
    final p1 = PluginProvider(plugins: [_FakePlugin()]);
    await p1.loadFromPrefs();
    await p1.toggle('test.fake');

    final p2 = PluginProvider(plugins: [_FakePlugin()]);
    await p2.loadFromPrefs();
    expect(p2.isEnabled('test.fake'), true);
  });
}
```

- [ ] **Step 4: Run test — expect FAIL**

```bash
cd app && flutter test test/providers/plugin_provider_test.dart
```

Expected: FAIL — `PluginProvider` not found.

- [ ] **Step 5: Create `PluginProvider`**

Create `app/lib/providers/plugin_provider.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';

class PluginProvider extends ChangeNotifier {
  final List<YourSSHPlugin> plugins;
  Set<String> _enabledIds = {};

  PluginProvider({required this.plugins});

  List<YourSSHPlugin> get enabledPlugins =>
      plugins.where((p) => _enabledIds.contains(p.id)).toList();

  bool isEnabled(String pluginId) => _enabledIds.contains(pluginId);

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('enabled_plugins') ?? [];
    _enabledIds = saved.toSet();
    notifyListeners();
  }

  Future<void> toggle(String pluginId) async {
    _enabledIds.contains(pluginId)
        ? _enabledIds.remove(pluginId)
        : _enabledIds.add(pluginId);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('enabled_plugins', _enabledIds.toList());
  }
}
```

- [ ] **Step 6: Run test — expect PASS**

```bash
cd app && flutter test test/providers/plugin_provider_test.dart
```

Expected: All 4 tests pass.

- [ ] **Step 7: Create `PluginContextImpl`**

Create `app/lib/plugins/plugin_context_impl.dart`:
```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import '../providers/session_provider.dart';
import '../services/ssh_service.dart';

class PluginContextImpl implements YourSSHPluginContext {
  final SessionProvider _sessions;
  final SshService _ssh;
  final String _pluginId;

  PluginContextImpl({
    required SessionProvider sessions,
    required SshService ssh,
    required String pluginId,
  })  : _sessions = sessions,
        _ssh = ssh,
        _pluginId = pluginId;

  @override
  List<SSHSessionProxy> get activeSessions => _sessions.sessions
      .map((s) => SSHSessionProxy(
            sessionId: s.id,
            hostLabel: '${s.host.username}@${s.host.host}',
            isConnected: s.isConnected,
          ))
      .toList();

  @override
  Future<String> execCommand(String sessionId, String command) async {
    try {
      return await _ssh.execCommand(sessionId, command);
    } catch (e) {
      throw PluginSSHException('execCommand failed: $e');
    }
  }

  @override
  Future<void> savePreference(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plugin_${_pluginId}_$key', value);
  }

  @override
  Future<String?> getPreference(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('plugin_${_pluginId}_$key');
  }
}
```

- [ ] **Step 8: Create `plugin_registry.dart`**

Create `app/lib/plugins/plugin_registry.dart`:
```dart
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';

// Add imports for installed plugins here:
// import 'package:yourssh_devops/yourssh_devops.dart';

/// All plugins compiled into this build.
/// To add a plugin: add it to pubspec.yaml, import it above, and add an instance here.
final List<YourSSHPlugin> kRegisteredPlugins = [
  // YourSSHDevOpsPlugin(),  ← will be uncommented in Task 7
];
```

- [ ] **Step 9: Commit**

```bash
git add app/lib/providers/plugin_provider.dart app/lib/plugins/ app/test/providers/plugin_provider_test.dart app/pubspec.yaml
git commit -m "feat: add PluginProvider, plugin_registry, and PluginContextImpl"
```

---

## Task 3: Create Plugin Marketplace screen

**Files:**
- Create: `app/lib/widgets/plugin_marketplace_screen.dart`

- [ ] **Step 1: Create the screen**

Create `app/lib/widgets/plugin_marketplace_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import '../providers/plugin_provider.dart';
import '../theme/app_theme.dart';

class PluginMarketplaceScreen extends StatelessWidget {
  const PluginMarketplaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pluginProvider = context.watch<PluginProvider>();
    final plugins = pluginProvider.plugins;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text(
            'Plugins',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Text(
            'Installed plugins. Add plugins by editing plugin_registry.dart and rebuilding.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        if (plugins.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No plugins installed.',
              style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: plugins.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, i) =>
                  _PluginTile(plugin: plugins[i]),
            ),
          ),
      ],
    );
  }
}

class _PluginTile extends StatelessWidget {
  final YourSSHPlugin plugin;
  const _PluginTile({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final pluginProvider = context.watch<PluginProvider>();
    final enabled = pluginProvider.isEnabled(plugin.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(plugin.icon, color: AppColors.accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      plugin.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'v${plugin.version}',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  plugin.description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: (_) => pluginProvider.toggle(plugin.id),
            activeColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify no analysis errors**

```bash
cd app && flutter analyze lib/widgets/plugin_marketplace_screen.dart
```

Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/plugin_marketplace_screen.dart
git commit -m "feat: add Plugin Marketplace screen"
```

---

## Task 4: Wire plugin system into MainScreen + SettingsProvider

**Files:**
- Modify: `app/lib/main.dart`
- Modify: `app/lib/screens/main_screen.dart`
- Modify: `app/lib/providers/settings_provider.dart`
- Modify: `app/lib/widgets/settings_screen.dart`

- [ ] **Step 1: Add PluginProvider to `main.dart`**

In `app/lib/main.dart`, add imports after the existing provider imports:
```dart
import 'plugins/plugin_registry.dart';
import 'providers/plugin_provider.dart';
```

In `_YourSSHAppState`, add a field:
```dart
late final PluginProvider _pluginProvider;
```

In `initState()`, after `_knownHostsProvider`:
```dart
_pluginProvider = PluginProvider(plugins: kRegisteredPlugins);
_pluginProvider.loadFromPrefs();
```

In `dispose()`, add:
```dart
_pluginProvider.dispose();
```

In `MultiProvider`, add after the last `ChangeNotifierProvider`:
```dart
ChangeNotifierProvider.value(value: _pluginProvider),
```

- [ ] **Step 2: Remove `showDevOps` from `SettingsProvider`**

In `app/lib/providers/settings_provider.dart`:

Remove the field:
```dart
bool showDevOps = false;
```

Remove the load line:
```dart
showDevOps = prefs.getBool('showDevOps') ?? false;
```

Remove from `save()` signature `bool? showDevOps,` and body:
```dart
if (showDevOps != null) this.showDevOps = showDevOps;
...
await prefs.setBool('showDevOps', this.showDevOps);
```

- [ ] **Step 3: Update `settings_screen.dart`**

Search for the DevOps toggle in `app/lib/widgets/settings_screen.dart` and remove it. The toggle will typically look like:
```dart
// Remove any row/switch that references showDevOps or 'DevOps' section toggle
```

Run:
```bash
cd app && grep -n "DevOps\|showDevOps" lib/widgets/settings_screen.dart
```

Remove the identified lines.

- [ ] **Step 4: Update `NavSection` enum in `main_screen.dart`**

Change:
```dart
enum NavSection { hosts, keychain, portForwarding, sftp, webTools, devOps, snippets, localTerminal, knownHosts, settings }
```
To:
```dart
enum NavSection { hosts, keychain, portForwarding, sftp, webTools, snippets, localTerminal, knownHosts, settings, plugins }
```

(`devOps` removed, `plugins` added for Plugin Marketplace nav item)

- [ ] **Step 5: Add `_activePluginId` to `_MainScreenState`**

In `_MainScreenState`, add:
```dart
String? _activePluginId;
```

- [ ] **Step 6: Update `_buildContent` to handle plugins**

Remove the `hiddenNav` block that references `NavSection.devOps`:
```dart
// Remove this:
final hiddenNav = (_nav == NavSection.devOps && !settings.showDevOps) || ...
```

Replace with (keeping webTools and snippets checks):
```dart
final hiddenNav = (_nav == NavSection.webTools && !settings.showWebTools) ||
    (_nav == NavSection.snippets && !settings.showSnippets);
```

In the `return switch (_nav)` block, remove the `NavSection.devOps` case and add `NavSection.plugins`:
```dart
NavSection.plugins => const PluginMarketplaceScreen(),
```

Add plugin content rendering BEFORE the switch. Replace the `return switch (_nav)` with:

```dart
// Active plugin view
if (_activePluginId != null) {
  final pluginProvider = context.read<PluginProvider>();
  final plugin = pluginProvider.enabledPlugins
      .where((p) => p.id == _activePluginId)
      .firstOrNull;
  if (plugin != null) {
    final ssh = context.read<SshService>();
    final sessions = context.read<SessionProvider>();
    final pluginCtx = PluginContextImpl(
      sessions: sessions,
      ssh: ssh,
      pluginId: plugin.id,
    );
    return _PluginErrorBoundary(
      key: ValueKey(plugin.id),
      child: plugin.buildUI(context, pluginCtx),
    );
  }
  // plugin was disabled while viewing it
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) setState(() => _activePluginId = null);
  });
  return const SizedBox.shrink();
}

return switch (_nav) {
  // ... existing cases without NavSection.devOps
  NavSection.plugins => const PluginMarketplaceScreen(),
  // ...
};
```

Add the necessary imports at the top of `main_screen.dart`:
```dart
import '../plugins/plugin_registry.dart';   // only for context; registry used via provider
import '../plugins/plugin_context_impl.dart';
import '../providers/plugin_provider.dart';
import '../widgets/plugin_marketplace_screen.dart';
import '../services/ssh_service.dart';
```

Remove the now-unused import:
```dart
// Remove: import '../widgets/devops_hub_screen.dart';
```

- [ ] **Step 7: Add `_PluginErrorBoundary` widget**

At the bottom of `main_screen.dart`, add:
```dart
class _PluginErrorBoundary extends StatefulWidget {
  final Widget child;
  const _PluginErrorBoundary({super.key, required this.child});

  @override
  State<_PluginErrorBoundary> createState() => _PluginErrorBoundaryState();
}

class _PluginErrorBoundaryState extends State<_PluginErrorBoundary> {
  Object? _error;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 32),
              const SizedBox(height: 12),
              Text(
                'Plugin crashed: $_error',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return widget.child;
  }

  @override
  void didUpdateWidget(_PluginErrorBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) _error = null;
  }
}
```

- [ ] **Step 8: Update `_Sidebar` to add dynamic plugin nav + Plugins item**

In `_Sidebar.build`, in the TOOLS section, replace:
```dart
if (context.watch<SettingsProvider>().showDevOps)
  _navItem(Icons.rocket_launch_outlined, 'DevOps', NavSection.devOps),
```

With dynamic plugin nav items:
```dart
...context.watch<PluginProvider>().enabledPlugins.map(
  (plugin) => _pluginNavItem(plugin),
),
```

Add `NavSection.plugins` item near the bottom (before Settings):
```dart
_navItem(Icons.extension_outlined, 'Plugins', NavSection.plugins),
```

Note: `_Sidebar` also needs access to `_activePluginId` and a setter. Since `_Sidebar` is a `StatelessWidget` that calls `onSelect`, extend it:

Change `_Sidebar`:
```dart
class _Sidebar extends StatelessWidget {
  final NavSection selected;
  final String? activePluginId;
  final ValueChanged<NavSection> onSelect;
  final ValueChanged<String> onSelectPlugin;
  const _Sidebar({
    required this.selected,
    required this.activePluginId,
    required this.onSelect,
    required this.onSelectPlugin,
  });
```

Add `_pluginNavItem` method:
```dart
Widget _pluginNavItem(YourSSHPlugin plugin) {
  final isActive = activePluginId == plugin.id;
  return _PluginNavItemWidget(
    plugin: plugin,
    isActive: isActive,
    onTap: () => onSelectPlugin(plugin.id),
  );
}
```

Add `_PluginNavItemWidget` (styled like `_navItem`):
```dart
class _PluginNavItemWidget extends StatelessWidget {
  final YourSSHPlugin plugin;
  final bool isActive;
  final VoidCallback onTap;
  const _PluginNavItemWidget({required this.plugin, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? AppColors.accent.withOpacity(0.15) : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isActive ? AppColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(plugin.icon,
                  size: 16,
                  color: isActive ? AppColors.accent : AppColors.textSecondary),
              const SizedBox(width: 10),
              Text(
                plugin.name,
                style: TextStyle(
                  color: isActive ? AppColors.accent : AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Update the `_Sidebar` instantiation in `_MainScreenState.build` to pass the new params and handle `onSelectPlugin`:
```dart
_Sidebar(
  selected: _nav,
  activePluginId: _activePluginId,
  onSelect: (s) {
    setState(() {
      _activePluginId = null;  // clear plugin when switching to a nav section
      // existing logic...
    });
  },
  onSelectPlugin: (id) => setState(() {
    _activePluginId = id;
    _viewingTerminal = false;
  }),
)
```

- [ ] **Step 9: Analyze and fix errors**

```bash
cd app && flutter analyze
```

Fix any remaining type errors. Common ones:
- Missing `SshService` import in `main_screen.dart`
- `firstOrNull` requires `package:collection` or use `cast<>().firstWhere(..., orElse: () => null)` — use `where().isEmpty ? null : where().first`

- [ ] **Step 10: Commit**

```bash
git add app/lib/main.dart app/lib/screens/main_screen.dart app/lib/providers/settings_provider.dart app/lib/widgets/settings_screen.dart
git commit -m "feat: wire plugin system into MainScreen with dynamic nav"
```

---

## Task 5: Create `yourssh_devops` package

**Files:**
- Create: `packages/yourssh_devops/pubspec.yaml`
- Create: `packages/yourssh_devops/lib/yourssh_devops.dart`
- Create: `packages/yourssh_devops/lib/src/devops_plugin_config.dart`
- Create: `packages/yourssh_devops/lib/src/devops_plugin.dart`

- [ ] **Step 1: Create package directory structure**

```bash
mkdir -p packages/yourssh_devops/lib/src/screens
mkdir -p packages/yourssh_devops/lib/src/services
mkdir -p packages/yourssh_devops/lib/src/models
```

- [ ] **Step 2: Create `pubspec.yaml`**

`packages/yourssh_devops/pubspec.yaml`:
```yaml
name: yourssh_devops
description: DevOps Hub plugin for YourSSH — network tools, S3, LAN share, and more.
version: 1.0.0
publish_to: none

environment:
  sdk: ^3.12.0

dependencies:
  flutter:
    sdk: flutter

  yourssh_plugin_api:
    path: ../yourssh_plugin_api

  # S3 browser deps
  http: ^1.2.0
  crypto: ^3.0.3
  xml: ^6.5.0
  path: ^1.9.0

  # LAN share deps
  network_info_plus: ^6.0.0
  shelf: ^1.4.1

  # UI deps
  file_picker: ^8.1.2
  flutter_secure_storage: ^9.2.2
  url_launcher: ^6.3.0

  provider: ^6.1.2
```

- [ ] **Step 3: Run pub get for the package**

```bash
cd packages/yourssh_devops && flutter pub get
```

Expected: `Got dependencies!`

- [ ] **Step 4: Create `DevOpsPluginConfig`**

`packages/yourssh_devops/lib/src/devops_plugin_config.dart`:
```dart
import 'package:flutter/material.dart';

/// Widget slots for DevOps sub-screens that depend on app-level providers
/// (SessionProvider, SshService, TunnelProvider). Passed from the app so
/// the yourssh_devops package stays free of circular dependencies.
class DevOpsPluginConfig {
  final Widget networkToolsScreen;
  final Widget cloudflareScreen;
  final Widget mailCatcherScreen;
  final Widget mcpServerScreen;

  const DevOpsPluginConfig({
    required this.networkToolsScreen,
    required this.cloudflareScreen,
    required this.mailCatcherScreen,
    required this.mcpServerScreen,
  });
}
```

- [ ] **Step 5: Create `YourSSHDevOpsPlugin`**

`packages/yourssh_devops/lib/src/devops_plugin.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'devops_plugin_config.dart';
import 'screens/devops_hub_screen.dart';

class YourSSHDevOpsPlugin extends YourSSHPlugin {
  final DevOpsPluginConfig config;

  YourSSHDevOpsPlugin({required this.config});

  @override String get id => 'dev.yourssh.devops';
  @override String get name => 'DevOps Hub';
  @override String get description =>
      'Network tools, S3 browser, LAN share, Mail catcher, MCP server, Cloudflare tunnels';
  @override IconData get icon => Icons.rocket_launch_outlined;
  @override String get version => '1.0.0';
  @override String get minApiVersion => '1.0.0';

  @override
  Widget buildUI(BuildContext context, YourSSHPluginContext pluginContext) {
    return DevOpsHubScreen(config: config);
  }
}
```

- [ ] **Step 6: Create barrel export**

`packages/yourssh_devops/lib/yourssh_devops.dart`:
```dart
export 'src/devops_plugin.dart';
export 'src/devops_plugin_config.dart';
```

- [ ] **Step 7: Commit package shell**

```bash
git add packages/yourssh_devops
git commit -m "feat: add yourssh_devops package shell with plugin interface"
```

---

## Task 6: Move self-contained DevOps screens to `yourssh_devops`

**Files to move from app to package:**
- `app/lib/models/s3_bucket_config.dart` → `packages/yourssh_devops/lib/src/models/s3_bucket_config.dart`
- `app/lib/models/s3_bucket_entry.dart` → `packages/yourssh_devops/lib/src/models/s3_bucket_entry.dart`
- `app/lib/services/s3_service.dart` → `packages/yourssh_devops/lib/src/services/s3_service.dart`
- `app/lib/services/lan_share_service.dart` → `packages/yourssh_devops/lib/src/services/lan_share_service.dart`
- `app/lib/widgets/s3_browser_screen.dart` → `packages/yourssh_devops/lib/src/screens/s3_browser_screen.dart`
- `app/lib/widgets/lan_share_screen.dart` → `packages/yourssh_devops/lib/src/screens/lan_share_screen.dart`

- [ ] **Step 1: Copy models**

```bash
cp app/lib/models/s3_bucket_config.dart packages/yourssh_devops/lib/src/models/
cp app/lib/models/s3_bucket_entry.dart packages/yourssh_devops/lib/src/models/
```

Update imports in both files: remove `../` relative paths (none expected — these are pure data classes). Verify with:
```bash
head -5 packages/yourssh_devops/lib/src/models/s3_bucket_config.dart
```

- [ ] **Step 2: Copy S3 service**

```bash
cp app/lib/services/s3_service.dart packages/yourssh_devops/lib/src/services/
```

Update imports in `packages/yourssh_devops/lib/src/services/s3_service.dart`:
- Change `import '../models/s3_bucket_config.dart';` → `import '../models/s3_bucket_config.dart';` (same relative path, already correct)
- Change `import '../models/s3_bucket_entry.dart';` → `import '../models/s3_bucket_entry.dart';` (same)

- [ ] **Step 3: Copy LAN share service**

```bash
cp app/lib/services/lan_share_service.dart packages/yourssh_devops/lib/src/services/
```

Check imports — this file should only import `dart:*` and `shelf`. Update if needed:
```bash
head -10 packages/yourssh_devops/lib/src/services/lan_share_service.dart
```

- [ ] **Step 4: Copy S3 browser screen**

```bash
cp app/lib/widgets/s3_browser_screen.dart packages/yourssh_devops/lib/src/screens/
```

Update imports in `packages/yourssh_devops/lib/src/screens/s3_browser_screen.dart`:
```dart
// Change:
import '../models/s3_bucket_config.dart';
import '../models/s3_bucket_entry.dart';
import '../services/s3_service.dart';
// To:
import '../models/s3_bucket_config.dart';
import '../models/s3_bucket_entry.dart';
import '../services/s3_service.dart';
```

Also update any `../theme/app_theme.dart` → needs to be removed or the theme needs to be passed in. Check:
```bash
grep "app_theme\|AppColors" packages/yourssh_devops/lib/src/screens/s3_browser_screen.dart | head -5
```

If `AppColors` is used, add a dependency on the app's theme. Since `yourssh_devops` can't import from `app`, we need to inline the colors or pass them. **Simplest fix:** duplicate the minimal colors needed, or use hardcoded `Color` values matching `AppColors`. Look at what's used:
```bash
grep "AppColors\." packages/yourssh_devops/lib/src/screens/s3_browser_screen.dart | sort -u
```

Create `packages/yourssh_devops/lib/src/theme.dart` with re-exports of the colors used:
```dart
import 'package:flutter/material.dart';

// Mirror of app's AppColors — keep in sync with app/lib/theme/app_theme.dart
abstract final class DevOpsColors {
  static const Color background = Color(0xFF1E1E2E);
  static const Color surface = Color(0xFF2A2A3E);
  static const Color sidebar = Color(0xFF252535);
  static const Color border = Color(0xFF3A3A4E);
  static const Color accent = Color(0xFF7C3AED);
  static const Color textPrimary = Color(0xFFE2E8F0);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textTertiary = Color(0xFF64748B);
}
```

Replace `AppColors.X` with `DevOpsColors.X` throughout the moved files.

- [ ] **Step 5: Copy LAN share screen**

```bash
cp app/lib/widgets/lan_share_screen.dart packages/yourssh_devops/lib/src/screens/
```

Same import update process as Step 4: fix `../services/lan_share_service.dart` and replace `AppColors` with `DevOpsColors`.

- [ ] **Step 6: Analyze the package**

```bash
cd packages/yourssh_devops && flutter analyze
```

Fix all reported issues before continuing.

- [ ] **Step 7: Create `DevOpsHubScreen` in the package**

Create `packages/yourssh_devops/lib/src/screens/devops_hub_screen.dart`:
```dart
import 'package:flutter/material.dart';
import '../devops_plugin_config.dart';
import '../theme.dart';
import 's3_browser_screen.dart';
import 'lan_share_screen.dart';

enum _DevOpsTool { networkTools, cloudflare, lanShare, mailCatcher, mcpServer, s3Browser }

class DevOpsHubScreen extends StatefulWidget {
  final DevOpsPluginConfig config;
  const DevOpsHubScreen({super.key, required this.config});

  @override
  State<DevOpsHubScreen> createState() => _DevOpsHubScreenState();
}

class _DevOpsHubScreenState extends State<DevOpsHubScreen> {
  _DevOpsTool _active = _DevOpsTool.networkTools;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SubNav(active: _active, onSelect: (t) => setState(() => _active = t)),
        Container(width: 1, color: DevOpsColors.border),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() => switch (_active) {
        _DevOpsTool.networkTools => widget.config.networkToolsScreen,
        _DevOpsTool.cloudflare  => widget.config.cloudflareScreen,
        _DevOpsTool.lanShare    => const LanShareScreen(),
        _DevOpsTool.mailCatcher => widget.config.mailCatcherScreen,
        _DevOpsTool.mcpServer   => widget.config.mcpServerScreen,
        _DevOpsTool.s3Browser   => const S3BrowserScreen(),
      };
}

class _SubNav extends StatelessWidget {
  final _DevOpsTool active;
  final ValueChanged<_DevOpsTool> onSelect;

  const _SubNav({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      color: DevOpsColors.sidebar,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'DevOps',
              style: const TextStyle(
                color: DevOpsColors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          _item(_DevOpsTool.networkTools, Icons.network_check, 'Network Tools'),
          _item(_DevOpsTool.cloudflare, Icons.cloud_outlined, 'Cloudflare'),
          _item(_DevOpsTool.lanShare, Icons.share_outlined, 'LAN Share'),
          _item(_DevOpsTool.mailCatcher, Icons.email_outlined, 'Mail Catcher'),
          _item(_DevOpsTool.mcpServer, Icons.hub_outlined, 'MCP Server'),
          _item(_DevOpsTool.s3Browser, Icons.storage_outlined, 'S3 Browser'),
        ],
      ),
    );
  }

  Widget _item(_DevOpsTool tool, IconData icon, String label) {
    final isActive = active == tool;
    return InkWell(
      onTap: () => onSelect(tool),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? DevOpsColors.accent.withOpacity(0.12) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isActive ? DevOpsColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 15,
                color: isActive ? DevOpsColors.accent : DevOpsColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? DevOpsColors.accent : DevOpsColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Analyze package again**

```bash
cd packages/yourssh_devops && flutter analyze
```

Expected: No issues.

- [ ] **Step 9: Commit**

```bash
git add packages/yourssh_devops
git commit -m "feat: move S3 and LAN Share screens into yourssh_devops package"
```

---

## Task 7: Register DevOps plugin in the app + delete migrated files

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/plugins/plugin_registry.dart`
- Delete: moved files from `app/lib/`

- [ ] **Step 1: Add `yourssh_devops` dep to app pubspec**

In `app/pubspec.yaml`, under the `yourssh_plugin_api` dep add:
```yaml
  yourssh_devops:
    path: ../packages/yourssh_devops
```

- [ ] **Step 2: Run pub get**

```bash
cd app && flutter pub get
```

Expected: `Got dependencies!`

- [ ] **Step 3: Update `plugin_registry.dart` to register the plugin**

`app/lib/plugins/plugin_registry.dart`:
```dart
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'package:yourssh_devops/yourssh_devops.dart';
import 'package:flutter/material.dart';
import '../widgets/devops_tools_screen.dart';
import '../widgets/cloudflare_tunnel_screen.dart';
import '../widgets/mail_catcher_screen.dart';
import '../widgets/mcp_server_screen.dart';

/// All plugins compiled into this build.
/// To add a plugin: add it to pubspec.yaml, import it above, and add an instance here.
final List<YourSSHPlugin> kRegisteredPlugins = [
  YourSSHDevOpsPlugin(
    config: DevOpsPluginConfig(
      networkToolsScreen: const DevopsToolsScreen(),
      cloudflareScreen: const CloudflareTunnelScreen(),
      mailCatcherScreen: const MailCatcherScreen(),
      mcpServerScreen: const McpServerScreen(),
    ),
  ),
];
```

- [ ] **Step 4: Delete migrated files from app**

```bash
rm app/lib/widgets/devops_hub_screen.dart
rm app/lib/widgets/s3_browser_screen.dart
rm app/lib/widgets/lan_share_screen.dart
rm app/lib/models/s3_bucket_config.dart
rm app/lib/models/s3_bucket_entry.dart
rm app/lib/services/s3_service.dart
rm app/lib/services/lan_share_service.dart
```

- [ ] **Step 5: Full analysis**

```bash
cd app && flutter analyze
```

Fix any import errors (likely remaining references to deleted files in other screens — check `devops_tools_screen.dart` for any s3/lan imports; there should be none).

- [ ] **Step 6: Run tests**

```bash
cd app && flutter test
```

Expected: All tests pass.

- [ ] **Step 7: Run the app and verify**

```bash
cd app && flutter run -d macos
```

Verify:
- Sidebar shows no "DevOps" nav item (plugin starts disabled)
- "Plugins" nav item is visible
- Plugin Marketplace shows "DevOps Hub" with a toggle
- Toggling ON → "DevOps Hub" appears in sidebar
- Clicking DevOps Hub → shows the hub with all 6 sub-tools working
- Toggling OFF → nav item disappears

- [ ] **Step 8: Commit**

```bash
git add app/lib/plugins/plugin_registry.dart app/pubspec.yaml
git commit -m "feat: register YourSSHDevOpsPlugin; remove migrated files from app"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] `yourssh_plugin_api` package with `YourSSHPlugin`, `YourSSHPluginContext`, `SSHSessionProxy`, `PluginSSHException` — Task 1
- [x] `PluginProvider` managing enabled/disabled state — Task 2
- [x] `plugin_registry.dart` single file for adding plugins — Task 2
- [x] `PluginContextImpl` wiring `SshService` + `SessionProvider` — Task 2
- [x] Plugin Marketplace screen with toggle — Task 3
- [x] Dynamic plugin nav items in sidebar — Task 4
- [x] `NavSection.devOps` removed — Task 4
- [x] `showDevOps` removed from `SettingsProvider` — Task 4
- [x] Error boundary around plugin `buildUI` — Task 4
- [x] `yourssh_devops` package created — Tasks 5–6
- [x] `DevOpsPluginConfig` for SSH-dependent screen slots — Tasks 5–7
- [x] S3 + LAN Share moved to package — Task 6
- [x] Plugin registered in app — Task 7
- [x] `minApiVersion` field defined — Task 1 (`YourSSHPlugin.minApiVersion`)

**Not in scope (per spec):** Web Tools extraction, runtime install, plugin sandboxing, plugin-to-plugin communication.
