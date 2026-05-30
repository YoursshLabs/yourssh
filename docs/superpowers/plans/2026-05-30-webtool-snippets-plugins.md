# WebTools & Snippets Plugin Extraction Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract WebTools and Snippets from the main app into installable plugin packages (`yourssh_web_tools`, `yourssh_snippets`) using the same pattern as `yourssh_devops`.

**Architecture:** Each screen moves to its own package. App-dependent widgets (`PortForwardBrowser`) stay in the app and are injected via a `PluginConfig` widget-builder. `SnippetProvider` stays in the app's MultiProvider tree (still used by `sync_settings_screen.dart`), but the model + provider class + screen move into the package so the app re-exports from there.

**Tech Stack:** Flutter, Dart packages (path deps), `yourssh_plugin_api`, `webview_flutter`, `cryptography`, `shared_preferences`, `uuid`

---

## File Structure

**New packages:**
- `packages/yourssh_web_tools/pubspec.yaml`
- `packages/yourssh_web_tools/lib/yourssh_web_tools.dart` — barrel
- `packages/yourssh_web_tools/lib/src/theme.dart` — `WebToolsColors`
- `packages/yourssh_web_tools/lib/src/web_tools_plugin_config.dart` — `WebToolsPluginConfig`
- `packages/yourssh_web_tools/lib/src/web_tools_plugin.dart` — `YourSSHWebToolsPlugin`
- `packages/yourssh_web_tools/lib/src/screens/web_tools_screen.dart` — moved + adapted hub
- `packages/yourssh_web_tools/lib/src/screens/embedded_browser.dart` — moved
- `packages/yourssh_web_tools/lib/src/screens/http_client.dart` — moved
- `packages/yourssh_web_tools/lib/src/screens/utility_tools.dart` — moved

- `packages/yourssh_snippets/pubspec.yaml`
- `packages/yourssh_snippets/lib/yourssh_snippets.dart` — barrel
- `packages/yourssh_snippets/lib/src/theme.dart` — `SnippetsColors`
- `packages/yourssh_snippets/lib/src/models/snippet.dart` — moved
- `packages/yourssh_snippets/lib/src/providers/snippet_provider.dart` — moved
- `packages/yourssh_snippets/lib/src/screens/snippets_screen.dart` — moved + adapted
- `packages/yourssh_snippets/lib/src/snippets_plugin.dart` — `YourSSHSnippetsPlugin`

**App files deleted after migration:**
- `app/lib/widgets/web_tools_screen.dart`
- `app/lib/widgets/web_tools/embedded_browser.dart`
- `app/lib/widgets/web_tools/http_client.dart`
- `app/lib/widgets/web_tools/utility_tools.dart`
- `app/lib/widgets/snippets_screen.dart`
- `app/lib/models/snippet.dart`
- `app/lib/providers/snippet_provider.dart`

**App files modified:**
- `app/pubspec.yaml` — add `yourssh_web_tools`, `yourssh_snippets` path deps
- `app/lib/plugins/plugin_registry.dart` — register both plugins
- `app/lib/main.dart` — update SnippetProvider import
- `app/lib/widgets/sync_settings_screen.dart` — update SnippetProvider + Snippet imports
- `app/lib/screens/main_screen.dart` — remove `NavSection.webTools`, `NavSection.snippets` and their cases
- `app/lib/providers/settings_provider.dart` — remove `showWebTools`, `showSnippets`
- `app/lib/widgets/settings_screen.dart` — remove Web Tools / Snippets toggles

---

### Task 1: Create `yourssh_web_tools` package skeleton

**Files:**
- Create: `packages/yourssh_web_tools/pubspec.yaml`
- Create: `packages/yourssh_web_tools/lib/src/theme.dart`
- Create: `packages/yourssh_web_tools/lib/src/web_tools_plugin_config.dart`
- Create: `packages/yourssh_web_tools/lib/src/web_tools_plugin.dart`
- Create: `packages/yourssh_web_tools/lib/yourssh_web_tools.dart`

