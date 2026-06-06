# Host Chain Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the JUMP HOST dropdown in the host detail panel with a Termius-style visual connection-chain editor (single hop, UI only).

**Architecture:** New pure-presentational widget `HostChainEditor` (no provider reads — all data via constructor, single `onSelect` output) rendered by `host_detail_panel.dart` in place of the old dropdown `_Card`. Backend (`Host.jumpHostId`, `SshService`) untouched. Spec: `docs/superpowers/specs/2026-06-06-host-chain-editor-design.md`.

**Tech Stack:** Flutter, flutter_svg (OS glyphs via `osIconAsset`), flutter_test widget tests.

---

### Task 1: `HostChainEditor` — empty state

**Files:**
- Create: `app/lib/widgets/host_chain_editor.dart`
- Test: `app/test/widgets/host_chain_editor_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `app/test/widgets/host_chain_editor_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/widgets/host_chain_editor.dart';

Host makeHost(String id, String label,
        {String user = 'root', String addr = '10.0.0.1', String? os}) =>
    Host(id: id, label: label, host: addr, username: user, detectedOs: os);

Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 360, child: child),
        ),
      ),
    );

void main() {
  testWidgets('empty state shows helper text and Add a Host', (tester) async {
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      candidates: [makeHost('h1', 'bastion')],
      onSelect: (_) {},
    )));

    expect(find.text('Add a Host'), findsOneWidget);
    expect(
      find.textContaining('prod-db', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Clear'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets/host_chain_editor_test.dart`
Expected: FAIL — `host_chain_editor.dart` does not exist (compile error).

- [ ] **Step 3: Write the empty-state implementation**

Create `app/lib/widgets/host_chain_editor.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/host.dart';
import '../services/os_detection.dart';
import '../theme/app_theme.dart';

/// Termius-style visual chain editor for the single-hop jump host.
///
/// Pure presentational: data in via constructor, the only output is
/// [onSelect] — a picked jump host, or null when the user taps Clear.
/// Spec: docs/superpowers/specs/2026-06-06-host-chain-editor-design.md
class HostChainEditor extends StatelessWidget {
  /// Label of the host being edited (bottom card / helper text).
  final String currentHostLabel;

  /// detectedOs of the host being edited (null → generic glyph).
  final String? currentHostOs;

  /// The selected jump host, or null for a direct connection.
  final Host? jumpHost;

  /// Shows the key glyph on the jump card when agent forwarding is on.
  final bool agentForwarding;

  /// Hosts selectable as jump (caller excludes the host being edited).
  final List<Host> candidates;

  final ValueChanged<Host?> onSelect;

  const HostChainEditor({
    super.key,
    required this.currentHostLabel,
    this.currentHostOs,
    this.jumpHost,
    this.agentForwarding = false,
    required this.candidates,
    required this.onSelect,
  });

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<Host>(
      context: context,
      builder: (_) => _HostPickerDialog(candidates: candidates),
    );
    if (picked != null) onSelect(picked);
  }

  @override
  Widget build(BuildContext context) {
    final jump = jumpHost;
    if (jump == null) return _emptyState(context);
    return _chain(context, jump);
  }

  Widget _emptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              text: 'Adding a host will route the connection to ',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12, height: 1.4),
              children: [
                TextSpan(
                  text: currentHostLabel,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _pick(context),
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.cardHover,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Add a Host',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Chain state added in Task 2.
  Widget _chain(BuildContext context, Host jump) => const SizedBox.shrink();
}

// Picker dialog added in Task 3.
class _HostPickerDialog extends StatelessWidget {
  final List<Host> candidates;
  const _HostPickerDialog({required this.candidates});

  @override
  Widget build(BuildContext context) => const Dialog();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/widgets/host_chain_editor_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/host_chain_editor.dart app/test/widgets/host_chain_editor_test.dart
git commit -m "feat(chain): HostChainEditor empty state with Add a Host"
```

---

### Task 2: `HostChainEditor` — chain state (cards, arrow, key icon, Clear)

**Files:**
- Modify: `app/lib/widgets/host_chain_editor.dart`
- Test: `app/test/widgets/host_chain_editor_test.dart`

- [ ] **Step 1: Add the failing tests**

Append inside `main()` of `app/test/widgets/host_chain_editor_test.dart`:

```dart
  testWidgets('chain state shows both cards, arrow and Clear', (tester) async {
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      jumpHost: makeHost('h1', 'bastion'),
      candidates: [makeHost('h1', 'bastion')],
      onSelect: (_) {},
    )));

    expect(find.text('bastion'), findsOneWidget);
    expect(find.text('prod-db'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Add a Host'), findsNothing);
  });

  testWidgets('key icon shows iff agentForwarding', (tester) async {
    final jump = makeHost('h1', 'bastion');
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      jumpHost: jump,
      agentForwarding: true,
      candidates: [jump],
      onSelect: (_) {},
    )));
    expect(find.byIcon(Icons.key), findsOneWidget);

    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      jumpHost: jump,
      agentForwarding: false,
      candidates: [jump],
      onSelect: (_) {},
    )));
    expect(find.byIcon(Icons.key), findsNothing);
  });

  testWidgets('Clear tap fires onSelect(null)', (tester) async {
    Host? selected = makeHost('sentinel', 's');
    var fired = false;
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      jumpHost: makeHost('h1', 'bastion'),
      candidates: const [],
      onSelect: (h) {
        fired = true;
        selected = h;
      },
    )));

    await tester.tap(find.text('Clear'));
    expect(fired, isTrue);
    expect(selected, isNull);
  });
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `cd app && flutter test test/widgets/host_chain_editor_test.dart`
Expected: first test PASS, the 3 new tests FAIL (chain renders `SizedBox.shrink`).

- [ ] **Step 3: Implement chain state**

In `app/lib/widgets/host_chain_editor.dart`, replace the `_chain` stub with:

```dart
  Widget _chain(BuildContext context, Host jump) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HostCard(
          label: jump.label.isNotEmpty
              ? jump.label
              : '${jump.username}@${jump.host}',
          detectedOs: jump.detectedOs,
          trailing: agentForwarding
              ? const Tooltip(
                  message:
                      'Agent forwarding on — this hop can use your local keys',
                  child: Icon(Icons.key, size: 14, color: AppColors.accent),
                )
              : null,
          onTap: () => _pick(context),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Icon(Icons.arrow_downward,
              size: 16, color: AppColors.textTertiary),
        ),
        _HostCard(label: currentHostLabel, detectedOs: currentHostOs),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => onSelect(null),
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Clear',
              style: TextStyle(
                  color: AppColors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
```

And add the `_HostCard` widget at the bottom of the file (above `_HostPickerDialog`):

```dart
/// One host row in the chain: OS glyph tile + label (+ optional trailing).
class _HostCard extends StatelessWidget {
  final String label;
  final String? detectedOs;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _HostCard({
    required this.label,
    this.detectedOs,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final asset = osIconAsset(detectedOs);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.cardHover,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: asset != null
                  ? SvgPicture.asset(
                      asset,
                      width: 16,
                      height: 16,
                      colorFilter: const ColorFilter.mode(
                          AppColors.textPrimary, BlendMode.srcIn),
                    )
                  : const Icon(Icons.dns_outlined,
                      size: 15, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/host_chain_editor_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/host_chain_editor.dart app/test/widgets/host_chain_editor_test.dart
git commit -m "feat(chain): chain state with host cards, arrow, key icon, Clear"
```

---

### Task 3: Host picker dialog with search

**Files:**
- Modify: `app/lib/widgets/host_chain_editor.dart`
- Test: `app/test/widgets/host_chain_editor_test.dart`

- [ ] **Step 1: Add the failing test**

Append inside `main()`:

```dart
  testWidgets('picker filters by search and returns picked host',
      (tester) async {
    Host? selected;
    await tester.pumpWidget(wrap(HostChainEditor(
      currentHostLabel: 'prod-db',
      candidates: [
        makeHost('h1', 'bastion', addr: '10.0.0.1'),
        makeHost('h2', 'staging', addr: '10.0.0.2'),
      ],
      onSelect: (h) => selected = h,
    )));

    await tester.tap(find.text('Add a Host'));
    await tester.pumpAndSettle();

    // Both candidates listed.
    expect(find.text('bastion'), findsOneWidget);
    expect(find.text('staging'), findsOneWidget);

    // Search narrows the list.
    await tester.enterText(find.byType(TextField), 'stag');
    await tester.pumpAndSettle();
    expect(find.text('bastion'), findsNothing);
    expect(find.text('staging'), findsOneWidget);

    // Picking returns the host.
    await tester.tap(find.text('staging'));
    await tester.pumpAndSettle();
    expect(selected?.id, 'h2');
    expect(find.byType(Dialog), findsNothing);
  });
```

- [ ] **Step 2: Run tests to verify the new one fails**

Run: `cd app && flutter test test/widgets/host_chain_editor_test.dart`
Expected: 4 PASS, the picker test FAILS (dialog is an empty `Dialog`).

- [ ] **Step 3: Implement the picker dialog**

Replace the `_HostPickerDialog` stub with:

```dart
/// Searchable list of candidate jump hosts. Pops with the picked [Host].
class _HostPickerDialog extends StatefulWidget {
  final List<Host> candidates;
  const _HostPickerDialog({required this.candidates});

  @override
  State<_HostPickerDialog> createState() => _HostPickerDialogState();
}

class _HostPickerDialogState extends State<_HostPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.candidates
        : widget.candidates
            .where((h) =>
                h.label.toLowerCase().contains(q) ||
                '${h.username}@${h.host}'.toLowerCase().contains(q))
            .toList();
    return Dialog(
      backgroundColor: AppColors.sidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search hosts…',
                  hintStyle: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 13),
                  prefixIcon: const Icon(Icons.search,
                      size: 16, color: AppColors.textTertiary),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: Text('No hosts found',
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 12)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final h = filtered[i];
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(h),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    h.label.isNotEmpty
                                        ? h.label
                                        : '${h.username}@${h.host}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 13),
                                  ),
                                  Text(
                                    '${h.username}@${h.host}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/widgets/host_chain_editor_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/host_chain_editor.dart app/test/widgets/host_chain_editor_test.dart
git commit -m "feat(chain): searchable host picker dialog"
```

---

### Task 4: Wire `HostChainEditor` into the host detail panel

**Files:**
- Modify: `app/lib/widgets/host_detail_panel.dart` (imports; `_sectionLabel('JUMP HOST')`; the jump-host `Builder` block, currently ~lines 336–387)

- [ ] **Step 1: Add import and label helper**

In `app/lib/widgets/host_detail_panel.dart` add to imports:

```dart
import 'host_chain_editor.dart';
```

Add this method to `_HostDetailPanelState` (next to `_clearTestResult`):

```dart
  /// Display label for the host being edited, used by the chain editor.
  /// Falls back to user@host while the label field is still empty.
  String _currentHostLabel() {
    final label = _labelCtrl.text.trim();
    if (label.isNotEmpty) return label;
    final host = _hostCtrl.text.trim();
    if (host.isEmpty) return 'this host';
    final user = _usernameCtrl.text.trim();
    return user.isEmpty ? host : '$user@$host';
  }
```

- [ ] **Step 2: Replace the dropdown block**

Change `_sectionLabel('JUMP HOST')` to `_sectionLabel('CONNECTION CHAIN')`.

Inside the existing `Builder` (keep `allHosts` / `otherHosts` / `isEmpty` guard / `validJump` stale-id cleanup exactly as they are), replace only the `return _Card(children: [ _DropdownRow(...) ]);` statement with:

```dart
                    final jump = validJump == null
                        ? null
                        : otherHosts.firstWhere((h) => h.id == validJump);
                    return ListenableBuilder(
                      // Live-update the bottom card while typing label/host.
                      listenable: Listenable.merge(
                          [_labelCtrl, _usernameCtrl, _hostCtrl]),
                      builder: (context, _) => HostChainEditor(
                        currentHostLabel: _currentHostLabel(),
                        currentHostOs: widget.existing?.detectedOs,
                        jumpHost: jump,
                        agentForwarding: _agentForwarding,
                        candidates: otherHosts,
                        onSelect: (h) =>
                            setState(() => _selectedJumpHostId = h?.id),
                      ),
                    );
```

- [ ] **Step 3: Analyze and run the panel's existing tests**

Run: `cd app && flutter analyze && flutter test test/widgets/host_detail_panel_agent_forwarding_test.dart test/widgets/host_chain_editor_test.dart`
Expected: analyze clean; all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/host_detail_panel.dart
git commit -m "feat(chain): replace JUMP HOST dropdown with HostChainEditor"
```

---

### Task 5: Full verification

- [ ] **Step 1: Run the full test suite**

Run: `cd app && flutter test`
Expected: all tests PASS.

- [ ] **Step 2: Run analyzer**

Run: `cd app && flutter analyze`
Expected: No issues found.

- [ ] **Step 3: Commit any straggler fixes; otherwise nothing to commit**
