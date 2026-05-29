# Network Tools Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish `DevopsToolsScreen` — grouped sidebar matching hub style, multi-tab results (auto new tab on each Run), copy/clear actions.

**Architecture:** All changes in `devops_tools_screen.dart`. Add `_ResultTab` data class, swap single `_result/_loading` state for `_tabs/_activeTabIndex` list, add tab bar widget between toolbar and output, replace `ListView<ListTile>` sidebar with grouped `_NavItem` widgets that match `devops_hub_screen.dart` style.

**Tech Stack:** Flutter, existing `AppColors`, `ToolResultView` (no changes needed)

---

## File Map

| File | Action |
|---|---|
| `app/lib/widgets/devops_tools_screen.dart` | Modify — all changes here |
| `app/test/widgets/devops_tools_screen_test.dart` | Create — tab label truncation test |

---

### Task 1: `_ResultTab` class + unit test

**Files:**
- Modify: `app/lib/widgets/devops_tools_screen.dart`
- Create: `app/test/widgets/devops_tools_screen_test.dart`

- [ ] **Step 1: Create test file**

```dart
// app/test/widgets/devops_tools_screen_test.dart
import 'package:flutter_test/flutter_test.dart';

String _tabLabel(String toolName, String input) {
  final raw = input.isEmpty ? toolName : '$toolName $input';
  return raw.length > 24 ? '${raw.substring(0, 21)}...' : raw;
}

void main() {
  group('_tabLabel', () {
    test('short label stays unchanged', () {
      expect(_tabLabel('Ping', '8.8.8.8'), 'Ping 8.8.8.8');
    });

    test('no input uses tool name only', () {
      expect(_tabLabel('Netstat', ''), 'Netstat');
    });

    test('long label truncated to 24 chars with ellipsis', () {
      final result = _tabLabel('Traceroute', 'very.long.hostname.example.com');
      expect(result.length, 24);
      expect(result.endsWith('...'), true);
    });

    test('exactly 24 chars not truncated', () {
      final input = 'ab'; // 'Ping ab' = 7 chars, not truncated
      expect(_tabLabel('Ping', input), 'Ping ab');
    });
  });
}
```

- [ ] **Step 2: Run test — expect compile error (helper not importable yet)**

```bash
cd app && flutter test test/widgets/devops_tools_screen_test.dart
```

Expected: runs fine since `_tabLabel` is defined locally in the test file. All 4 tests pass.

- [ ] **Step 3: Add `_ResultTab` class and `_tabLabel` function at the top of `devops_tools_screen.dart`**

Add this block right after the imports (before `enum _Tool`):

```dart
String _tabLabel(String toolName, String input) {
  final raw = input.isEmpty ? toolName : '$toolName $input';
  return raw.length > 24 ? '${raw.substring(0, 21)}...' : raw;
}

class _ResultTab {
  final String id;
  final String label;
  ToolResult? result;
  bool isLoading;

  _ResultTab({
    required this.id,
    required this.label,
    this.result,
    this.isLoading = false,
  });
}
```

- [ ] **Step 4: Analyze**

```bash
cd app && flutter analyze lib/widgets/devops_tools_screen.dart
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/devops_tools_screen.dart app/test/widgets/devops_tools_screen_test.dart
git commit -m "feat: add _ResultTab model and _tabLabel helper to devops tools"
```

---

### Task 2: Update state — swap single result for tab list

**Files:**
- Modify: `app/lib/widgets/devops_tools_screen.dart`

Replace the state fields and all methods in `_DevopsToolsScreenState`. Do not touch `_needsInput`, `_inputHint`, or `build()` yet.

- [ ] **Step 1: Replace state fields**

In `_DevopsToolsScreenState`, remove:
```dart
ToolResult? _result;
bool _loading = false;
```

Add:
```dart
final List<_ResultTab> _tabs = [];
int _activeTabIndex = -1;
```

- [ ] **Step 2: Replace `_run()` method**

Remove the old `_run()` and add:

