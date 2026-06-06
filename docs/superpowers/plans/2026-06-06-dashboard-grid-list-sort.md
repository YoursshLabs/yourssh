# Dashboard Grid/List View Toggle + Host Sorting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user switch the hosts dashboard between the existing card grid and a new compact single-line list view, and sort hosts by name / creation date / hostname; both preferences persist.

**Architecture:** A pure `sortHosts` function in `app/lib/util/host_sort.dart` sorts the flat filtered host list. Two new string prefs (`dashboardViewMode`, `dashboardSort`) follow the existing `SettingsProvider` `_load()`/`save()` pattern. In `hosts_dashboard.dart`, `_HostCard` gains a `compact` flag (list-row layout sharing all existing state/handlers — test connection, context menu, selection), a `_SortBtn` dropdown and `_ViewToggle` segmented control go into `_TopBar`, and the dashboard build sorts then renders `_HostGrid` or `_HostList`.

**Tech Stack:** Flutter (desktop), provider, shared_preferences, flutter_test.

**Spec:** `docs/superpowers/specs/2026-06-06-dashboard-grid-list-sort-design.md`

---

## File map

| File | Change |
|---|---|
| `app/lib/util/host_sort.dart` | **Create** — `HostSortMode` enum + `sortHosts` (pure Dart, no Flutter imports) |
| `app/test/util/host_sort_test.dart` | **Create** — unit tests |
| `app/lib/providers/settings_provider.dart` | **Modify** — `dashboardViewMode`, `dashboardSort` prefs |
| `app/test/settings_provider_test.dart` | **Modify** — persistence tests |
| `app/lib/widgets/hosts_dashboard.dart` | **Modify** — `_HostCard.compact`, `_HostList`, `_SortBtn`, `_ViewToggle`, `_TopBar` params, build wiring, `@visibleForTesting` factories |
| `app/test/widgets/hosts_dashboard_view_test.dart` | **Create** — widget tests for row/toggle/sort button |
| `CHANGELOG.md` | **Modify** — `[Unreleased] → Added` entry |

---

### Task 1: `HostSortMode` + `sortHosts`

**Files:**
- Create: `app/lib/util/host_sort.dart`
- Test: `app/test/util/host_sort_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `app/test/util/host_sort_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/util/host_sort.dart';

Host _host(String label, {String host = '1.1.1.1', DateTime? created}) => Host(
      label: label,
      host: host,
      username: 'root',
      createdAt: created,
    );