- [ ] **Step 1: Create pubspec.yaml**

```yaml
name: yourssh_web_tools
description: Web Tools plugin for YourSSH — embedded browser, HTTP client, and utilities.
version: 1.0.0
publish_to: none

environment:
  sdk: ^3.12.0

dependencies:
  flutter:
    sdk: flutter

  yourssh_plugin_api:
    path: ../yourssh_plugin_api

  webview_flutter: ^4.8.0
  cryptography: ^2.7.0
```

- [ ] **Step 2: Create `lib/src/theme.dart`**

```dart
import 'package:flutter/material.dart';

abstract final class WebToolsColors {
  static const bg = Color(0xFF0F0F0F);
  static const sidebar = Color(0xFF141414);
  static const card = Color(0xFF1C1C1C);
  static const cardHover = Color(0xFF242424);
  static const border = Color(0xFF2A2A2A);
  static const accent = Color(0xFF22C55E);
  static const accentDim = Color(0xFF16A34A);
  static const textPrimary = Color(0xFFE5E5E5);
  static const textSecondary = Color(0xFF888888);
  static const textTertiary = Color(0xFF555555);
  static const red = Color(0xFFEF4444);
  static const orange = Color(0xFFF97316);
  static const blue = Color(0xFF3B82F6);
}
```

- [ ] **Step 3: Create `lib/src/web_tools_plugin_config.dart`**

`PortForwardBrowser` uses `PortForwardProvider` from the app, so the hub passes a builder instead of a pre-built widget. The builder receives the `onOpenUrl` callback the hub needs to wire cross-tab navigation.

```dart
import 'package:flutter/widgets.dart';

class WebToolsPluginConfig {
  /// Builder for the port-forward browser tab.
  /// Receives [onOpenUrl] so clicking a tunnel opens the Browser tab.
  final Widget Function(void Function(String url) onOpenUrl) portForwardBrowserBuilder;

  const WebToolsPluginConfig({
    required this.portForwardBrowserBuilder,
  });
}
```

- [ ] **Step 4: Create `lib/src/web_tools_plugin.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'screens/web_tools_screen.dart';
import 'web_tools_plugin_config.dart';

class YourSSHWebToolsPlugin extends YourSSHPlugin {
  final WebToolsPluginConfig config;

  YourSSHWebToolsPlugin({required this.config});

  @override
  String get id => 'dev.yourssh.webtools';

  @override
  String get name => 'Web Tools';

  @override
  String get description => 'Embedded browser, HTTP client, and port-forward browser.';

  @override
  IconData get icon => Icons.build_outlined;

  @override
  String get version => '1.0.0';

  @override
  String get minApiVersion => '1.0.0';

  @override
  Widget buildUI(BuildContext context, YourSSHPluginContext pluginContext) {
    return WebToolsScreen(config: config);
  }
}
```

- [ ] **Step 5: Create barrel `lib/yourssh_web_tools.dart`**

```dart
export 'src/web_tools_plugin.dart';
export 'src/web_tools_plugin_config.dart';
export 'src/theme.dart';
```

- [ ] **Step 6: Commit**

```bash
git add packages/yourssh_web_tools/
git commit -m "feat: scaffold yourssh_web_tools plugin package"
```

---

### Task 2: Move WebTools screens into the package

**Files:**
- Create: `packages/yourssh_web_tools/lib/src/screens/embedded_browser.dart`
- Create: `packages/yourssh_web_tools/lib/src/screens/http_client.dart`
- Create: `packages/yourssh_web_tools/lib/src/screens/utility_tools.dart`
- Create: `packages/yourssh_web_tools/lib/src/screens/web_tools_screen.dart`

- [ ] **Step 1: Copy and adapt `embedded_browser.dart`**

Read `app/lib/widgets/web_tools/embedded_browser.dart`. Copy the full content into `packages/yourssh_web_tools/lib/src/screens/embedded_browser.dart`. Change the theme import:

```dart
// OLD:
import '../../theme/app_theme.dart';
// NEW:
import '../theme.dart';
```