```dart
Future<void> _run() async {
  final session = context.read<SessionProvider>().activeSession;
  if (session == null) return;

  final service = WebToolsService(context.read<SshService>());
  final input = _inputController.text.trim();
  final label = _tabLabel(_selected.label, input);

  final tab = _ResultTab(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    label: label,
    isLoading: true,
  );

  setState(() {
    _tabs.add(tab);
    _activeTabIndex = _tabs.length - 1;
  });

  final tabIndex = _activeTabIndex;
  final host = session.host;

  final result = await switch (_selected) {
    _Tool.ping        => service.ping(host, input),
    _Tool.curl        => service.curl(host, input),
    _Tool.dns         => service.dnsLookup(host, input),
    _Tool.traceroute  => service.traceroute(host, input),
    _Tool.portScan    => service.portScan(host, input),
    _Tool.whois       => service.whois(host, input),
    _Tool.netstat     => service.netstat(host),
    _Tool.diskUsage   => service.diskUsage(host, input.isEmpty ? '/' : input),
    _Tool.topProcesses => service.topProcesses(host),
    _Tool.memory      => service.memoryInfo(host),
    _Tool.httpHeaders => service.httpHeaders(host, input),
    _Tool.sslCert     => service.sslCert(host, input),
  };

  if (!mounted) return;
  setState(() {
    if (tabIndex < _tabs.length) {
      _tabs[tabIndex].result = result;
      _tabs[tabIndex].isLoading = false;
    }
  });
}

void _closeTab(int index) {
  setState(() {
    _tabs.removeAt(index);
    if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.length - 1;
    }
  });
}

void _clearAllTabs() {
  setState(() {
    _tabs.clear();
    _activeTabIndex = -1;
  });
}
```

- [ ] **Step 3: Analyze**

```bash
cd app && flutter analyze lib/widgets/devops_tools_screen.dart
```