void main() {
  group('HostSortMode.fromKey', () {
    test('maps every key to its mode', () {
      for (final mode in HostSortMode.values) {
        expect(HostSortMode.fromKey(mode.key), mode);
      }
    });

    test('falls back to nameAsc on unknown or null', () {
      expect(HostSortMode.fromKey('bogus'), HostSortMode.nameAsc);
      expect(HostSortMode.fromKey(null), HostSortMode.nameAsc);
    });
  });

  group('sortHosts', () {
    test('nameAsc sorts case-insensitively', () {
      final sorted = sortHosts(
          [_host('zeta'), _host('Alpha'), _host('beta')], HostSortMode.nameAsc);
      expect(sorted.map((h) => h.label).toList(), ['Alpha', 'beta', 'zeta']);
    });

    test('nameDesc reverses nameAsc', () {
      final sorted = sortHosts(
          [_host('Alpha'), _host('zeta'), _host('beta')], HostSortMode.nameDesc);
      expect(sorted.map((h) => h.label).toList(), ['zeta', 'beta', 'Alpha']);
    });

    test('createdDesc puts newest first, createdAsc oldest first', () {
      final old = _host('old', created: DateTime(2024, 1, 1));
      final mid = _host('mid', created: DateTime(2025, 6, 1));
      final newest = _host('new', created: DateTime(2026, 1, 1));
      expect(sortHosts([mid, newest, old], HostSortMode.createdDesc),
          [newest, mid, old]);
      expect(sortHosts([mid, newest, old], HostSortMode.createdAsc),
          [old, mid, newest]);
    });

    test('hostAsc sorts by hostname case-insensitively', () {
      final a = _host('x', host: 'Beta.example.com');
      final b = _host('y', host: 'alpha.example.com');
      expect(sortHosts([a, b], HostSortMode.hostAsc), [b, a]);
      expect(sortHosts([a, b], HostSortMode.hostDesc), [a, b]);
    });

    test('equal keys tie-break by label then id (deterministic)', () {
      final a = _host('same', host: '9.9.9.9');
      final b = _host('same', host: '9.9.9.9');
      final expected = a.id.compareTo(b.id) < 0 ? [a, b] : [b, a];
      expect(sortHosts([a, b], HostSortMode.hostAsc), expected);
      expect(sortHosts([b, a], HostSortMode.hostAsc), expected);
    });

    test('does not mutate the input list', () {
      final input = [_host('b'), _host('a')];
      final before = List<Host>.of(input);
      sortHosts(input, HostSortMode.nameAsc);
      expect(input, before);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/util/host_sort_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'yourssh/util/host_sort.dart'` (or "Target of URI doesn't exist").

- [ ] **Step 3: Implement `host_sort.dart`**

Create `app/lib/util/host_sort.dart`:

```dart
import '../models/host.dart';

/// Dashboard host orderings. [key] is the value persisted in
/// SharedPreferences (`dashboardSort`); [label] is the dropdown text.
enum HostSortMode {
  nameAsc('name_asc', 'Name A→Z'),
  nameDesc('name_desc', 'Name Z→A'),
  createdDesc('created_desc', 'Newest first'),
  createdAsc('created_asc', 'Oldest first'),
  hostAsc('host_asc', 'Host A→Z'),
  hostDesc('host_desc', 'Host Z→A');

  const HostSortMode(this.key, this.label);
  final String key;
  final String label;

  /// Unknown or null persisted values fall back to the default.
  static HostSortMode fromKey(String? key) => values
      .firstWhere((m) => m.key == key, orElse: () => HostSortMode.nameAsc);
}

/// Returns a new list sorted by [mode]. Comparisons on label/host are
/// case-insensitive; ties break by label then id so the order is stable
/// across rebuilds regardless of input order.
List<Host> sortHosts(List<Host> hosts, HostSortMode mode) {
  int byLabel(Host a, Host b) {
    final c = a.label.toLowerCase().compareTo(b.label.toLowerCase());
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  int cmp(Host a, Host b) {
    switch (mode) {
      case HostSortMode.nameAsc:
        return byLabel(a, b);
      case HostSortMode.nameDesc:
        return byLabel(b, a);
      case HostSortMode.createdDesc:
        final c = b.createdAt.compareTo(a.createdAt);
        return c != 0 ? c : byLabel(a, b);
      case HostSortMode.createdAsc:
        final c = a.createdAt.compareTo(b.createdAt);
        return c != 0 ? c : byLabel(a, b);
      case HostSortMode.hostAsc:
        final c = a.host.toLowerCase().compareTo(b.host.toLowerCase());
        return c != 0 ? c : byLabel(a, b);
      case HostSortMode.hostDesc:
        final c = b.host.toLowerCase().compareTo(a.host.toLowerCase());
        return c != 0 ? c : byLabel(a, b);
    }
  }

  return List<Host>.of(hosts)..sort(cmp);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/util/host_sort_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/util/host_sort.dart app/test/util/host_sort_test.dart
git commit -m "feat(dashboard): HostSortMode enum and pure sortHosts helper"
```

---

### Task 2: `SettingsProvider` prefs

**Files:**
- Modify: `app/lib/providers/settings_provider.dart`
- Test: `app/test/settings_provider_test.dart`

- [ ] **Step 1: Write the failing tests**

Append inside `main()` of `app/test/settings_provider_test.dart` (the file already mocks SharedPreferences in `setUp`):

```dart
  test('dashboard prefs default to grid and name_asc', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.dashboardViewMode, 'grid');
    expect(provider.dashboardSort, 'name_asc');
  });

  test('save persists dashboardViewMode and dashboardSort', () async {
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    await provider.save(dashboardViewMode: 'list', dashboardSort: 'created_desc');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('dashboardViewMode'), 'list');
    expect(prefs.getString('dashboardSort'), 'created_desc');
    expect(provider.dashboardViewMode, 'list');
    expect(provider.dashboardSort, 'created_desc');
  });

  test('loads persisted dashboard prefs on init', () async {
    SharedPreferences.setMockInitialValues({
      'dashboardViewMode': 'list',
      'dashboardSort': 'host_asc',
    });
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(provider.dashboardViewMode, 'list');
    expect(provider.dashboardSort, 'host_asc');
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/settings_provider_test.dart`
Expected: FAIL — `The getter 'dashboardViewMode' isn't defined for the class 'SettingsProvider'`.

- [ ] **Step 3: Implement the prefs**

In `app/lib/providers/settings_provider.dart`:

1. Add fields after `String recordingPath = '';` (line 19):

```dart
  /// Hosts dashboard layout: 'grid' (cards) or 'list' (compact rows).
  /// Anything else is treated as 'grid' at the point of use.
  String dashboardViewMode = 'grid';

  /// Hosts dashboard ordering; a HostSortMode key. Unknown values fall
  /// back to name_asc via HostSortMode.fromKey.
  String dashboardSort = 'name_asc';
```

2. In `_load()`, after the `recordingPath` line:

```dart
    dashboardViewMode = prefs.getString('dashboardViewMode') ?? 'grid';
    dashboardSort = prefs.getString('dashboardSort') ?? 'name_asc';
```

3. In `save(...)`, add parameters after `String? recordingPath,`:

```dart
    String? dashboardViewMode,
    String? dashboardSort,
```

then after `if (recordingPath != null) this.recordingPath = recordingPath;`:

```dart
    if (dashboardViewMode != null) this.dashboardViewMode = dashboardViewMode;
    if (dashboardSort != null) this.dashboardSort = dashboardSort;
```

and after `await prefs.setString('recordingPath', this.recordingPath);`:

```dart
    await prefs.setString('dashboardViewMode', this.dashboardViewMode);
    await prefs.setString('dashboardSort', this.dashboardSort);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/settings_provider_test.dart`
Expected: PASS (all tests, including pre-existing ones).

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/settings_provider.dart app/test/settings_provider_test.dart
git commit -m "feat(settings): persist dashboardViewMode and dashboardSort prefs"
```

---

### Task 3: Move `_HostCard` provider reads into callbacks (prep refactor)

`_HostCardState.build` currently does `context.read<SessionProvider>()` / `context.read<HostProvider>()` at build time (lines 729–730 of `app/lib/widgets/hosts_dashboard.dart`), which forces every widget test to scaffold providers. Move the reads into the callbacks that use them so the row can be pumped bare. No behavior change.

**Files:**
- Modify: `app/lib/widgets/hosts_dashboard.dart`

- [ ] **Step 1: Remove build-time reads**

In `_HostCardState.build`, delete:

```dart
    final sessionProvider = context.read<SessionProvider>();
    final hostProvider = context.read<HostProvider>();
```

and change the `onDoubleTap` line to:

```dart
        onDoubleTap: widget.selectionMode
            ? null
            : () => context.read<SessionProvider>().connect(widget.host),
```

- [ ] **Step 2: Make `_showMenu` self-sufficient**

Change the more-menu trigger:

```dart
                _iconBtn(Icons.more_horiz, 'More', onTapDown: (d) => _showMenu(context, d.globalPosition)),
```

and the `_showMenu` signature/body:

```dart
  void _showMenu(BuildContext context, Offset tapPosition) {
    final hostProvider = context.read<HostProvider>();
    final sessionProvider = context.read<SessionProvider>();
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
```

(The rest of `_showMenu` is unchanged.)

- [ ] **Step 3: Analyze and run existing tests**

Run: `cd app && flutter analyze && flutter test test/widgets/hosts_dashboard_menu_test.dart test/widgets/facet_chip_bar_test.dart`
Expected: `No issues found!` and PASS.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/hosts_dashboard.dart
git commit -m "refactor(dashboard): read providers in _HostCard callbacks, not build"
```

---

### Task 4: `_HostCard` compact (list-row) layout

`compact: true` renders the single-line row from the spec; `compact: false` (default) keeps the card layout byte-for-byte. All state (`_hovered`, `_testing`, `_testResult`) and handlers are shared.

**Files:**
- Modify: `app/lib/widgets/hosts_dashboard.dart` (`_HostCard`, plus a `hostListRowForTest` factory next to `facetChipBarForTest`)
- Test: `app/test/widgets/hosts_dashboard_view_test.dart` (create)

- [ ] **Step 1: Write the failing widget tests**

Create `app/test/widgets/hosts_dashboard_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/widgets/hosts_dashboard.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Column(children: [child])));

void main() {
  group('host list row', () {
    testWidgets('shows label and user@host, hides default port', (tester) async {
      await tester.pumpWidget(_wrap(hostListRowForTest(
        host: Host(label: 'Web', host: '10.0.0.1', username: 'root'),
      )));
      expect(find.text('Web'), findsOneWidget);
      expect(find.text('root@10.0.0.1'), findsOneWidget);
    });

    testWidgets('appends non-default port', (tester) async {
      await tester.pumpWidget(_wrap(hostListRowForTest(
        host: Host(label: 'Web', host: '10.0.0.1', username: 'root', port: 2222),
      )));
      expect(find.text('root@10.0.0.1:2222'), findsOneWidget);
    });

    testWidgets('no checkbox outside selection mode', (tester) async {
      await tester.pumpWidget(_wrap(hostListRowForTest(
        host: Host(label: 'Web', host: '10.0.0.1', username: 'root'),
      )));
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('selection mode shows checkbox and row tap toggles', (tester) async {
      var toggled = 0;
      await tester.pumpWidget(_wrap(hostListRowForTest(
        host: Host(label: 'Web', host: '10.0.0.1', username: 'root'),
        selectionMode: true,
        onToggleSelect: () => toggled++,
      )));
      expect(find.byType(Checkbox), findsOneWidget);
      await tester.tap(find.text('Web'));
      expect(toggled, 1);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/widgets/hosts_dashboard_view_test.dart`
Expected: FAIL — `The function 'hostListRowForTest' isn't defined`.

- [ ] **Step 3: Implement the compact layout**

In `app/lib/widgets/hosts_dashboard.dart`:

1. Add the field + constructor param to `_HostCard`:

```dart
class _HostCard extends StatefulWidget {
  final Host host;
  final void Function(Host)? onEditHost;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelect;

  /// false → grid card; true → single-line list row.
  final bool compact;
  const _HostCard({
    required this.host,
    this.onEditHost,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelect,
    this.compact = false,
  });
```

2. Parametrize `_osIcon` sizes (replace the existing method):

```dart
  Widget _osIcon(Host host, {double pad = 8, double svg = 20, double fallback = 18}) {
    final asset = osIconAsset(host.detectedOs);
    if (asset != null) {
      return Padding(
        padding: EdgeInsets.all(pad),
        child: SvgPicture.asset(
          asset,
          width: svg,
          height: svg,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      );
    }
    return Icon(Icons.dns, color: Colors.white, size: fallback);
  }
```

3. Restructure `build` so card and row share the container/gestures and the trailing widgets. Replace the whole `build` method body with:

```dart
  @override
  Widget build(BuildContext context) {
    final color = AppColors.hostColor(widget.host.id);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.selectionMode ? widget.onToggleSelect : null,
        onDoubleTap: widget.selectionMode
            ? null
            : () => context.read<SessionProvider>().connect(widget.host),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: 14, vertical: widget.compact ? 8 : 12),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.cardHover : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: widget.selected ? AppColors.accent : _hovered ? AppColors.border.withValues(alpha: 0.8) : AppColors.border),
          ),
          child: widget.compact ? _compactRow(context, color) : _cardRow(context, color),
        ),
      ),
    );
  }
```

4. Add the three new builders right after `build`. `_cardRow` is the existing card `Row` moved verbatim (with the trailing section replaced by the shared `_trailing`); `_selectionCheckbox` is the existing checkbox extracted because both layouts use it:

```dart
  Widget _selectionCheckbox() => SizedBox(
        width: 18,
        height: 18,
        child: Checkbox(
          value: widget.selected,
          onChanged: (_) => widget.onToggleSelect?.call(),
          activeColor: AppColors.accent,
          side: const BorderSide(color: AppColors.border),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );

  /// Hover actions / spinner / test result — shared by both layouts.
  /// [maxResultWidth] bounds the error text so a long message can't
  /// overflow the single-line list row.
  List<Widget> _trailing(BuildContext context, {double? maxResultWidth}) {
    Widget resultText = Text(
      _testResult == null
          ? ''
          : _testResult!.success
              ? '${_testResult!.latencyMs}ms'
              : (_testResult!.error ?? 'Failed'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: (_testResult?.success ?? false) ? AppColors.accent : AppColors.red,
        fontSize: 11,
      ),
    );
    if (maxResultWidth != null) {
      resultText = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxResultWidth),
        child: resultText,
      );
    }
    return [
      if (!widget.selectionMode && _hovered && !_testing && _testResult == null) ...[
        _iconBtn(Icons.network_check, 'Test Connection', onTap: _test),
        const SizedBox(width: 2),
        _iconBtn(Icons.folder_outlined, 'SFTP', onTap: () => _openSftp(context)),
        const SizedBox(width: 2),
        _iconBtn(Icons.more_horiz, 'More', onTapDown: (d) => _showMenu(context, d.globalPosition)),
      ],
      if (_testing)
        const SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textSecondary),
        ),
      if (_testResult != null) ...[
        Icon(
          _testResult!.success ? Icons.check_circle_outline : Icons.error_outline,
          size: 14,
          color: _testResult!.success ? AppColors.accent : AppColors.red,
        ),
        const SizedBox(width: 4),
        resultText,
      ],
    ];
  }

  Widget _cardRow(BuildContext context, Color color) {
    return Row(
      children: [
        if (widget.selectionMode) ...[
          _selectionCheckbox(),
          const SizedBox(width: 10),
        ],
        // Host icon
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _osIcon(widget.host),
        ),
        const SizedBox(width: 10),

        // Host info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Status dot
                  Container(
                    width: 6, height: 6,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: const BoxDecoration(
                      color: AppColors.red, // offline by default
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.host.label,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.host.username}@${widget.host.host}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        ..._trailing(context),
      ],
    );
  }

  /// Single-line list row: dot/checkbox · small OS icon · label ·
  /// user@host[:port] · test result · hover actions.
  Widget _compactRow(BuildContext context, Color color) {
    final port = widget.host.port == 22 ? '' : ':${widget.host.port}';
    return Row(
      children: [
        if (widget.selectionMode)
          _selectionCheckbox()
        else
          Container(
            width: 6, height: 6,
            decoration: const BoxDecoration(
              color: AppColors.red, // offline by default
              shape: BoxShape.circle,
            ),
          ),
        const SizedBox(width: 10),
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: _osIcon(widget.host, pad: 5, svg: 14, fallback: 13),
        ),
        const SizedBox(width: 10),
        // Fixed label column so rows align vertically.
        SizedBox(
          width: 220,
          child: Text(
            widget.host.label,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${widget.host.username}@${widget.host.host}$port',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        ..._trailing(context, maxResultWidth: 260),
      ],
    );
  }
```

5. Delete the now-moved card `Row(...)` (and the old inline checkbox/trailing code) that previously lived in `build`.

6. Add the test factory at the bottom of the file, next to `facetChipBarForTest`:

```dart
/// Test-only entry point to the private compact host row.
@visibleForTesting
Widget hostListRowForTest({
  required Host host,
  bool selectionMode = false,
  bool selected = false,
  VoidCallback? onToggleSelect,
}) =>
    _HostCard(
      host: host,
      compact: true,
      selectionMode: selectionMode,
      selected: selected,
      onToggleSelect: onToggleSelect,
    );
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/hosts_dashboard_view_test.dart && flutter analyze`
Expected: PASS, `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/hosts_dashboard.dart app/test/widgets/hosts_dashboard_view_test.dart
git commit -m "feat(dashboard): compact list-row layout for _HostCard"
```

---

### Task 5: `_SortBtn` + `_ViewToggle` widgets

**Files:**
- Modify: `app/lib/widgets/hosts_dashboard.dart` (new widgets + test factories; import `../util/host_sort.dart`)
- Test: `app/test/widgets/hosts_dashboard_view_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Append inside `main()` of `app/test/widgets/hosts_dashboard_view_test.dart`, and add the import `import 'package:yourssh/util/host_sort.dart';` at the top:

```dart
  group('view toggle', () {
    testWidgets('reports mode on tap and highlights active side', (tester) async {
      String? changed;
      await tester.pumpWidget(_wrap(viewToggleForTest(
        viewMode: 'grid',
        onChanged: (v) => changed = v,
      )));
      expect(find.byIcon(Icons.grid_view), findsOneWidget);
      expect(find.byIcon(Icons.view_list), findsOneWidget);

      await tester.tap(find.byIcon(Icons.view_list));
      expect(changed, 'list');

      await tester.tap(find.byIcon(Icons.grid_view));
      expect(changed, 'grid');
    });
  });

  group('sort button', () {
    testWidgets('shows current mode label', (tester) async {
      await tester.pumpWidget(_wrap(sortButtonForTest(
        mode: HostSortMode.nameAsc,
        onChanged: (_) {},
      )));
      expect(find.text('Name A→Z'), findsOneWidget);
    });

    testWidgets('opens menu and reports the picked mode', (tester) async {
      HostSortMode? picked;
      await tester.pumpWidget(_wrap(sortButtonForTest(
        mode: HostSortMode.nameAsc,
        onChanged: (m) => picked = m,
      )));
      await tester.tap(find.text('Name A→Z'));
      await tester.pumpAndSettle();
      expect(find.text('Newest first'), findsOneWidget);

      await tester.tap(find.text('Newest first'));
      await tester.pumpAndSettle();
      expect(picked, HostSortMode.createdDesc);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd app && flutter test test/widgets/hosts_dashboard_view_test.dart`
Expected: FAIL — `The function 'viewToggleForTest' isn't defined`.

- [ ] **Step 3: Implement the widgets**

In `app/lib/widgets/hosts_dashboard.dart`:

1. Add the import:

```dart
import '../util/host_sort.dart';
```

2. Add both widgets right after the `_OutlinedBtn` class:

```dart
/// Dropdown button showing the current sort mode; opens a menu with all
/// HostSortMode values.
class _SortBtn extends StatelessWidget {
  final HostSortMode mode;
  final ValueChanged<HostSortMode> onChanged;
  const _SortBtn({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (d) => _openMenu(context, d.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(mode.label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.3)),
            const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<HostSortMode>(
      context: context,
      color: AppColors.card,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final m in HostSortMode.values)
          PopupMenuItem<HostSortMode>(
            value: m,
            height: 36,
            child: Row(
              children: [
                Icon(Icons.check,
                    size: 14,
                    color: m == mode ? AppColors.accent : Colors.transparent),
                const SizedBox(width: 8),
                Text(m.label,
                    style: TextStyle(
                        color: m == mode ? AppColors.textPrimary : AppColors.textSecondary,
                        fontSize: 13)),
              ],
            ),
          ),
      ],
    );
    if (selected != null) onChanged(selected);
  }
}

/// Segmented grid/list switch for the hosts dashboard.
class _ViewToggle extends StatelessWidget {
  final String viewMode; // 'grid' | 'list'
  final ValueChanged<String> onChanged;
  const _ViewToggle({required this.viewMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _segment(Icons.grid_view, 'Grid view', 'grid'),
            Container(width: 1, height: 27, color: AppColors.border),
            _segment(Icons.view_list, 'List view', 'list'),
          ],
        ),
      ),
    );
  }

  Widget _segment(IconData icon, String tooltip, String mode) {
    final active = viewMode == mode;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => onChanged(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          color: active ? AppColors.card : Colors.transparent,
          child: Icon(icon, size: 13, color: active ? AppColors.textPrimary : AppColors.textSecondary),
        ),
      ),
    );
  }
}
```

3. Add the test factories at the bottom of the file:

```dart
/// Test-only entry point to the private sort dropdown button.
@visibleForTesting
Widget sortButtonForTest({
  required HostSortMode mode,
  required ValueChanged<HostSortMode> onChanged,
}) =>
    _SortBtn(mode: mode, onChanged: onChanged);

/// Test-only entry point to the private grid/list view toggle.
@visibleForTesting
Widget viewToggleForTest({
  required String viewMode,
  required ValueChanged<String> onChanged,
}) =>
    _ViewToggle(viewMode: viewMode, onChanged: onChanged);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/hosts_dashboard_view_test.dart && flutter analyze`
Expected: PASS, `No issues found!` (the new widgets are referenced by the factories, so no unused-element warnings).

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/hosts_dashboard.dart app/test/widgets/hosts_dashboard_view_test.dart
git commit -m "feat(dashboard): sort dropdown and grid/list view toggle widgets"
```

---

### Task 6: Wire sort + view mode through `_TopBar` and the dashboard build

**Files:**
- Modify: `app/lib/widgets/hosts_dashboard.dart` (`_TopBar`, `_HostsDashboardState.build`, new `_HostList`)

- [ ] **Step 1: Extend `_TopBar`**

Add the four params:

```dart
class _TopBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final int totalHosts;
  final int filteredCount;
  final VoidCallback? onAddHost;
  final VoidCallback? onLocalTerminal;
  final VoidCallback? onNewGroup;
  final VoidCallback? onImport;
  final VoidCallback? onSelect;
  final HostSortMode sortMode;
  final ValueChanged<HostSortMode> onSortChanged;
  final String viewMode;
  final ValueChanged<String> onViewChanged;

  const _TopBar({
    required this.controller,
    required this.onSearch,
    required this.totalHosts,
    required this.filteredCount,
    this.onAddHost,
    this.onLocalTerminal,
    this.onNewGroup,
    this.onImport,
    this.onSelect,
    required this.sortMode,
    required this.onSortChanged,
    required this.viewMode,
    required this.onViewChanged,
  });
```

In its `build`, replace

```dart
          const SizedBox(width: 16),
          _OutlinedBtn(
            icon: Icons.check_box_outlined,
```

with

```dart
          const SizedBox(width: 16),
          _SortBtn(mode: sortMode, onChanged: onSortChanged),
          const SizedBox(width: 8),
          _ViewToggle(viewMode: viewMode, onChanged: onViewChanged),
          const SizedBox(width: 8),
          _OutlinedBtn(
            icon: Icons.check_box_outlined,
```

- [ ] **Step 2: Add `_HostList`**

Right after the `_HostGrid` class:

```dart
class _HostList extends StatelessWidget {
  final List<Host> hosts;
  final void Function(Host)? onEditHost;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(Host)? onToggleSelect;
  const _HostList({
    required this.hosts,
    this.onEditHost,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final h in hosts)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _HostCard(
              host: h,
              compact: true,
              onEditHost: onEditHost,
              selectionMode: selectionMode,
              selected: selectedIds.contains(h.id),
              onToggleSelect: () => onToggleSelect?.call(h),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 3: Wire the dashboard build**

In `app/lib/widgets/hosts_dashboard.dart`:

1. Add the import:

```dart
import '../providers/settings_provider.dart';
```

2. In `_HostsDashboardState.build`, after `final filtered = ...;` add:

```dart
    final settings = context.watch<SettingsProvider>();
    final sortMode = HostSortMode.fromKey(settings.dashboardSort);
    final sorted = sortHosts(filtered, sortMode);
    final listView = settings.dashboardViewMode == 'list';
```

3. Extend the `_TopBar(...)` call:

```dart
              : _TopBar(
                  controller: _searchController,
                  onSearch: (v) => setState(() => _search = v),
                  totalHosts: hosts.length,
                  filteredCount: filtered.length,
                  onAddHost: widget.onAddHost,
                  onLocalTerminal: widget.onOpenLocalTerminal,
                  onNewGroup: widget.onNewGroup,
                  onImport: widget.onImport,
                  onSelect: _enterSelectionMode,
                  sortMode: sortMode,
                  onSortChanged: (m) =>
                      context.read<SettingsProvider>().save(dashboardSort: m.key),
                  viewMode: settings.dashboardViewMode,
                  onViewChanged: (v) => context
                      .read<SettingsProvider>()
                      .save(dashboardViewMode: v),
                ),
```

4. Replace the `_HostGrid(...)` call at the bottom of `build`:

```dart
                  else if (listView)
                    _HostList(
                      hosts: sorted,
                      onEditHost: widget.onEditHost,
                      selectionMode: _selectionMode,
                      selectedIds: _selectedHostIds,
                      onToggleSelect: _toggleSelected,
                    )
                  else
                    _HostGrid(
                      hosts: sorted,
                      onEditHost: widget.onEditHost,
                      selectionMode: _selectionMode,
                      selectedIds: _selectedHostIds,
                      onToggleSelect: _toggleSelected,
                    ),
```

(The preceding `if (filtered.isEmpty && _search.isEmpty) _EmptyState(...)` branch stays as is.)

- [ ] **Step 4: Analyze and run the full widget test suite**

Run: `cd app && flutter analyze && flutter test test/widgets/ test/util/ test/settings_provider_test.dart`
Expected: `No issues found!`, all PASS.

- [ ] **Step 5: Manual smoke test**

Note: the spec's dashboard-level widget tests (toggle switches layout, sort
reorders, selection survives a switch) are covered here manually instead —
pumping the full `HostsDashboard` would require scaffolding `HostProvider`,
`SessionProvider`, `SshService`, and `StorageService`; the wiring itself is a
thin ternary over components already covered by the targeted tests above.

Run: `cd app && flutter run -d macos`
Verify:
- Sort dropdown shows "Name A→Z" by default; hosts are alphabetical.
- Picking "Newest first" reorders; restart the app → choice persisted.
- View toggle switches cards ↔ single-line rows; restart → persisted.
- In list view: hover shows Test/SFTP/menu buttons; Test shows inline `✓ Nms` / `✗ error`; double-click connects.
- SELECT mode: checkboxes appear in both views; switching views keeps the selection; Esc exits.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/hosts_dashboard.dart
git commit -m "feat(dashboard): grid/list view toggle and host sorting wired to settings"
```

---

### Task 7: Changelog

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add the entry**

Under `## [Unreleased]` → `### Added`, append:

```markdown
- **Grid & List view for the hosts dashboard** — toggle between the card
  grid and a compact single-line list; pick a sort order (name, creation
  date, or hostname, ascending/descending) from the new toolbar dropdown.
  Both choices persist across restarts. Default order is now Name A→Z
  (previously insertion order).
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): dashboard grid/list view and sorting"
```
