# Host Group Management & Import — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "New Group" right-side panel and an "Import Hosts" right-side panel, both triggered from a split button in the Hosts dashboard top bar.

**Architecture:** Extend `StorageService` with `pinnedGroups` persistence, add group management to `HostProvider`, replace the single `_showHostPanel: bool` in `MainScreen` with a `_SidePanel` enum, and add two new panel widgets (`NewGroupPanel`, `ImportPanel`) following the existing `HostDetailPanel` pattern (340px right-side panel, no modals).

**Tech Stack:** Flutter/Dart, `shared_preferences` (already used), `file_picker ^8.1.2` (already in `pubspec.yaml`)

---

## File Map

| File | Change |
|------|--------|
| `app/lib/services/storage_service.dart` | Add `loadPinnedGroups` / `savePinnedGroups` |
| `app/lib/providers/host_provider.dart` | Add `_pinnedGroups`, `addGroup`, `removeGroup`, load on init |
| `app/lib/widgets/hosts_dashboard.dart` | Change `onNewGroup` to `VoidCallback`, add `onImport`, split button, merge pinnedGroups in group section, `_GroupCard` delete hover menu |
| `app/lib/screens/main_screen.dart` | Replace `bool _showHostPanel` with `_SidePanel` enum; wire `onNewGroup`/`onImport` |
| `app/lib/widgets/new_group_panel.dart` | **New** — group name field + save |
| `app/lib/widgets/import_panel.dart` | **New** — file/paste input, ssh-config + JSON parsers, preview, duplicate handling, import |
| `app/test/providers/host_provider_test.dart` | **New** — pinnedGroups CRUD tests |
| `app/test/widgets/import_parser_test.dart` | **New** — parser unit tests |

---

### Task 1: StorageService — pinnedGroups persistence

**Files:**
- Modify: `app/lib/services/storage_service.dart`

- [ ] **Step 1: Add `loadPinnedGroups` and `savePinnedGroups` to `StorageService`**

Open `app/lib/services/storage_service.dart`. After the `_knownHostsKey` constant block, add:

```dart
// ── Pinned Groups ──────────────────────────────────────────

static const _pinnedGroupsKey = 'yourssh.pinned_groups';

Future<List<String>> loadPinnedGroups() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(_pinnedGroupsKey) ?? [];
}

Future<void> savePinnedGroups(List<String> groups) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(_pinnedGroupsKey, groups);
}
```

- [ ] **Step 2: Verify the app still analyzes cleanly**

```bash
cd app && flutter analyze --no-fatal-infos
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add app/lib/services/storage_service.dart
git commit -m "feat: add pinnedGroups persistence to StorageService"
```

---

### Task 2: HostProvider — pinnedGroups state

**Files:**
- Modify: `app/lib/providers/host_provider.dart`
- Create: `app/test/providers/host_provider_test.dart`

- [ ] **Step 1: Write failing tests**

Create `app/test/providers/host_provider_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('HostProvider pinnedGroups', () {
    late HostProvider provider;

    setUp(() {
      provider = HostProvider(StorageService());
    });

    tearDown(() => provider.dispose());

    test('starts with empty pinnedGroups', () async {
      await Future.delayed(Duration.zero); // allow _load to complete
      expect(provider.pinnedGroups, isEmpty);
    });

    test('addGroup appends to pinnedGroups', () async {
      await Future.delayed(Duration.zero);
      await provider.addGroup('Production');
      expect(provider.pinnedGroups, ['Production']);
    });

    test('addGroup ignores duplicates (case-insensitive)', () async {
      await Future.delayed(Duration.zero);
      await provider.addGroup('Production');
      await provider.addGroup('production');
      expect(provider.pinnedGroups.length, 1);
    });

    test('removeGroup removes the group', () async {
      await Future.delayed(Duration.zero);
      await provider.addGroup('Staging');
      await provider.removeGroup('Staging');
      expect(provider.pinnedGroups, isEmpty);
    });

    test('pinnedGroups persists across provider instances', () async {
      await Future.delayed(Duration.zero);
      await provider.addGroup('Saved');
      final provider2 = HostProvider(StorageService());
      await Future.delayed(Duration.zero);
      expect(provider2.pinnedGroups, ['Saved']);
      provider2.dispose();
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app && flutter test test/providers/host_provider_test.dart
```
Expected: FAIL — `pinnedGroups` getter not found.

