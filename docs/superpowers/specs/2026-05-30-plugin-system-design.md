# Plugin System Design

**Date:** 2026-05-30
**Status:** Approved
**Scope:** `yourssh_plugin_api` public package + `yourssh_devops` bundled plugin + Plugin Marketplace UI

---

## Overview

Add a compile-time plugin system to YourSSH so that third-party developers can build and distribute tools as Dart/Flutter packages. Plugins register a UI panel, can access active SSH sessions (via a safe proxy), and persist their own preferences. The DevOps Hub is extracted as the first example plugin (`yourssh_devops`).

---

## Architecture

### Repo structure

```
yourssh/
├── app/                          # Flutter app
│   ├── lib/
│   │   ├── plugins/
│   │   │   ├── plugin_registry.dart        # single file to edit when adding a plugin
│   │   │   └── plugin_context_impl.dart    # implements YourSSHPluginContext
│   │   ├── widgets/
│   │   │   └── plugin_marketplace_screen.dart
│   │   └── providers/
│   │       └── plugin_provider.dart
│   └── pubspec.yaml
│
└── packages/
    ├── yourssh_plugin_api/       # published to pub.dev — stable public API
    │   └── lib/src/
    │       ├── plugin.dart
    │       ├── plugin_context.dart
    │       └── ssh_session_proxy.dart
    │
    └── yourssh_devops/           # bundled plugin: DevOps Hub
        ├── lib/
        │   ├── yourssh_devops.dart
        │   └── src/
        │       ├── devops_plugin.dart
        │       └── screens/      # moved from app/lib/widgets/
        └── pubspec.yaml
```

### Data flow

```
MainScreen
  └── PluginProvider (ChangeNotifier)
        └── kRegisteredPlugins  ← plugin_registry.dart
              └── YourSSHPlugin.buildUI(ctx, pluginContext)
                    └── YourSSHPluginContext (impl in plugin_context_impl.dart)
                          ├── SshService  (exec, session list)
                          └── SharedPreferences (namespaced by pluginId)
```

---

## Package: `yourssh_plugin_api`

Published to pub.dev. Third-party plugins depend on this, not on the app itself.

### `YourSSHPlugin` (abstract class)

```dart
abstract class YourSSHPlugin {
  String get id;            // reverse-domain unique ID, e.g. "com.example.my_tool"
  String get name;
  String get description;
  IconData get icon;
  String get version;
  String get minApiVersion; // e.g. "1.0.0" — app checks at load time

  Widget buildUI(BuildContext context, YourSSHPluginContext pluginContext);

  void onActivate(YourSSHPluginContext ctx) {}
  void onDeactivate() {}
}
```

### `YourSSHPluginContext` (abstract class)

```dart
abstract class YourSSHPluginContext {
  List<SSHSessionProxy> get activeSessions;
  Future<String> execCommand(String sessionId, String command);
  Future<void> savePreference(String key, String value);
  Future<String?> getPreference(String key);
}
```

### `SSHSessionProxy`

```dart
class SSHSessionProxy {
  final String sessionId;
  final String hostLabel;   // "user@host"
  final bool isConnected;
}
```

Plugins receive only this proxy — no access to `SSHClient`, raw socket, or other sessions' data.

### Versioning

- Semantic versioning: no breaking changes at minor/patch.
- New methods added with default implementations so existing plugins don't break.
- `minApiVersion` field on plugin; app skips + warns if incompatible.

---

## Package: `yourssh_devops`

Bundled plugin. Contains all code currently in:
- `app/lib/widgets/devops_hub_screen.dart`
- `app/lib/widgets/devops_tools_screen.dart`
- `app/lib/widgets/cloudflare_tunnel_screen.dart`
- `app/lib/widgets/lan_share_screen.dart`
- `app/lib/widgets/mail_catcher_screen.dart`
- `app/lib/widgets/mcp_server_screen.dart`
- `app/lib/widgets/s3_browser_screen.dart`
- `app/lib/services/cloudflare_tunnel_service.dart`
- `app/lib/services/lan_share_service.dart`
- `app/lib/services/mail_catcher_service.dart`
- `app/lib/services/mcp_gateway_service.dart`
- `app/lib/services/s3_service.dart`
- `app/lib/models/s3_bucket_config.dart`
- `app/lib/models/s3_bucket_entry.dart`

`YourSSHDevOpsPlugin` implements `YourSSHPlugin`, returns the `DevOpsHubScreen` from `buildUI()`.

---

## App changes

### `plugin_registry.dart`

The single file a developer edits to add a plugin:

```dart
import 'package:yourssh_devops/yourssh_devops.dart';
// import 'package:third_party_tool/third_party_tool.dart';

final List<YourSSHPlugin> kRegisteredPlugins = [
  YourSSHDevOpsPlugin(),
  // ThirdPartyPlugin(),
];
```

### `PluginProvider`

```dart
class PluginProvider extends ChangeNotifier {
  Set<String> _enabledIds = {};

  List<YourSSHPlugin> get enabledPlugins =>
      kRegisteredPlugins.where((p) => _enabledIds.contains(p.id)).toList();

  bool isEnabled(String pluginId) => _enabledIds.contains(pluginId);

  Future<void> toggle(String pluginId) async { ... } // persists to SharedPreferences
}
```

### `NavSection` migration

Remove `NavSection.devOps`, `NavSection.webTools` from the enum. Plugin nav items are rendered dynamically in `_SideNav`:

```dart
for (final plugin in pluginProvider.enabledPlugins)
  _navItem(plugin.icon, plugin.name, pluginId: plugin.id),
```

Remove `showDevOps` and `showWebTools` booleans from `SettingsProvider` — replaced by `PluginProvider.isEnabled()`.

### Plugin Marketplace screen

Added as a section in Settings. Shows all registered plugins with name, version, description, author, and an enable/disable toggle. Warns if a plugin's `minApiVersion` is incompatible with the installed API version.

---

## Error Handling

- `buildUI()` wrapped in try/catch per plugin; crash shows `_PluginErrorView` for that panel only — app does not crash.
- `execCommand` throws `PluginSSHException` (defined in `yourssh_plugin_api`) instead of raw `dartssh2` exceptions.
- Incompatible `minApiVersion`: plugin is skipped at startup with a log warning; shown as "incompatible" in Marketplace.

---

## What is NOT in scope

- Runtime install without rebuild (not possible in compiled Flutter).
- Plugin sandboxing / code signing.
- Web Tools extraction (separate effort, same pattern).
- Plugin-to-plugin communication.