Replace every `AppColors.` with `WebToolsColors.`.

- [ ] **Step 2: Copy and adapt `http_client.dart`**

Read `app/lib/widgets/web_tools/http_client.dart`. Copy to `packages/yourssh_web_tools/lib/src/screens/http_client.dart`. Change theme import and replace `AppColors.` with `WebToolsColors.`.

- [ ] **Step 3: Copy and adapt `utility_tools.dart`**

Read `app/lib/widgets/web_tools/utility_tools.dart`. Copy to `packages/yourssh_web_tools/lib/src/screens/utility_tools.dart`. Change theme import and replace `AppColors.` with `WebToolsColors.`.

- [ ] **Step 4: Create `web_tools_screen.dart` (hub) in the package**

This is `app/lib/widgets/web_tools_screen.dart` adapted. Key changes:
- Import from package-local files instead of app paths
- Remove `import 'web_tools/port_forward_browser.dart'`
- Accept `WebToolsPluginConfig config` as constructor param
- Use `config.portForwardBrowserBuilder(_openUrl)` instead of `PortForwardBrowser(onOpenUrl: _openUrl)`
- Replace `AppColors.` with `WebToolsColors.`

```dart
import 'package:flutter/material.dart';
import '../theme.dart';
import '../web_tools_plugin_config.dart';
import 'embedded_browser.dart';
import 'http_client.dart';
import 'utility_tools.dart';

enum _WebTool { browser, http, utilities, portForward }

class WebToolsScreen extends StatefulWidget {
  final WebToolsPluginConfig config;

  const WebToolsScreen({super.key, required this.config});

  @override
  State<WebToolsScreen> createState() => _WebToolsScreenState();
}

class _WebToolsScreenState extends State<WebToolsScreen> {
  _WebTool _active = _WebTool.browser;
  String? _browserUrl;

  void _openUrl(String url) {
    setState(() {
      _browserUrl = url;
      _active = _WebTool.browser;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SubNav(active: _active, onSelect: (t) => setState(() => _active = t)),
        Container(width: 1, color: WebToolsColors.border),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() => switch (_active) {
        _WebTool.browser     => EmbeddedBrowser(key: ValueKey(_browserUrl), initialUrl: _browserUrl),
        _WebTool.http        => const HttpClientTool(),
        _WebTool.utilities   => const UtilityTools(),
        _WebTool.portForward => widget.config.portForwardBrowserBuilder(_openUrl),
      };
}

class _SubNav extends StatelessWidget {
  final _WebTool active;
  final ValueChanged<_WebTool> onSelect;

  const _SubNav({required this.active, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      color: WebToolsColors.sidebar,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Web Tools',
              style: TextStyle(
                color: WebToolsColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          _item(Icons.language, 'Browser', _WebTool.browser),
          _item(Icons.http, 'HTTP Client', _WebTool.http),
          _item(Icons.build_circle_outlined, 'Utilities', _WebTool.utilities),
          _item(Icons.router_outlined, 'Port Tunnels', _WebTool.portForward),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String label, _WebTool tool) {
    final sel = active == tool;
    return _SubNavItem(icon: icon, label: label, selected: sel, onTap: () => onSelect(tool));
  }
}

class _SubNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SubNavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  State<_SubNavItem> createState() => _SubNavItemState();
}

class _SubNavItemState extends State<_SubNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? WebToolsColors.accent.withValues(alpha: 0.12)
        : _hovered
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: widget.selected ? Border.all(color: WebToolsColors.accent.withValues(alpha: 0.2)) : null,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 14,
                  color: widget.selected ? WebToolsColors.accent : WebToolsColors.textSecondary),
              const SizedBox(width: 8),
              Text(widget.label,
                  style: TextStyle(
                    color: widget.selected ? WebToolsColors.accent : WebToolsColors.textSecondary,
                    fontSize: 12,
                    fontWeight: widget.selected ? FontWeight.w500 : FontWeight.normal,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Verify no remaining `AppColors` or app-relative imports in package screens**

```bash
grep -r "AppColors\|app_theme\|\.\.\/\.\.\/theme" packages/yourssh_web_tools/
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add packages/yourssh_web_tools/lib/src/screens/
git commit -m "feat: move WebTools screens into yourssh_web_tools package"
```

---

### Task 3: Create `yourssh_snippets` package

**Files:**
- Create: `packages/yourssh_snippets/pubspec.yaml`
- Create: `packages/yourssh_snippets/lib/src/theme.dart`
- Create: `packages/yourssh_snippets/lib/src/models/snippet.dart`
- Create: `packages/yourssh_snippets/lib/src/providers/snippet_provider.dart`
- Create: `packages/yourssh_snippets/lib/src/screens/snippets_screen.dart`
- Create: `packages/yourssh_snippets/lib/src/snippets_plugin.dart`
- Create: `packages/yourssh_snippets/lib/yourssh_snippets.dart`

- [ ] **Step 1: Create pubspec.yaml**

```yaml
name: yourssh_snippets
description: Snippets plugin for YourSSH — save and recall reusable shell commands.
version: 1.0.0
publish_to: none