- [ ] **Step 3: Add pinnedGroups to HostProvider**

Open `app/lib/providers/host_provider.dart`. After `List<Host> _hosts = [];` add:

```dart
List<String> _pinnedGroups = [];
```

After `String _search = '';` add the getter and methods:

```dart
List<String> get pinnedGroups => List.unmodifiable(_pinnedGroups);

Future<void> addGroup(String name) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return;
  final alreadyExists = _pinnedGroups.any(
    (g) => g.toLowerCase() == trimmed.toLowerCase(),
  );
  if (alreadyExists) return;
  _pinnedGroups.add(trimmed);
  await _storage.savePinnedGroups(_pinnedGroups);
  notifyListeners();
}

Future<void> removeGroup(String name) async {
  _pinnedGroups.removeWhere((g) => g.toLowerCase() == name.toLowerCase());
  await _storage.savePinnedGroups(_pinnedGroups);
  notifyListeners();
}
```

In the `_load()` method, load pinnedGroups alongside hosts:

```dart
Future<void> _load() async {
  _hosts = await _storage.loadHosts();
  _pinnedGroups = await _storage.loadPinnedGroups();
  notifyListeners();
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd app && flutter test test/providers/host_provider_test.dart
```
Expected: all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/host_provider.dart app/test/providers/host_provider_test.dart
git commit -m "feat: add pinnedGroups management to HostProvider"
```

---

### Task 3: HostsDashboard — split button + group display + card delete

**Files:**
- Modify: `app/lib/widgets/hosts_dashboard.dart`

- [ ] **Step 1: Update `HostsDashboard` callbacks**

In `app/lib/widgets/hosts_dashboard.dart`, change the `HostsDashboard` widget's constructor. Replace:

```dart
final void Function(String group)? onNewGroup;
const HostsDashboard({super.key, this.onAddHost, this.onEditHost, this.onOpenLocalTerminal, this.onNewGroup});
```

with:

```dart
final VoidCallback? onNewGroup;
final VoidCallback? onImport;
const HostsDashboard({super.key, this.onAddHost, this.onEditHost, this.onOpenLocalTerminal, this.onNewGroup, this.onImport});
```

- [ ] **Step 2: Merge pinnedGroups into the groups map**

In `_HostsDashboardState.build`, replace the groups map construction block:

```dart
final groups = <String, List<Host>>{};
for (final h in hosts) {
  final g = h.group.isEmpty ? 'DEFAULT' : h.group.toUpperCase();
  (groups[g] ??= []).add(h);
}
```

with:

```dart
final pinnedGroups = hostProvider.pinnedGroups;
final groups = <String, List<Host>>{};
// Pinned groups appear first (may be empty)
for (final g in pinnedGroups) {
  groups[g.toUpperCase()] = [];
}
// Fill with hosts (may add new groups not in pinnedGroups)
for (final h in hosts) {
  final g = h.group.isEmpty ? 'DEFAULT' : h.group.toUpperCase();
  (groups[g] ??= []).add(h);
}
```

- [ ] **Step 3: Pass `onDelete` to `_GroupCard`**

In `_HostsDashboardState.build`, replace the `_GroupCard` construction in the `Wrap`:

```dart
.map((e) => _GroupCard(name: e.key, count: e.value.length))
```

with:

```dart
.map((e) => _GroupCard(
  name: e.key,
  count: e.value.length,
  onDelete: () => context.read<HostProvider>().removeGroup(e.key),
))
```

- [ ] **Step 4: Add hover delete menu to `_GroupCard`**

Replace the entire `_GroupCard` class:

```dart
class _GroupCard extends StatefulWidget {
  final String name;
  final int count;
  final VoidCallback? onDelete;
  const _GroupCard({required this.name, required this.count, this.onDelete});

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.textTertiary.withValues(alpha: 0.3),
              child: Icon(Icons.folder_outlined, color: AppColors.textSecondary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.name,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  Text('${widget.count} host${widget.count == 1 ? '' : 's'}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            if (_hovered && widget.onDelete != null)
              GestureDetector(
                onTapDown: (d) => _showMenu(context, d.globalPosition),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.more_horiz,
                      size: 14, color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context, Offset position) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      color: AppColors.card,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'delete',
          height: 36,
          onTap: widget.onDelete,
          child: const Row(
            children: [
              Icon(Icons.delete_outline, size: 14, color: AppColors.red),
              SizedBox(width: 10),
              Text('Delete group',
                  style: TextStyle(color: AppColors.red, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Update `_TopBar` to accept and wire the new callbacks**

In `_TopBar`, replace:

```dart
final void Function(String group)? onNewGroup;

const _TopBar({required this.search, required this.onSearch, required this.totalHosts, required this.filteredCount, this.onAddHost, this.onLocalTerminal, this.onNewGroup});
```

with:

```dart
final VoidCallback? onNewGroup;
final VoidCallback? onImport;

const _TopBar({required this.search, required this.onSearch, required this.totalHosts, required this.filteredCount, this.onAddHost, this.onLocalTerminal, this.onNewGroup, this.onImport});
```

- [ ] **Step 6: Replace NEW HOST button with a split button in `_TopBar.build`**

In `_TopBar.build`, replace:

```dart
_OutlinedBtn(
  icon: Icons.add,
  label: 'NEW HOST',
  onTap: onAddHost ?? () {},
),
```

with:

```dart
_SplitNewBtn(
  onNewHost: onAddHost ?? () {},
  onNewGroup: onNewGroup,
  onImport: onImport,
),
```

- [ ] **Step 7: Add `_SplitNewBtn` widget at the bottom of `hosts_dashboard.dart`**

Add after the `_OutlinedBtn` class:

```dart
class _SplitNewBtn extends StatefulWidget {
  final VoidCallback onNewHost;
  final VoidCallback? onNewGroup;
  final VoidCallback? onImport;
  const _SplitNewBtn({
    required this.onNewHost,
    this.onNewGroup,
    this.onImport,
  });

  @override
  State<_SplitNewBtn> createState() => _SplitNewBtnState();
}

class _SplitNewBtnState extends State<_SplitNewBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: _hovered ? AppColors.textSecondary : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Left: NEW HOST action
            GestureDetector(
              onTap: widget.onNewHost,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add,
                        size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    const Text('NEW HOST',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            letterSpacing: 0.3)),
                  ],
                ),
              ),
            ),
            // Divider
            Container(width: 1, height: 20, color: AppColors.border),
            // Right: dropdown chevron
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'group') widget.onNewGroup?.call();
                if (v == 'import') widget.onImport?.call();
              },
              color: AppColors.card,
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Icon(Icons.keyboard_arrow_down,
                    size: 14, color: AppColors.textSecondary),
              ),
              itemBuilder: (_) => [
                PopupMenuItem<String>(
                  value: 'group',
                  height: 36,
                  child: Row(
                    children: const [
                      Icon(Icons.create_new_folder_outlined,
                          size: 14, color: AppColors.textSecondary),
                      SizedBox(width: 10),
                      Text('New Group',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'import',
                  height: 36,
                  child: Row(
                    children: const [
                      Icon(Icons.upload_file_outlined,
                          size: 14, color: AppColors.textSecondary),
                      SizedBox(width: 10),
                      Text('Import',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Update `_TopBar` instantiation in `_HostsDashboardState.build`**

Find the `_TopBar(...)` call and add `onImport: widget.onImport`:

```dart
_TopBar(
  search: _search,
  onSearch: (v) => setState(() => _search = v),
  totalHosts: hosts.length,
  filteredCount: filtered.length,
  onAddHost: widget.onAddHost,
  onLocalTerminal: widget.onOpenLocalTerminal,
  onNewGroup: widget.onNewGroup,
  onImport: widget.onImport,
),
```

- [ ] **Step 9: Analyze and verify**

```bash
cd app && flutter analyze --no-fatal-infos
```
Expected: no errors.

- [ ] **Step 10: Commit**

```bash
git add app/lib/widgets/hosts_dashboard.dart
git commit -m "feat: split button in HostsDashboard with New Group and Import actions"
```

---

### Task 4: MainScreen — _SidePanel enum

**Files:**
- Modify: `app/lib/screens/main_screen.dart`

- [ ] **Step 1: Replace panel state**

In `app/lib/screens/main_screen.dart`, add the enum before the class (after the imports):

```dart
enum _SidePanel { none, host, newGroup, import }
```

In `_MainScreenState`, replace:

```dart
bool _showHostPanel = false;
Host? _editingHost;
String? _initialGroup;
```

with:

```dart
_SidePanel _sidePanel = _SidePanel.none;
Host? _editingHost;
String? _initialGroup;
```

- [ ] **Step 2: Update `_openHostPanel` and add new open/close helpers**

Replace `_openHostPanel` and `_closeHostPanel`:

```dart
void _openHostPanel({Host? existing, String? initialGroup}) {
  setState(() {
    _sidePanel = _SidePanel.host;
    _editingHost = existing;
    _initialGroup = initialGroup;
  });
}

void _openNewGroupPanel() => setState(() {
      _sidePanel = _SidePanel.newGroup;
      _editingHost = null;
      _initialGroup = null;
    });

void _openImportPanel() => setState(() {
      _sidePanel = _SidePanel.import;
      _editingHost = null;
      _initialGroup = null;
    });

void _closePanel() => setState(() {
      _sidePanel = _SidePanel.none;
      _editingHost = null;
      _initialGroup = null;
    });
```

- [ ] **Step 3: Update all references to `_showHostPanel` and `_closeHostPanel`**

In the `build` method, replace every `_showHostPanel` check and `_closeHostPanel()` call:

```dart
// Replace:
if (s != NavSection.hosts) _closeHostPanel();
// With:
if (s != NavSection.hosts) _closePanel();
```

(There are two identical occurrences in `onNavSelect` lambdas — replace both.)

```dart
// Replace the Row child condition:
if (_showHostPanel && _nav == NavSection.hosts && !_viewingTerminal)
  HostDetailPanel(
    ...
    onClose: _closeHostPanel,
    ...
  ),

// With:
if (_nav == NavSection.hosts && !_viewingTerminal) ...[
  if (_sidePanel == _SidePanel.host)
    HostDetailPanel(
      existing: _editingHost,
      initialGroup: _initialGroup,
      onClose: _closePanel,
      onSave: (host, password) async {
        final hp = context.read<HostProvider>();
        if (_editingHost != null) {
          await hp.updateHost(host, password: password);
        } else {
          await hp.addHost(host, password: password);
        }
      },
      onConnect: (host) async {
        setState(() => _viewingTerminal = true);
        await context.read<SessionProvider>().connect(host);
      },
    ),
  if (_sidePanel == _SidePanel.newGroup)
    NewGroupPanel(onClose: _closePanel),
  if (_sidePanel == _SidePanel.import)
    ImportPanel(onClose: _closePanel),
],
```

- [ ] **Step 4: Add imports for new widgets at top of file**

Add after the existing imports:

```dart
import '../widgets/new_group_panel.dart';
import '../widgets/import_panel.dart';
```

- [ ] **Step 5: Wire callbacks in `_buildContent` → `HostsDashboard`**

Replace the `HostsDashboard` call:

```dart
NavSection.hosts => HostsDashboard(
    onAddHost: () => _openHostPanel(),
    onEditHost: (h) => _openHostPanel(existing: h),
    onOpenLocalTerminal: () => setState(() => _nav = NavSection.localTerminal),
    onNewGroup: (group) => _openHostPanel(initialGroup: group),
  ),
```

with:

```dart
NavSection.hosts => HostsDashboard(
    onAddHost: () => _openHostPanel(),
    onEditHost: (h) => _openHostPanel(existing: h),
    onOpenLocalTerminal: () => setState(() => _nav = NavSection.localTerminal),
    onNewGroup: _openNewGroupPanel,
    onImport: _openImportPanel,
  ),
```

- [ ] **Step 6: Analyze and verify**

```bash
cd app && flutter analyze --no-fatal-infos
```
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add app/lib/screens/main_screen.dart
git commit -m "refactor: replace _showHostPanel bool with _SidePanel enum in MainScreen"
```

---

### Task 5: NewGroupPanel widget

**Files:**
- Create: `app/lib/widgets/new_group_panel.dart`

- [ ] **Step 1: Create `new_group_panel.dart`**

Create `app/lib/widgets/new_group_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/host_provider.dart';
import '../theme/app_theme.dart';

class NewGroupPanel extends StatefulWidget {
  final VoidCallback onClose;
  const NewGroupPanel({super.key, required this.onClose});

  @override
  State<NewGroupPanel> createState() => _NewGroupPanelState();
}

class _NewGroupPanelState extends State<NewGroupPanel> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Group name is required');
      return;
    }
    final provider = context.read<HostProvider>();
    final exists = provider.pinnedGroups.any(
      (g) => g.toLowerCase() == name.toLowerCase(),
    );
    if (exists) {
      setState(() => _error = 'Group "$name" already exists');
      return;
    }
    setState(() { _saving = true; _error = null; });
    await provider.addGroup(name);
    if (mounted) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _error != null ? AppColors.red : AppColors.border,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_outlined,
                            size: 16, color: AppColors.textTertiary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            autofocus: true,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13),
                            decoration: const InputDecoration(
                              hintText: 'Group name',
                              hintStyle: TextStyle(
                                  color: AppColors.textTertiary, fontSize: 13),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onSubmitted: (_) => _save(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(_error!,
                      style: const TextStyle(
                          color: AppColors.red, fontSize: 11)),
                ],
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _saving ? null : _save,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _saving ? AppColors.accentDim : AppColors.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.black, strokeWidth: 2))
                        : const Text('SAVE GROUP',
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                letterSpacing: 1)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Expanded(
            child: Text('New Group',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.close,
                  size: 14, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
cd app && flutter analyze --no-fatal-infos
```
Expected: no errors.

- [ ] **Step 3: Manual smoke test**

```bash
cd app && flutter run -d macos
```
- Click dropdown chevron `˅` next to NEW HOST → select "New Group"
- Right panel should slide in with "New Group" header and a text field
- Type a name and press SAVE GROUP → panel closes, group card appears in dashboard
- Reopen New Group, type same name → red error "already exists"

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/new_group_panel.dart
git commit -m "feat: add NewGroupPanel right-side panel"
```

---

### Task 6: ImportPanel — parsers + preview

**Files:**
- Create: `app/lib/widgets/import_panel.dart`
- Create: `app/test/widgets/import_parser_test.dart`

- [ ] **Step 1: Write failing parser tests**

Create `app/test/widgets/import_parser_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/import_panel.dart';
import 'package:yourssh/models/host.dart';

void main() {
  group('parseSshConfig', () {
    test('parses a single Host block', () {
      const input = '''
Host myserver
    HostName 192.168.1.10
    User ubuntu
    Port 2222
''';
      final hosts = parseSshConfig(input);
      expect(hosts.length, 1);
      expect(hosts[0].label, 'myserver');
      expect(hosts[0].host, '192.168.1.10');
      expect(hosts[0].username, 'ubuntu');
      expect(hosts[0].port, 2222);
    });

    test('defaults User to root and Port to 22 when missing', () {
      const input = 'Host bare\n    HostName 10.0.0.1\n';
      final hosts = parseSshConfig(input);
      expect(hosts[0].username, 'root');
      expect(hosts[0].port, 22);
    });

    test('skips Host * wildcard blocks', () {
      const input = '''
Host *
    ServerAliveInterval 60

Host real
    HostName 1.2.3.4
    User admin
''';
      final hosts = parseSshConfig(input);
      expect(hosts.length, 1);
      expect(hosts[0].label, 'real');
    });

    test('parses multiple Host blocks', () {
      const input = '''
Host prod
    HostName prod.example.com
    User deploy

Host staging
    HostName staging.example.com
    User deploy
    Port 2022
''';
      final hosts = parseSshConfig(input);
      expect(hosts.length, 2);
      expect(hosts[1].label, 'staging');
      expect(hosts[1].port, 2022);
    });

    test('returns empty list for empty string', () {
      expect(parseSshConfig(''), isEmpty);
    });
  });

  group('parseJsonHosts', () {
    test('parses a JSON array of hosts', () {
      const input = '''[
  {"label":"Web","host":"web.example.com","port":22,"username":"admin",
   "authType":"password","group":"prod","tags":[]}
]''';
      final hosts = parseJsonHosts(input);
      expect(hosts.length, 1);
      expect(hosts[0].label, 'Web');
      expect(hosts[0].host, 'web.example.com');
      expect(hosts[0].group, 'prod');
    });

    test('assigns new ids (does not reuse imported ids)', () {
      const input = '''[
  {"id":"old-id-123","label":"A","host":"1.2.3.4","port":22,
   "username":"root","authType":"password","group":"","tags":[]}
]''';
      final hosts = parseJsonHosts(input);
      expect(hosts[0].id, isNot('old-id-123'));
    });

    test('returns empty list for invalid JSON', () {
      expect(parseJsonHosts('not json at all'), isEmpty);
    });

    test('returns empty list for empty input', () {
      expect(parseJsonHosts(''), isEmpty);
    });
  });

  group('detectAndParse', () {
    test('detects ssh config when input starts with "Host "', () {
      const input = 'Host server\n    HostName 1.2.3.4\n    User root\n';
      final result = detectAndParse(input);
      expect(result, isNotEmpty);
      expect(result[0].label, 'server');
    });

    test('detects JSON when input starts with [', () {
      const input =
          '[{"label":"X","host":"x.com","port":22,"username":"u","authType":"password","group":"","tags":[]}]';
      final result = detectAndParse(input);
      expect(result, isNotEmpty);
      expect(result[0].label, 'X');
    });

    test('returns empty list for unrecognized format', () {
      expect(detectAndParse('random garbage'), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd app && flutter test test/widgets/import_parser_test.dart
```
Expected: FAIL — `parseSshConfig`, `parseJsonHosts`, `detectAndParse` not found.

- [ ] **Step 3: Create `import_panel.dart` with parsers and panel skeleton**

Create `app/lib/widgets/import_panel.dart`:

```dart
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../providers/host_provider.dart';
import '../theme/app_theme.dart';

// ── Public parser functions (also used by tests) ──────────

List<Host> parseSshConfig(String input) {
  final hosts = <Host>[];
  // Split on lines starting with 'Host ' (case-insensitive)
  final blockRegex = RegExp(r'^Host\s+(.+)$', multiLine: true, caseSensitive: false);
  final matches = blockRegex.allMatches(input).toList();
  for (var i = 0; i < matches.length; i++) {
    final alias = matches[i].group(1)!.trim();
    if (alias == '*') continue;
    final start = matches[i].end;
    final end = i + 1 < matches.length ? matches[i + 1].start : input.length;
    final block = input.substring(start, end);
    String? hostname;
    String user = 'root';
    int port = 22;
    for (final line in block.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith('hostname ')) {
        hostname = trimmed.substring('hostname '.length).trim();
      } else if (trimmed.toLowerCase().startsWith('user ')) {
        user = trimmed.substring('user '.length).trim();
      } else if (trimmed.toLowerCase().startsWith('port ')) {
        port = int.tryParse(trimmed.substring('port '.length).trim()) ?? 22;
      }
    }
    if (hostname == null) continue;
    hosts.add(Host(
      label: alias,
      host: hostname,
      port: port,
      username: user,
    ));
  }
  return hosts;
}

List<Host> parseJsonHosts(String input) {
  if (input.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(input);
    final list = decoded is List ? decoded : [decoded];
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) {
          // Never re-use imported IDs — always generate new ones
          final map = Map<String, dynamic>.from(e)..remove('id');
          return Host.fromJson({
            'label': map['label'] ?? '',
            'host': map['host'] ?? '',
            'port': map['port'] ?? 22,
            'username': map['username'] ?? 'root',
            'authType': map['authType'] ?? 'password',
            'group': map['group'] ?? '',
            'tags': map['tags'] ?? [],
            'createdAt': DateTime.now().toIso8601String(),
          });
        })
        .where((h) => h.host.isNotEmpty)
        .toList();
  } catch (_) {
    return [];
  }
}

List<Host> detectAndParse(String input) {
  final trimmed = input.trimLeft();
  if (trimmed.toLowerCase().startsWith('host ')) {
    return parseSshConfig(input);
  }
  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    return parseJsonHosts(input);
  }
  return [];
}

// ── ImportPanel widget ────────────────────────────────────

class ImportPanel extends StatefulWidget {
  final VoidCallback onClose;
  const ImportPanel({super.key, required this.onClose});

  @override
  State<ImportPanel> createState() => _ImportPanelState();
}

enum _InputMode { file, paste }

class _ImportPanelState extends State<ImportPanel> {
  _InputMode _mode = _InputMode.file;
  final _pasteCtrl = TextEditingController();
  String? _parseError;
  List<Host> _parsed = [];
  // Per-host state: true=include, false=exclude
  final Map<int, bool> _included = {};
  // Per-host duplicate resolution: true=overwrite, false=skip
  final Map<int, bool> _overwrite = {};

  @override
  void dispose() {
    _pasteCtrl.dispose();
    super.dispose();
  }

  List<Host> get _existingHosts =>
      context.read<HostProvider>().allHosts;

  bool _isDuplicate(Host h) => _existingHosts.any(
        (e) =>
            e.host.toLowerCase() == h.host.toLowerCase() &&
            e.username.toLowerCase() == h.username.toLowerCase(),
      );

  void _applyParsed(List<Host> hosts) {
    setState(() {
      _parsed = hosts;
      _parseError = hosts.isEmpty ? 'No hosts found or unrecognized format' : null;
      _included.clear();
      _overwrite.clear();
      for (var i = 0; i < hosts.length; i++) {
        _included[i] = true;
        _overwrite[i] = false; // default: skip duplicate
      }
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'config', 'conf', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    final content = String.fromCharCodes(bytes);
    _applyParsed(detectAndParse(content));
  }

  void _parsePaste() {
    _applyParsed(detectAndParse(_pasteCtrl.text));
  }

  // Counts only rows that will actually be imported:
  // checked non-duplicates + checked duplicates with overwrite=true
  int get _effectiveImportCount => _included.entries
      .where((e) => e.value)
      .where((e) {
        final dup = _isDuplicate(_parsed[e.key]);
        return !dup || (_overwrite[e.key] ?? false);
      })
      .length;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _buildModeToggle(),
                const SizedBox(height: 12),
                if (_mode == _InputMode.file) _buildFileSection(),
                if (_mode == _InputMode.paste) _buildPasteSection(),
                if (_parseError != null) ...[
                  const SizedBox(height: 8),
                  Text(_parseError!,
                      style: const TextStyle(
                          color: AppColors.red, fontSize: 11)),
                ],
                if (_parsed.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildPreview(),
                  const SizedBox(height: 16),
                  _buildImportButton(context),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Expanded(
            child: Text('Import Hosts',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.close,
                  size: 14, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _modeTab('From file', _InputMode.file),
          _modeTab('Paste text', _InputMode.paste),
        ],
      ),
    );
  }

  Widget _modeTab(String label, _InputMode mode) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _mode = mode;
          _parsed = [];
          _parseError = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.textPrimary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal)),
        ),
      ),
    );
  }

  Widget _buildFileSection() {
    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: AppColors.border, style: BorderStyle.solid),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.upload_file_outlined,
                size: 16, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Text('Choose .json or config file',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildPasteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: _pasteCtrl,
            maxLines: 10,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontFamily: 'monospace'),
            decoration: const InputDecoration(
              hintText:
                  'Paste .ssh/config or JSON here...',
              hintStyle:
                  TextStyle(color: AppColors.textTertiary, fontSize: 12),
              contentPadding: EdgeInsets.all(12),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _parsePaste,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: const Text('Parse',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_parsed.length} host${_parsed.length == 1 ? '' : 's'} found',
          style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: List.generate(_parsed.length, (i) {
              final h = _parsed[i];
              final dup = _isDuplicate(h);
              return _PreviewRow(
                host: h,
                isDuplicate: dup,
                included: _included[i] ?? true,
                overwrite: _overwrite[i] ?? false,
                onToggleInclude: (v) =>
                    setState(() => _included[i] = v),
                onToggleOverwrite: (v) =>
                    setState(() => _overwrite[i] = v),
                showDivider: i < _parsed.length - 1,
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildImportButton(BuildContext context) {
    final count = _effectiveImportCount;
    return GestureDetector(
      onTap: count == 0 ? null : () => _doImport(context),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: count == 0 ? AppColors.accentDim : AppColors.accent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          'IMPORT $count HOST${count == 1 ? '' : 'S'}',
          style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 1),
        ),
      ),
    );
  }

  Future<void> _doImport(BuildContext context) async {
    final provider = context.read<HostProvider>();
    int imported = 0;
    for (var i = 0; i < _parsed.length; i++) {
      if (!(_included[i] ?? true)) continue;
      final h = _parsed[i];
      final dup = _isDuplicate(h);
      if (dup) {
        if (!(_overwrite[i] ?? false)) continue; // skip
        final existing = provider.allHosts.firstWhere(
          (e) =>
              e.host.toLowerCase() == h.host.toLowerCase() &&
              e.username.toLowerCase() == h.username.toLowerCase(),
        );
        await provider.updateHost(existing.copyWith(
          label: h.label,
          host: h.host,
          port: h.port,
          username: h.username,
          group: h.group,
        ));
      } else {
        await provider.addHost(h);
      }
      imported++;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Imported $imported host${imported == 1 ? '' : 's'}'),
      duration: const Duration(seconds: 2),
    ));
    widget.onClose();
  }
}

// ── Preview Row ───────────────────────────────────────────

class _PreviewRow extends StatelessWidget {
  final Host host;
  final bool isDuplicate;
  final bool included;
  final bool overwrite;
  final ValueChanged<bool> onToggleInclude;
  final ValueChanged<bool> onToggleOverwrite;
  final bool showDivider;

  const _PreviewRow({
    required this.host,
    required this.isDuplicate,
    required this.included,
    required this.overwrite,
    required this.onToggleInclude,
    required this.onToggleOverwrite,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Checkbox(
                value: included,
                onChanged: (v) => onToggleInclude(v ?? true),
                side: const BorderSide(color: AppColors.textSecondary),
                activeColor: AppColors.accent,
                checkColor: Colors.black,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(host.label,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                    Text(
                      '${host.username}@${host.host}:${host.port}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isDuplicate && included) ...[
                const SizedBox(width: 4),
                _DuplicateBadge(
                    overwrite: overwrite,
                    onToggle: () => onToggleOverwrite(!overwrite)),
              ],
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, color: AppColors.border, indent: 10),
      ],
    );
  }
}

class _DuplicateBadge extends StatelessWidget {
  final bool overwrite;
  final VoidCallback onToggle;

  const _DuplicateBadge({required this.overwrite, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: overwrite
              ? AppColors.blue.withValues(alpha: 0.15)
              : Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: overwrite
                ? AppColors.blue.withValues(alpha: 0.5)
                : Colors.orange.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          overwrite ? 'Overwrite' : 'Skip dup',
          style: TextStyle(
              color: overwrite ? AppColors.blue : Colors.orange,
              fontSize: 9,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run parser tests**

```bash
cd app && flutter test test/widgets/import_parser_test.dart
```
Expected: all tests PASS.

- [ ] **Step 5: Run full test suite**

```bash
cd app && flutter test
```
Expected: all tests PASS.

- [ ] **Step 6: Analyze**

```bash
cd app && flutter analyze --no-fatal-infos
```
Expected: no errors.

- [ ] **Step 7: Manual smoke test**

```bash
cd app && flutter run -d macos
```

Test file import:
- Click `˅` → Import → panel opens
- Click "Choose .json or config file" → pick a `.ssh/config` file
- Preview list appears with checkbox per host
- Any host already in the app shows an amber "Skip dup" badge; tap it to toggle to "Overwrite"
- Uncheck a host to exclude it
- Click IMPORT N HOSTS → SnackBar confirms, panel closes

Test paste:
- Switch to "Paste text" tab
- Paste a `.ssh/config` block → click Parse → preview appears
- Click IMPORT

- [ ] **Step 8: Commit**

```bash
git add app/lib/widgets/import_panel.dart app/test/widgets/import_parser_test.dart
git commit -m "feat: add ImportPanel with ssh-config + JSON parsers and preview"
```