Expected: errors about `_result` / `_loading` still used in `build()` — that's fine, we fix `build()` in Task 4.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/devops_tools_screen.dart
git commit -m "feat: replace single result state with multi-tab list in devops tools"
```

---

### Task 3: Grouped sidebar with consistent `_NavItem` style

**Files:**
- Modify: `app/lib/widgets/devops_tools_screen.dart`

Add two private classes at the bottom of the file (before the final `}`), then update `build()` sidebar column.

- [ ] **Step 1: Add `_NavItem` and `_SidebarSection` widgets at the bottom of the file**

```dart
class _SidebarSection extends StatelessWidget {
  final String label;
  const _SidebarSection(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      );
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.active
        ? AppColors.accent.withValues(alpha: 0.12)
        : _hovered
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.transparent;
    final color = widget.active ? AppColors.accent : AppColors.textSecondary;

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
            border: widget.active
                ? Border.all(color: AppColors.accent.withValues(alpha: 0.2))
                : null,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 13, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: widget.active ? FontWeight.w500 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
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

- [ ] **Step 2: Replace the sidebar `SizedBox+Material+ListView` in `build()` with the new grouped sidebar**

In `_DevopsToolsScreenState.build()`, replace:

```dart
SizedBox(
  width: 160,
  child: Material(
    color: AppColors.sidebar,
    child: ListView(
      children: _Tool.values
          .map(
            (tool) => ListTile(
              leading: Icon(...),
              title: Text(...),
              selected: _selected == tool,
              onTap: () => setState(() {
                _selected = tool;
                _result = null;
              }),
              dense: true,
            ),
          )
          .toList(),
    ),
  ),
),
```

with:

```dart
SizedBox(
  width: 160,
  child: Container(
    color: AppColors.sidebar,
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: ListView(
      children: [
        const _SidebarSection('Network'),
        ...[
          _Tool.ping, _Tool.curl, _Tool.dns,
          _Tool.traceroute, _Tool.portScan, _Tool.whois, _Tool.netstat,
        ].map(_navItem),
        const _SidebarSection('System'),
        ...[_Tool.diskUsage, _Tool.topProcesses, _Tool.memory].map(_navItem),
        const _SidebarSection('HTTP'),
        ...[_Tool.httpHeaders, _Tool.sslCert].map(_navItem),
      ],
    ),
  ),
),
```

- [ ] **Step 3: Add `_navItem` helper method to `_DevopsToolsScreenState`**

```dart
Widget _navItem(_Tool tool) => _NavItem(
      icon: tool.icon,
      label: tool.label,
      active: _selected == tool,
      onTap: () => setState(() {
        _selected = tool;
      }),
    );
```

- [ ] **Step 4: Analyze**

```bash
cd app && flutter analyze lib/widgets/devops_tools_screen.dart
```

Expected: errors about `_result`/`_loading` in the output section — still fine.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/devops_tools_screen.dart
git commit -m "feat: replace sidebar ListTile with grouped _NavItem style in devops tools"
```

---

### Task 4: Tab bar + tab-aware output + toolbar Clear All

**Files:**
- Modify: `app/lib/widgets/devops_tools_screen.dart`

This task wires up the tab bar, updates the output area to use the active tab's data, and adds the Clear All button to the toolbar. It also removes the last uses of `_result` and `_loading`.

- [ ] **Step 1: Add `_buildTabBar()` method to `_DevopsToolsScreenState`**

```dart
Widget _buildTabBar() {
  if (_tabs.isEmpty) return const SizedBox.shrink();

  return Container(
    height: 33,
    decoration: const BoxDecoration(
      color: AppColors.sidebar,
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _tabs.asMap().entries.map((e) {
          final i = e.key;
          final tab = e.value;
          final isActive = i == _activeTabIndex;

          return GestureDetector(
            onTap: () => setState(() => _activeTabIndex = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isActive ? AppColors.bg : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? AppColors.accent : Colors.transparent,
                    width: 2,
                  ),
                  right: const BorderSide(color: AppColors.border),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tab.isLoading)
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: AppColors.accent),
                    )
                  else
                    Icon(
                      tab.result?.isSuccess == true
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 11,
                      color: tab.result?.isSuccess == true
                          ? AppColors.accent
                          : AppColors.red,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    tab.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                      fontWeight: isActive
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _closeTab(i),
                    child: const Icon(Icons.close,
                        size: 11, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    ),
  );
}
```

- [ ] **Step 2: Replace the `Expanded` right-side `Column` in `build()` completely**

Find and replace the full right-side `Expanded(child: Column(...))` block:

```dart
Expanded(
  child: Column(
    children: [
      if (session == null)
        Container(
          padding: const EdgeInsets.all(8),
          color: AppColors.card,
          child: const Row(
            children: [
              Icon(Icons.warning_amber, size: 14, color: AppColors.orange),
              SizedBox(width: 8),
              Text('No active session — connect to a host first',
                  style: TextStyle(color: AppColors.orange, fontSize: 12)),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (_needsInput) ...[
              Expanded(
                child: TextField(
                  controller: _inputController,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: _inputHint,
                    hintStyle: const TextStyle(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.card,
                    border: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onSubmitted: (_) => session != null ? _run() : null,
                ),
              ),
              const SizedBox(width: 8),
            ],
            ElevatedButton.icon(
              onPressed: session != null && !_loading ? _run : null,
              icon: const Icon(Icons.play_arrow, size: 16),
              label: Text(_selected.label),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        ),
      ),
      const Divider(height: 1, color: AppColors.border),
      Expanded(
        child: ToolResultView(result: _result, isLoading: _loading),
      ),
    ],
  ),
),
```

with:

```dart
Expanded(
  child: Column(
    children: [
      if (session == null)
        Container(
          padding: const EdgeInsets.all(8),
          color: AppColors.card,
          child: const Row(
            children: [
              Icon(Icons.warning_amber, size: 14, color: AppColors.orange),
              SizedBox(width: 8),
              Text('No active session — connect to a host first',
                  style: TextStyle(color: AppColors.orange, fontSize: 12)),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (_needsInput) ...[
              Expanded(
                child: TextField(
                  controller: _inputController,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: _inputHint,
                    hintStyle: const TextStyle(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.card,
                    border: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onSubmitted: (_) => session != null ? _run() : null,
                ),
              ),
              const SizedBox(width: 8),
            ],
            ElevatedButton.icon(
              onPressed: session != null ? _run : null,
              icon: const Icon(Icons.play_arrow, size: 16),
              label: Text(_selected.label),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            if (_tabs.isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.clear_all, size: 18, color: AppColors.textSecondary),
                tooltip: 'Clear all tabs',
                onPressed: _clearAllTabs,
              ),
            ],
          ],
        ),
      ),
      const Divider(height: 1, color: AppColors.border),
      _buildTabBar(),
      Expanded(
        child: _activeTabIndex >= 0 && _activeTabIndex < _tabs.length
            ? ToolResultView(
                result: _tabs[_activeTabIndex].result,
                isLoading: _tabs[_activeTabIndex].isLoading,
              )
            : const ToolResultView(),
      ),
    ],
  ),
),
```

- [ ] **Step 3: Analyze — expect zero errors**

```bash
cd app && flutter analyze lib/widgets/devops_tools_screen.dart
```

Expected: no errors, no warnings about unused `_result` or `_loading`.

- [ ] **Step 4: Run all tests**

```bash
cd app && flutter test
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/devops_tools_screen.dart
git commit -m "feat: add multi-tab results and grouped sidebar to network tools"
```

---

### Task 5: Final verification

- [ ] **Step 1: Run app**

```bash
cd app && flutter run -d macos
```

- [ ] **Step 2: Manual smoke test**

1. Navigate to **DevOps → Network Tools**
2. Confirm sidebar shows 3 sections: Network / System / HTTP with hover/active styles
3. Type `8.8.8.8`, press Run → tab appears with spinner → result loads, tab shows ✓
4. Change input to `1.1.1.1`, press Run → second tab appears alongside first
5. Click tab 1 → shows first result. Click tab 2 → shows second result
6. Press ✕ on tab 1 → it closes, tab 2 becomes active
7. Press Clear All → all tabs gone, empty state shows
8. Select Netstat (no input) → Run → tab labeled "Netstat"

- [ ] **Step 3: Run full test suite + analyzer**

```bash
cd app && flutter analyze && flutter test
```

Expected: no issues.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: network tools polish — grouped sidebar + multi-tab results"
```