environment:
  sdk: ^3.12.0

dependencies:
  flutter:
    sdk: flutter

  yourssh_plugin_api:
    path: ../yourssh_plugin_api

  shared_preferences: ^2.2.2
  uuid: ^4.4.0
  provider: ^6.1.2
```

- [ ] **Step 2: Create `lib/src/theme.dart`**

```dart
import 'package:flutter/material.dart';

abstract final class SnippetsColors {
  static const bg = Color(0xFF0F0F0F);
  static const sidebar = Color(0xFF141414);
  static const card = Color(0xFF1C1C1C);
  static const cardHover = Color(0xFF242424);
  static const border = Color(0xFF2A2A2A);
  static const accent = Color(0xFF22C55E);
  static const accentDim = Color(0xFF16A34A);
  static const textPrimary = Color(0xFFE5E5E5);
  static const textSecondary = Color(0xFF888888);
  static const textTertiary = Color(0xFF555555);
  static const red = Color(0xFFEF4444);
}
```

- [ ] **Step 3: Create `lib/src/models/snippet.dart`**

Copy verbatim from `app/lib/models/snippet.dart` — no app-specific imports to change.

```dart
import 'package:uuid/uuid.dart';

class Snippet {
  final String id;
  String label;
  String command;
  String description;
  String tag;

  Snippet({
    String? id,
    required this.label,
    required this.command,
    this.description = '',
    this.tag = '',
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'command': command,
        'description': description,
        'tag': tag,
      };

  factory Snippet.fromJson(Map<String, dynamic> json) => Snippet(
        id: json['id'],
        label: json['label'],
        command: json['command'],
        description: json['description'] ?? '',
        tag: json['tag'] ?? '',
      );
}
```

- [ ] **Step 4: Create `lib/src/providers/snippet_provider.dart`**

Copy from `app/lib/providers/snippet_provider.dart`, update the import:

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/snippet.dart';  // was: '../models/snippet.dart' — same relative path within package

class SnippetProvider extends ChangeNotifier {
  static const _prefsKey = 'yourssh.snippets';
  final List<Snippet> _snippets = [];

  List<Snippet> get snippets => _snippets;

  SnippetProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _snippets.addAll(list.map((e) => Snippet.fromJson(e as Map<String, dynamic>)));
    } else {
      _loadDefaults();
    }
    notifyListeners();
  }

  void _loadDefaults() {
    _snippets.addAll([
      Snippet(label: 'Disk usage', command: 'df -h', description: 'Show disk space', tag: 'system'),
      Snippet(label: 'Memory info', command: 'free -m', description: 'Show memory usage', tag: 'system'),
      Snippet(label: 'Running processes', command: 'ps aux', description: 'List all processes', tag: 'system'),
      Snippet(label: 'Tail syslog', command: 'tail -f /var/log/syslog', description: 'Follow system log', tag: 'logs'),
      Snippet(label: 'Network interfaces', command: 'ip addr show', description: 'List network interfaces', tag: 'network'),
      Snippet(label: 'Open ports', command: 'ss -tlnp', description: 'Show listening ports', tag: 'network'),
    ]);
    _save();
  }

  Future<void> add(Snippet snippet) async {
    _snippets.add(snippet);
    await _save();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    _snippets.removeWhere((s) => s.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_snippets.map((s) => s.toJson()).toList()));
  }
}
```

- [ ] **Step 5: Create `lib/src/screens/snippets_screen.dart`**

Copy from `app/lib/widgets/snippets_screen.dart`. Update imports:

```dart
// OLD app imports:
import '../models/snippet.dart';
import '../providers/snippet_provider.dart';
import '../theme/app_theme.dart';

// NEW package imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/snippet.dart';
import '../providers/snippet_provider.dart';
import '../theme.dart';
```

Replace every `AppColors.` with `SnippetsColors.`.

- [ ] **Step 6: Create `lib/src/snippets_plugin.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_plugin_api/yourssh_plugin_api.dart';
import 'providers/snippet_provider.dart';
import 'screens/snippets_screen.dart';

class YourSSHSnippetsPlugin extends YourSSHPlugin {
  @override
  String get id => 'dev.yourssh.snippets';

  @override
  String get name => 'Snippets';

  @override
  String get description => 'Save and recall reusable shell commands.';

  @override
  IconData get icon => Icons.code;

  @override
  String get version => '1.0.0';

  @override
  String get minApiVersion => '1.0.0';

  @override
  Widget buildUI(BuildContext context, YourSSHPluginContext pluginContext) {
    // SnippetProvider is provided by the app's MultiProvider.
    // We confirm it's in the tree by reading it here — no re-wrapping needed.
    return const SnippetsScreen();
  }
}
```

Note: `SnippetProvider` must already be in the app's `MultiProvider` tree for `SnippetsScreen` to work. This is handled in Task 4.

- [ ] **Step 7: Create barrel `lib/yourssh_snippets.dart`**

```dart
export 'src/snippets_plugin.dart';
export 'src/models/snippet.dart';
export 'src/providers/snippet_provider.dart';
```

- [ ] **Step 8: Verify no remaining `AppColors` in package**

```bash
grep -r "AppColors\|app_theme" packages/yourssh_snippets/
```

Expected: no output.

- [ ] **Step 9: Commit**

```bash
git add packages/yourssh_snippets/
git commit -m "feat: scaffold yourssh_snippets plugin package"
```

---

### Task 4: Wire both plugins into the app

**Files:**
- Modify: `app/pubspec.yaml`
- Modify: `app/lib/plugins/plugin_registry.dart`
- Modify: `app/lib/main.dart`
- Modify: `app/lib/widgets/sync_settings_screen.dart`
- Modify: `app/lib/screens/main_screen.dart`
- Modify: `app/lib/providers/settings_provider.dart`
- Modify: `app/lib/widgets/settings_screen.dart`
- Delete: `app/lib/widgets/web_tools_screen.dart`
- Delete: `app/lib/widgets/web_tools/embedded_browser.dart`
- Delete: `app/lib/widgets/web_tools/http_client.dart`
- Delete: `app/lib/widgets/web_tools/utility_tools.dart`
- Delete: `app/lib/widgets/snippets_screen.dart`
- Delete: `app/lib/models/snippet.dart`
- Delete: `app/lib/providers/snippet_provider.dart`

- [ ] **Step 1: Add package deps to `app/pubspec.yaml`**

Add under the `yourssh_devops` entry:

```yaml
  yourssh_web_tools:
    path: ../packages/yourssh_web_tools
  yourssh_snippets:
    path: ../packages/yourssh_snippets
```

- [ ] **Step 2: Run `flutter pub get`**

```bash
cd app && flutter pub get
```

Expected: no errors.

- [ ] **Step 3: Register plugins in `app/lib/plugins/plugin_registry.dart`**

Add imports and entries:

```dart
import 'package:yourssh_devops/yourssh_devops.dart';
import 'package:yourssh_web_tools/yourssh_web_tools.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import '../widgets/devops_tools_screen.dart';
import '../widgets/cloudflare_tunnel_screen.dart';
import '../widgets/mail_catcher_screen.dart';
import '../widgets/mcp_server_screen.dart';
import '../widgets/web_tools/port_forward_browser.dart';

final List<YourSSHPlugin> kRegisteredPlugins = [
  YourSSHDevOpsPlugin(
    config: DevOpsPluginConfig(
      networkToolsScreen: const DevopsToolsScreen(),
      cloudflareScreen: const CloudflareTunnelScreen(),
      mailCatcherScreen: const MailCatcherScreen(),
      mcpServerScreen: const McpServerScreen(),
    ),
  ),
  YourSSHWebToolsPlugin(
    config: WebToolsPluginConfig(
      portForwardBrowserBuilder: (onOpenUrl) => PortForwardBrowser(onOpenUrl: onOpenUrl),
    ),
  ),
  YourSSHSnippetsPlugin(),
];
```

- [ ] **Step 4: Update `app/lib/main.dart` — replace SnippetProvider import**

Find:
```dart
import 'providers/snippet_provider.dart';
```
Replace with:
```dart
import 'package:yourssh_snippets/yourssh_snippets.dart';
```

The `ChangeNotifierProvider(create: (_) => SnippetProvider())` line stays as-is since `SnippetProvider` is re-exported from the package barrel.

- [ ] **Step 5: Update `app/lib/widgets/sync_settings_screen.dart` — replace imports**

Find (approximate top of file):
```dart
import '../models/snippet.dart';
import '../providers/snippet_provider.dart';
```
Replace with:
```dart
import 'package:yourssh_snippets/yourssh_snippets.dart';
```

Verify `Snippet` and `SnippetProvider` are both exported by the barrel (they are — Step 7 of Task 3).

- [ ] **Step 6: Update `app/lib/screens/main_screen.dart` — remove WebTools and Snippets nav**

**6a.** Remove imports:
```dart
import '../widgets/web_tools_screen.dart';
import '../widgets/snippets_screen.dart';
```

**6b.** Change the `NavSection` enum — remove `webTools` and `snippets`:
```dart
// OLD:
enum NavSection { hosts, keychain, portForwarding, sftp, webTools, snippets, localTerminal, knownHosts, settings, plugins }
// NEW:
enum NavSection { hosts, keychain, portForwarding, sftp, localTerminal, knownHosts, settings, plugins }
```

**6c.** Remove the `hiddenNav` guard block (no longer needed):
```dart
// Remove these lines:
final hiddenNav = (_nav == NavSection.webTools && !settings.showWebTools) ||
    (_nav == NavSection.snippets && !settings.showSnippets);
// ... and associated setState block
```

**6d.** Remove sidebar nav items in `_Sidebar.build`:
```dart
// Remove:
if (context.watch<SettingsProvider>().showWebTools)
  _navItem(Icons.build_outlined, 'Web Tools', NavSection.webTools),
if (context.watch<SettingsProvider>().showSnippets)
  _navItem(Icons.code, 'Snippets', NavSection.snippets),
```

**6e.** Remove cases in `_buildContent` switch:
```dart
// Remove:
NavSection.snippets => const SnippetsScreen(),
NavSection.webTools => const WebToolsScreen(),
```

- [ ] **Step 7: Update `app/lib/providers/settings_provider.dart` — remove showWebTools/showSnippets**

Remove field declarations:
```dart
// Remove:
bool showWebTools = false;
bool showSnippets = false;
```

Remove from `load()`:
```dart
// Remove:
showWebTools = prefs.getBool('showWebTools') ?? false;
showSnippets = prefs.getBool('showSnippets') ?? false;
```

Remove from `save()` named params and body:
```dart
// Remove parameter:
bool? showWebTools,
bool? showSnippets,
// Remove body assignments:
if (showWebTools != null) this.showWebTools = showWebTools;
if (showSnippets != null) this.showSnippets = showSnippets;
// Remove prefs writes:
await prefs.setBool('showWebTools', this.showWebTools);
await prefs.setBool('showSnippets', this.showSnippets);
```

- [ ] **Step 8: Update `app/lib/widgets/settings_screen.dart` — remove toggle rows**

Find and remove the SwitchListTile blocks for Web Tools and Snippets:

```dart
// Remove the Web Tools tile (approximately lines 195-197):
value: settings.showWebTools,
onChanged: (v) => context.read<SettingsProvider>().save(showWebTools: v),

// Remove the Snippets tile (approximately lines 199-202):
title: const Text('Snippets', ...),
subtitle: const Text('Show Snippets section in sidebar', ...),
value: settings.showSnippets,
onChanged: (v) => context.read<SettingsProvider>().save(showSnippets: v),
```

Remove the full `SwitchListTile` widgets wrapping those values. Check whether the surrounding section header (e.g. "Features") only contained these two items — if so, remove the header too.

- [ ] **Step 9: Delete old app files**

```bash
rm app/lib/widgets/web_tools_screen.dart
rm app/lib/widgets/web_tools/embedded_browser.dart
rm app/lib/widgets/web_tools/http_client.dart
rm app/lib/widgets/web_tools/utility_tools.dart
rm app/lib/widgets/snippets_screen.dart
rm app/lib/models/snippet.dart
rm app/lib/providers/snippet_provider.dart
```

Note: `app/lib/widgets/web_tools/port_forward_browser.dart` stays — it's still used by `plugin_registry.dart`.

- [ ] **Step 10: Run `flutter analyze` and fix all errors**

```bash
cd app && flutter analyze
```

Fix any remaining import errors. Common issues:
- Any file that imported `snippet.dart` or `snippet_provider.dart` directly needs to switch to `package:yourssh_snippets/yourssh_snippets.dart`
- Any file that imported `web_tools_screen.dart` or `snippets_screen.dart` needs to be cleaned up
- If `settings_provider.dart` save() callers pass `showWebTools` or `showSnippets`, remove those named args

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "feat: wire yourssh_web_tools and yourssh_snippets plugins into app"
```

---

### Task 5: Verify and test

**Files:** No new files

- [ ] **Step 1: Run the app**

```bash
cd app && flutter run -d macos
```

Expected: app launches without errors.

- [ ] **Step 2: Verify WebTools plugin**

1. Open Plugins marketplace — confirm "Web Tools" appears
2. Enable Web Tools plugin
3. Confirm it appears in the sidebar plugin section
4. Click Web Tools — confirm Browser, HTTP Client, Utilities tabs work
5. Click Port Tunnels tab — confirm it shows active tunnels or the empty state message
6. Start a local port forward in Port Forwarding section, return to Web Tools → Port Tunnels — confirm tunnel appears and "Open" navigates to Browser tab

- [ ] **Step 3: Verify Snippets plugin**

1. Open Plugins marketplace — confirm "Snippets" appears
2. Enable Snippets plugin
3. Click Snippets — confirm default snippets render
4. Add a snippet — confirm it persists after disabling/re-enabling the plugin
5. Delete a snippet — confirm it's removed

- [ ] **Step 4: Verify Settings cleanup**

1. Open Settings — confirm no "Web Tools" or "Snippets" toggle exists
2. Verify no sidebar nav items for Web Tools or Snippets remain when plugins are disabled

- [ ] **Step 5: Verify Sync still works**

1. Enable sync in Settings
2. Confirm sync settings screen loads without errors (it reads `SnippetProvider.snippets` for sync payload)

- [ ] **Step 6: Run tests**

```bash
cd app && flutter test
```

Expected: all tests pass.

- [ ] **Step 7: Commit clean state**

```bash
git add -A
git commit -m "chore: verify webtool and snippets plugin extraction complete"
```
