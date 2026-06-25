# Mobile UI Redesign (Termius-style) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reskin the four mobile screens (Hosts / Sessions / SFTP / Settings) plus Add-host to a Termius-class look and feel, on a shared mobile design system, without changing any provider/service/navigation logic.

**Architecture:** Add an additive mobile token + shared-widget layer (`app/lib/mobile/theme/`, `app/lib/mobile/widgets/`), then reskin each screen on top of it. New testable units (initials, status mapping, cursor-drag→key mapping) are pure Dart and unit-tested; screens get widget tests for presence/behavior.

**Tech Stack:** Flutter (Material 3, dark-only), `provider`, `xterm` (`TerminalKey`/`TerminalView`), existing `AppColors` in `app/lib/theme/app_theme.dart`.

## Global Constraints

- Dark theme only; all colors come from `AppColors` (`app/lib/theme/app_theme.dart`). Per-host variety uses the existing `AppColors.hostColor(seed)`.
- Primary accent stays `AppColors.accent` (`#22C55E`); seeded host colors drive avatars/left-bars only.
- Do NOT modify `SshService`, providers, sync, app-lock, or TOFU logic. Reskin only.
- Phone layout only — no tablet/foldable multi-pane, no iPad sidebar.
- No RDP/VNC on mobile (mobile is SSH-only today; keep it that way).
- Run `cd app && flutter analyze` clean and `cd app && flutter test` green before each commit.
- No Claude attribution anywhere in commits/code/docs.
- Commit messages in English; conventional-commit style matching the repo (`feat(mobile): …`, `refactor(mobile): …`, `test(mobile): …`).

---

## File Structure

**New:**
- `app/lib/mobile/theme/mobile_tokens.dart` — spacing/radii/size constants.
- `app/lib/mobile/widgets/host_avatar.dart` — `HostAvatar` + pure `hostInitials()`.
- `app/lib/mobile/widgets/status_dot.dart` — `StatusDot` + `HostConnState` + `statusColor()`.
- `app/lib/mobile/widgets/tag_chip.dart` — `TagChip`.
- `app/lib/mobile/widgets/section_header.dart` — `SectionHeader`.
- `app/lib/mobile/widgets/mobile_card.dart` — `MobileCard`.
- `app/lib/mobile/widgets/host_card.dart` — `HostCard` (composes the above; used by Hosts).
- `app/lib/mobile/terminal/terminal_cursor_gestures.dart` — pure `CursorDragMapper`.
- `app/lib/mobile/terminal/terminal_side_panel.dart` — `TerminalSidePanel` bottom sheet (Keys/Snippets/History/Themes).
- Tests under `app/test/mobile/…` mirroring the above.

**Modified (reskin only):**
- `app/lib/mobile/screens/mobile_hosts_screen.dart`
- `app/lib/mobile/screens/mobile_sessions_screen.dart`
- `app/lib/mobile/terminal/accessory_key_bar.dart`
- `app/lib/mobile/screens/mobile_sftp_screen.dart`
- `app/lib/mobile/screens/mobile_settings_screen.dart`
- `app/lib/mobile/screens/mobile_add_host_screen.dart`

---

## Milestone 1 — Design system foundation

### Task 1: Mobile tokens

**Files:**
- Create: `app/lib/mobile/theme/mobile_tokens.dart`

**Interfaces:**
- Produces: `class MobileTokens` with static `double` consts: `space1=4, space2=8, space3=12, space4=16, space5=24, radiusCard=14, radiusPill=22, radiusAvatar=12, avatar=44, statusDot=8, accessoryBarHeight=48, touchTarget=44`.

- [ ] **Step 1: Create the tokens file**

```dart
// app/lib/mobile/theme/mobile_tokens.dart
/// Layout constants for the mobile UI. Colors live in [AppColors]; this is
/// purely spacing/sizing so widgets share one rhythm.
class MobileTokens {
  MobileTokens._();

  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;

  static const double radiusCard = 14;
  static const double radiusPill = 22;
  static const double radiusAvatar = 12;

  static const double avatar = 44;
  static const double statusDot = 8;
  static const double accessoryBarHeight = 48;
  static const double touchTarget = 44;
}
```

- [ ] **Step 2: Analyze**

Run: `cd app && flutter analyze lib/mobile/theme/mobile_tokens.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add app/lib/mobile/theme/mobile_tokens.dart
git commit -m "feat(mobile): add shared layout tokens"
```

### Task 2: HostAvatar + initials

**Files:**
- Create: `app/lib/mobile/widgets/host_avatar.dart`
- Test: `app/test/mobile/host_avatar_test.dart`

**Interfaces:**
- Produces: `String hostInitials(String label)` — up to 2 uppercase letters; `class HostAvatar extends StatelessWidget` with `HostAvatar({required String label, required String seed, double size})`.
- Consumes: `MobileTokens`, `AppColors`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/mobile/host_avatar_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/widgets/host_avatar.dart';

void main() {
  group('hostInitials', () {
    test('two words → first letter of each, uppercased', () {
      expect(hostInitials('production web'), 'PW');
    });
    test('single word → first two letters', () {
      expect(hostInitials('staging'), 'ST');
    });
    test('single letter → one letter', () {
      expect(hostInitials('x'), 'X');
    });
    test('blank → empty', () {
      expect(hostInitials('   '), '');
    });
    test('skips non-letter leading tokens', () {
      expect(hostInitials('10.0.0.5'), '1');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/host_avatar_test.dart`
Expected: FAIL — `host_avatar.dart` does not exist / `hostInitials` undefined.

- [ ] **Step 3: Implement**

```dart
// app/lib/mobile/widgets/host_avatar.dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../theme/mobile_tokens.dart';

/// Up to two uppercase initials from a host label. Words are whitespace-split;
/// two-plus words use the first letter of the first two, a single word uses its
/// first two characters. Returns '' for blank input.
String hostInitials(String label) {
  final words = label.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '';
  if (words.length == 1) {
    final w = words.first;
    return (w.length == 1 ? w : w.substring(0, 2)).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

/// Rounded-square avatar: seeded background tint + initials in the seed color.
/// Falls back to a terminal glyph when the label yields no initials.
class HostAvatar extends StatelessWidget {
  final String label;
  final String seed;
  final double size;

  const HostAvatar({
    super.key,
    required this.label,
    required this.seed,
    this.size = MobileTokens.avatar,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.hostColor(seed);
    final initials = hostInitials(label);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(MobileTokens.radiusAvatar),
      ),
      child: initials.isEmpty
          ? Icon(Icons.dns_outlined, color: color, size: size * 0.5)
          : Text(
              initials,
              style: TextStyle(
                color: color,
                fontSize: size * 0.36,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/mobile/host_avatar_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/widgets/host_avatar.dart app/test/mobile/host_avatar_test.dart
git commit -m "feat(mobile): add HostAvatar with seeded initials"
```

### Task 3: StatusDot + state mapping

**Files:**
- Create: `app/lib/mobile/widgets/status_dot.dart`
- Test: `app/test/mobile/status_dot_test.dart`

**Interfaces:**
- Produces: `enum HostConnState { connected, connecting, offline }`; `Color statusColor(HostConnState s)`; `class StatusDot extends StatelessWidget` with `StatusDot({required HostConnState state, double size})`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/mobile/status_dot_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh/mobile/widgets/status_dot.dart';

void main() {
  test('statusColor maps each state', () {
    expect(statusColor(HostConnState.connected), AppColors.accent);
    expect(statusColor(HostConnState.connecting), AppColors.orange);
    expect(statusColor(HostConnState.offline), AppColors.textTertiary);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/status_dot_test.dart`
Expected: FAIL — undefined.

- [ ] **Step 3: Implement**

```dart
// app/lib/mobile/widgets/status_dot.dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../theme/mobile_tokens.dart';

/// Coarse connection state for a host row / session, decoupled from
/// [SessionStatus] so this widget stays provider-free.
enum HostConnState { connected, connecting, offline }

Color statusColor(HostConnState s) => switch (s) {
      HostConnState.connected => AppColors.accent,
      HostConnState.connecting => AppColors.orange,
      HostConnState.offline => AppColors.textTertiary,
    };

class StatusDot extends StatelessWidget {
  final HostConnState state;
  final double size;

  const StatusDot({
    super.key,
    required this.state,
    this.size = MobileTokens.statusDot,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: statusColor(state),
        shape: BoxShape.circle,
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/mobile/status_dot_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/widgets/status_dot.dart app/test/mobile/status_dot_test.dart
git commit -m "feat(mobile): add StatusDot + connection-state mapping"
```

### Task 4: TagChip, SectionHeader, MobileCard

**Files:**
- Create: `app/lib/mobile/widgets/tag_chip.dart`, `app/lib/mobile/widgets/section_header.dart`, `app/lib/mobile/widgets/mobile_card.dart`
- Test: `app/test/mobile/shared_widgets_test.dart`

**Interfaces:**
- Produces: `class TagChip extends StatelessWidget` (`TagChip({required String label, bool selected, VoidCallback? onTap})`); `class SectionHeader extends StatelessWidget` (`SectionHeader(this.title)`); `class MobileCard extends StatelessWidget` (`MobileCard({required Widget child, VoidCallback? onTap, EdgeInsets? padding})`).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/mobile/shared_widgets_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/widgets/tag_chip.dart';
import 'package:yourssh/mobile/widgets/section_header.dart';
import 'package:yourssh/mobile/widgets/mobile_card.dart';

void main() {
  testWidgets('TagChip renders label', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: TagChip(label: 'prod'))));
    expect(find.text('prod'), findsOneWidget);
  });

  testWidgets('SectionHeader uppercases the title', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: SectionHeader('security'))));
    expect(find.text('SECURITY'), findsOneWidget);
  });

  testWidgets('MobileCard fires onTap', (t) async {
    var tapped = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MobileCard(onTap: () => tapped = true, child: const Text('x')),
      ),
    ));
    await t.tap(find.text('x'));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/shared_widgets_test.dart`
Expected: FAIL — undefined widgets.

- [ ] **Step 3: Implement the three widgets**

```dart
// app/lib/mobile/widgets/tag_chip.dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../theme/mobile_tokens.dart';

/// Compact pill for a host tag or a filter chip. [selected] tints it with the
/// accent; tappable when [onTap] is provided.
class TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const TagChip({super.key, required this.label, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.black : AppColors.textSecondary;
    final bg = selected ? AppColors.accent : AppColors.bg;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: MobileTokens.space2, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11)),
    );
    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
      onTap: onTap,
      child: chip,
    );
  }
}
```

```dart
// app/lib/mobile/widgets/section_header.dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../theme/mobile_tokens.dart';

/// Uppercase, letter-spaced section label for grouped lists/settings.
class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: MobileTokens.space1,
        bottom: MobileTokens.space2,
        top: MobileTokens.space2,
      ),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
```

```dart
// app/lib/mobile/widgets/mobile_card.dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../theme/mobile_tokens.dart';

/// The single source of card styling for the mobile UI: card surface, rounded
/// border, ripple. Used by host rows, SFTP rows, settings groups.
class MobileCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? padding;

  const MobileCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(MobileTokens.radiusCard),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(MobileTokens.space3),
          child: child,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/mobile/shared_widgets_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/widgets/tag_chip.dart app/lib/mobile/widgets/section_header.dart app/lib/mobile/widgets/mobile_card.dart app/test/mobile/shared_widgets_test.dart
git commit -m "feat(mobile): add TagChip, SectionHeader, MobileCard"
```

---

## Milestone 2 — Hosts screen

### Task 5: HostCard widget

**Files:**
- Create: `app/lib/mobile/widgets/host_card.dart`
- Test: `app/test/mobile/host_card_test.dart`

**Interfaces:**
- Consumes: `HostAvatar`, `StatusDot`/`HostConnState`, `TagChip`, `MobileCard`, `MobileTokens`, `AppColors`, `Host`.
- Produces: `class HostCard extends StatelessWidget` with `HostCard({required Host host, required HostConnState state, required VoidCallback onTap, VoidCallback? onLongPress})`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/mobile/host_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/mobile/widgets/host_card.dart';
import 'package:yourssh/mobile/widgets/status_dot.dart';

void main() {
  testWidgets('renders label, target, tags, and fires onTap', (t) async {
    final host = Host(
      label: 'Production Web',
      host: '10.0.0.5',
      port: 22,
      username: 'root',
      tags: const ['prod', 'nginx'],
    );
    var tapped = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostCard(
          host: host,
          state: HostConnState.connected,
          onTap: () => tapped = true,
        ),
      ),
    ));
    expect(find.text('Production Web'), findsOneWidget);
    expect(find.text('root@10.0.0.5:22'), findsOneWidget);
    expect(find.text('prod'), findsOneWidget);
    expect(find.text('nginx'), findsOneWidget);
    await t.tap(find.text('Production Web'));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/host_card_test.dart`
Expected: FAIL — `host_card.dart` missing.

- [ ] **Step 3: Implement**

```dart
// app/lib/mobile/widgets/host_card.dart
import 'package:flutter/material.dart';

import '../../models/host.dart';
import '../../theme/app_theme.dart';
import '../theme/mobile_tokens.dart';
import 'host_avatar.dart';
import 'mobile_card.dart';
import 'status_dot.dart';
import 'tag_chip.dart';

/// Termius-style host row: seeded avatar + label + user@host:port + tag chips,
/// with a connection status dot and a trailing chevron.
class HostCard extends StatelessWidget {
  final Host host;
  final HostConnState state;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const HostCard({
    super.key,
    required this.host,
    required this.state,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MobileTokens.space3,
        vertical: MobileTokens.space1 + 2,
      ),
      child: MobileCard(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Row(
          children: [
            HostAvatar(label: host.label, seed: host.host),
            const SizedBox(width: MobileTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          host.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      StatusDot(state: state),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${host.username}@${host.host}:${host.port}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  if (host.tags.isNotEmpty) ...[
                    const SizedBox(height: MobileTokens.space2),
                    Wrap(
                      spacing: MobileTokens.space1 + 2,
                      runSpacing: MobileTokens.space1,
                      children: [for (final tag in host.tags) TagChip(label: tag)],
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/mobile/host_card_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/widgets/host_card.dart app/test/mobile/host_card_test.dart
git commit -m "feat(mobile): add HostCard row"
```

### Task 6: Reskin Hosts screen (cards + filter chips + long-press delete + empty state)

**Files:**
- Modify: `app/lib/mobile/screens/mobile_hosts_screen.dart` (full rewrite of the build + helpers; keep `MobileHostsScreen` constructor/`onConnected`/`onAddHost` signature and `_connect`)
- Test: `app/test/mobile/mobile_hosts_screen_test.dart`

**Interfaces:**
- Consumes: `HostProvider.allHosts` / `HostProvider.deleteHost(id)`, `SessionProvider.connectAny(host)` / `SessionProvider.sshSessions`, `HostQuery.parse`, `HostCard`, `HostConnState`, `TagChip`, `MobileTokens`.

- [ ] **Step 1: Write the failing widget test**

```dart
// app/test/mobile/mobile_hosts_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/mobile/screens/mobile_hosts_screen.dart';
import 'package:yourssh/mobile/widgets/host_card.dart';
import 'package:yourssh/providers/host_provider.dart';

// Minimal fake exposing just what the screen reads.
class _FakeHostProvider extends HostProvider {
  _FakeHostProvider(this._hosts);
  final List<Host> _hosts;
  @override
  List<Host> get allHosts => _hosts;
}

void main() {
  Host h(String label, String addr) =>
      Host(label: label, host: addr, username: 'root');

  testWidgets('empty state shows add CTA', (t) async {
    await t.pumpWidget(_wrap(_FakeHostProvider([])));
    expect(find.textContaining('No hosts'), findsOneWidget);
  });

  testWidgets('renders a HostCard per host', (t) async {
    await t.pumpWidget(_wrap(_FakeHostProvider([h('Alpha', '1.1.1.1'), h('Beta', '2.2.2.2')])));
    expect(find.byType(HostCard), findsNWidgets(2));
  });
}

Widget _wrap(HostProvider hp) {
  return MultiProvider(
    providers: [ChangeNotifierProvider<HostProvider>.value(value: hp)],
    child: MaterialApp(
      home: MobileHostsScreen(onConnected: () {}, onAddHost: () {}),
    ),
  );
}
```

> NOTE: If `HostProvider`'s constructor requires args, adapt `_FakeHostProvider` to satisfy them (pass through to `super`). If `SessionProvider` is read during build for status, add a `ChangeNotifierProvider<SessionProvider>` with an empty fake to `_wrap`. Verify by reading `host_provider.dart` / `session_provider.dart` constructors before writing the fake.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/mobile_hosts_screen_test.dart`
Expected: FAIL — still rendering `ListTile`/`_HostRow` (no `HostCard`).

- [ ] **Step 3: Rewrite the screen**

Replace the entire body of `app/lib/mobile/screens/mobile_hosts_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/host.dart';
import '../../models/ssh_session.dart';
import '../../providers/host_provider.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_theme.dart';
import '../../util/host_query.dart';
import '../theme/mobile_tokens.dart';
import '../widgets/host_card.dart';
import '../widgets/status_dot.dart';
import '../widgets/tag_chip.dart';

/// Hosts tab: searchable list of saved hosts as Termius-style cards; tap to
/// connect, long-press to delete, FAB to add. Tag chips filter the list.
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
  String? _tagFilter;

  /// Coarse connection state for a host, derived from any live session on it.
  HostConnState _stateFor(Host host, List<SshSession> sessions) {
    final mine = sessions.where((s) => s.host.id == host.id);
    if (mine.any((s) => s.status == SessionStatus.connected)) {
      return HostConnState.connected;
    }
    if (mine.any((s) => s.status == SessionStatus.connecting)) {
      return HostConnState.connecting;
    }
    return HostConnState.offline;
  }

  @override
  Widget build(BuildContext context) {
    final all = context.watch<HostProvider>().allHosts;
    final sessions = context.watch<SessionProvider>().sshSessions;

    final tags = <String>{for (final h in all) ...h.tags}.toList()..sort();

    var hosts = all;
    final q = _query.trim();
    if (q.isNotEmpty) {
      hosts = hosts.where(HostQuery.parse(q).matches).toList();
    }
    if (_tagFilter != null) {
      hosts = hosts.where((h) => h.tags.contains(_tagFilter)).toList();
    }

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
              padding: const EdgeInsets.fromLTRB(
                MobileTokens.space3,
                MobileTokens.space3,
                MobileTokens.space3,
                MobileTokens.space2,
              ),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search hosts',
                  prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.card,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (tags.isNotEmpty)
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: MobileTokens.space3),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: MobileTokens.space2),
                      child: TagChip(
                        label: 'All',
                        selected: _tagFilter == null,
                        onTap: () => setState(() => _tagFilter = null),
                      ),
                    ),
                    for (final tag in tags)
                      Padding(
                        padding: const EdgeInsets.only(right: MobileTokens.space2),
                        child: TagChip(
                          label: tag,
                          selected: _tagFilter == tag,
                          onTap: () => setState(
                              () => _tagFilter = _tagFilter == tag ? null : tag),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: hosts.isEmpty
                  ? _EmptyState(onAddHost: widget.onAddHost)
                  : ListView.builder(
                      padding: const EdgeInsets.only(
                          top: MobileTokens.space2, bottom: 80),
                      itemCount: hosts.length,
                      itemBuilder: (_, i) => HostCard(
                        host: hosts[i],
                        state: _stateFor(hosts[i], sessions),
                        onTap: () => _connect(hosts[i]),
                        onLongPress: () => _confirmDelete(hosts[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _connect(Host host) {
    context.read<SessionProvider>().connectAny(host);
    widget.onConnected();
  }

  Future<void> _confirmDelete(Host host) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Delete ${host.label}?',
            style: const TextStyle(color: AppColors.textPrimary)),
        content: const Text('This removes the saved host and its credentials.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<HostProvider>().deleteHost(host.id);
    }
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAddHost;
  const _EmptyState({required this.onAddHost});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.dns_outlined, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: MobileTokens.space3),
          const Text('No hosts yet',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
          const SizedBox(height: MobileTokens.space1),
          const Text('Add a server to get started',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: MobileTokens.space4),
          FilledButton.icon(
            onPressed: onAddHost,
            icon: const Icon(Icons.add),
            label: const Text('Add host'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the screen test + full mobile suite**

Run: `cd app && flutter test test/mobile/`
Expected: PASS. Then `cd app && flutter analyze` → "No issues found!".

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/screens/mobile_hosts_screen.dart app/test/mobile/mobile_hosts_screen_test.dart
git commit -m "feat(mobile): Termius-style hosts list with cards, tag filter, delete"
```

---

## Milestone 3 — Terminal ergonomics

### Task 7: Cursor-drag → arrow-key mapper (pure)

**Files:**
- Create: `app/lib/mobile/terminal/terminal_cursor_gestures.dart`
- Test: `app/test/mobile/terminal_cursor_gestures_test.dart`

**Interfaces:**
- Produces: `class CursorDragMapper` with `CursorDragMapper({double baseStep = 22})`, `List<TerminalKey> addDelta(double dx, double dy)`, `void reset()`.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/mobile/terminal_cursor_gestures_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/mobile/terminal/terminal_cursor_gestures.dart';

void main() {
  test('horizontal drag emits arrowRight per step', () {
    final m = CursorDragMapper(baseStep: 20);
    expect(m.addDelta(20, 0), [TerminalKey.arrowRight]);
    expect(m.addDelta(20, 0), [TerminalKey.arrowRight]);
  });

  test('negative vertical drag emits arrowUp', () {
    final m = CursorDragMapper(baseStep: 20);
    expect(m.addDelta(0, -20), [TerminalKey.arrowUp]);
  });

  test('sub-step deltas accumulate then fire once', () {
    final m = CursorDragMapper(baseStep: 20);
    expect(m.addDelta(0, 12), isEmpty);
    expect(m.addDelta(0, 12), [TerminalKey.arrowDown]);
  });

  test('dominant axis wins (no diagonal double-fire)', () {
    final m = CursorDragMapper(baseStep: 20);
    expect(m.addDelta(30, 5), [TerminalKey.arrowRight]);
  });

  test('reset clears accumulators and gear', () {
    final m = CursorDragMapper(baseStep: 20);
    m.addDelta(100, 0);
    m.reset();
    expect(m.addDelta(0, 19), isEmpty); // back to gear 1, sub-step
  });

  test('acceleration: step shrinks after sustained drag', () {
    final m = CursorDragMapper(baseStep: 20);
    // First burst pushes emitted count up into a higher gear.
    m.addDelta(200, 0); // many arrowRight
    // After gear-up, a 12px delta should now be enough to fire.
    final keys = m.addDelta(12, 0);
    expect(keys, isNotEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/terminal_cursor_gestures_test.dart`
Expected: FAIL — undefined.

- [ ] **Step 3: Implement**

```dart
// app/lib/mobile/terminal/terminal_cursor_gestures.dart
import 'package:xterm/xterm.dart';

/// Translates a long-press drag into a stream of arrow-key presses, the
/// touch way to move the terminal cursor. Distance is accumulated; every
/// `step` pixels in the dominant axis emits one arrow key. The step shrinks
/// across three gears the longer a single drag persists, so a slow nudge moves
/// one cell while a long sweep flies. Pure + deterministic for unit testing;
/// call [reset] when the drag ends.
class CursorDragMapper {
  final double baseStep;
  CursorDragMapper({this.baseStep = 22});

  double _accX = 0;
  double _accY = 0;
  int _emitted = 0;

  double get _step {
    if (_emitted >= 12) return baseStep * 0.4; // gear 3
    if (_emitted >= 5) return baseStep * 0.65; // gear 2
    return baseStep; // gear 1
  }

  List<TerminalKey> addDelta(double dx, double dy) {
    _accX += dx;
    _accY += dy;
    final keys = <TerminalKey>[];
    while (true) {
      final step = _step;
      final xReady = _accX.abs() >= step;
      final yReady = _accY.abs() >= step;
      if (!xReady && !yReady) break;
      final useX = xReady && (!yReady || _accX.abs() >= _accY.abs());
      if (useX) {
        keys.add(_accX > 0 ? TerminalKey.arrowRight : TerminalKey.arrowLeft);
        _accX += _accX > 0 ? -step : step;
      } else {
        keys.add(_accY > 0 ? TerminalKey.arrowDown : TerminalKey.arrowUp);
        _accY += _accY > 0 ? -step : step;
      }
      _emitted++;
    }
    return keys;
  }

  void reset() {
    _accX = 0;
    _accY = 0;
    _emitted = 0;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/mobile/terminal_cursor_gestures_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/terminal/terminal_cursor_gestures.dart app/test/mobile/terminal_cursor_gestures_test.dart
git commit -m "feat(mobile): cursor-drag to arrow-key mapper"
```

### Task 8: Regroup the accessory key bar + side-panel trigger

**Files:**
- Modify: `app/lib/mobile/terminal/accessory_key_bar.dart`
- Test: `app/test/mobile/accessory_key_bar_test.dart`

**Interfaces:**
- Produces (new optional param): `AccessoryKeyBar({..., VoidCallback? onOpenPanel})` — adds a leading keyboard button that calls `onOpenPanel` when non-null. Existing `controller`/`onKey`/`onText` unchanged.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/mobile/accessory_key_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/mobile/terminal/accessory_bar_controller.dart';
import 'package:yourssh/mobile/terminal/accessory_key_bar.dart';

void main() {
  testWidgets('Esc/Tab/Ctrl render and Ctrl arms one-shot', (t) async {
    final c = AccessoryBarController();
    final keys = <(TerminalKey, bool)>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccessoryKeyBar(
          controller: c,
          onKey: (k, {ctrl = false, alt = false}) => keys.add((k, ctrl)),
          onText: (_) {},
        ),
      ),
    ));
    expect(find.text('Esc'), findsOneWidget);
    expect(find.text('Tab'), findsOneWidget);
    await t.tap(find.text('Ctrl'));
    await t.pump();
    expect(c.ctrlArmed, isTrue);
    await t.tap(find.text('Esc'));
    expect(keys.single, (TerminalKey.escape, true));
    expect(c.ctrlArmed, isFalse); // consumed
  });

  testWidgets('onOpenPanel button fires when provided', (t) async {
    var opened = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccessoryKeyBar(
          controller: AccessoryBarController(),
          onKey: (k, {ctrl = false, alt = false}) {},
          onText: (_) {},
          onOpenPanel: () => opened = true,
        ),
      ),
    ));
    await t.tap(find.byIcon(Icons.keyboard_outlined));
    expect(opened, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/accessory_key_bar_test.dart`
Expected: FAIL — `onOpenPanel` param missing.

- [ ] **Step 3: Modify the bar**

In `accessory_key_bar.dart`: add the field + a leading button. Add to the constructor and fields:

```dart
  final void Function(String text) onText;
  /// Opens the terminal side panel (extended keyboard / snippets / history /
  /// themes). When null the leading keyboard button is hidden.
  final VoidCallback? onOpenPanel;

  const AccessoryKeyBar({
    super.key,
    required this.controller,
    required this.onKey,
    required this.onText,
    this.onOpenPanel,
  });
```

Update the container height to the token and prepend the panel button + a divider before `_btn('Esc', …)`:

```dart
        return Container(
          height: MobileTokens.accessoryBarHeight,
          color: AppColors.card,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            children: [
              if (onOpenPanel != null)
                _icon(Icons.keyboard_outlined, 'Keyboard panel', onOpenPanel!),
              _btn('Esc', onTap: () => _key(TerminalKey.escape)),
              _btn('Tab', onTap: () => _key(TerminalKey.tab)),
              _btn('Ctrl', armed: controller.ctrlArmed, onTap: controller.armCtrl),
              _btn('Alt', armed: controller.altArmed, onTap: controller.armAlt),
              _btn('^C', onTap: () => _ctrlKey(TerminalKey.keyC)),
              _btn('^D', onTap: () => _ctrlKey(TerminalKey.keyD)),
              _icon(Icons.keyboard_arrow_left, 'Left', () => _key(TerminalKey.arrowLeft)),
              _icon(Icons.keyboard_arrow_up, 'Up', () => _key(TerminalKey.arrowUp)),
              _icon(Icons.keyboard_arrow_down, 'Down', () => _key(TerminalKey.arrowDown)),
              _icon(Icons.keyboard_arrow_right, 'Right', () => _key(TerminalKey.arrowRight)),
              for (final ch in const ['/', '-', '|', '~', ':', '\$'])
                _btn(ch, onTap: () => _text(ch)),
            ],
          ),
        );
```

Add the import at the top: `import '../theme/mobile_tokens.dart';`

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd app && flutter test test/mobile/accessory_key_bar_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/terminal/accessory_key_bar.dart app/test/mobile/accessory_key_bar_test.dart
git commit -m "feat(mobile): accessory bar gains a side-panel button + \$ key"
```

### Task 9: Terminal side panel (Keys / Snippets / History / Themes)

**Files:**
- Create: `app/lib/mobile/terminal/terminal_side_panel.dart`
- Test: `app/test/mobile/terminal_side_panel_test.dart`

**Interfaces:**
- Consumes: `SnippetProvider` (via existing `MobileSnippetsSheet` content pattern), `CommandHistoryProvider.historyFor(sessionId).entries`, `TerminalAppearanceControls`, `AppColors`, `MobileTokens`.
- Produces: `Future<void> showTerminalSidePanel(BuildContext context, {required String sessionId, required void Function(String) onInsert, required void Function(TerminalKey, {bool ctrl, bool alt}) onKey, int initialTab = 0})` — opens a `showModalBottomSheet` with a 4-tab segmented body.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/mobile/terminal_side_panel_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/providers/command_history_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh/mobile/terminal/terminal_side_panel.dart';

void main() {
  testWidgets('shows the four tabs', (t) async {
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CommandHistoryProvider()),
          ChangeNotifierProvider(create: (_) => SnippetProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showTerminalSidePanel(
                    ctx,
                    sessionId: 's1',
                    onInsert: (_) {},
                    onKey: (k, {ctrl = false, alt = false}) {},
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Keys'), findsOneWidget);
    expect(find.text('Snippets'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Themes'), findsOneWidget);
  });
}
```

> NOTE: Adjust provider constructors to match the real ones (read `command_history_provider.dart`, `snippet_provider.dart`, `settings_provider.dart` before writing — some may need a service/prefs arg or a no-arg test constructor). If a provider can't be cheaply constructed in a test, inject the data the panel needs via parameters instead of reading it from a provider, and simplify this test accordingly.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/mobile/terminal_side_panel_test.dart`
Expected: FAIL — `terminal_side_panel.dart` missing.

- [ ] **Step 3: Implement the panel**

```dart
// app/lib/mobile/terminal/terminal_side_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

import '../../providers/command_history_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/terminal_appearance_controls.dart';
import '../theme/mobile_tokens.dart';

/// Termius-style terminal side panel as a bottom sheet: Keys (extended
/// keyboard), Snippets, Command History, and Themes. Insertions/keys are
/// routed back to the active session via the callbacks.
Future<void> showTerminalSidePanel(
  BuildContext context, {
  required String sessionId,
  required void Function(String text) onInsert,
  required void Function(TerminalKey key, {bool ctrl, bool alt}) onKey,
  int initialTab = 0,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(MobileTokens.radiusCard)),
    ),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.6,
      child: _SidePanel(
        sessionId: sessionId,
        onInsert: onInsert,
        onKey: onKey,
        initialTab: initialTab,
      ),
    ),
  );
}

class _SidePanel extends StatefulWidget {
  final String sessionId;
  final void Function(String text) onInsert;
  final void Function(TerminalKey key, {bool ctrl, bool alt}) onKey;
  final int initialTab;

  const _SidePanel({
    required this.sessionId,
    required this.onInsert,
    required this.onKey,
    required this.initialTab,
  });

  @override
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel> with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 4, vsync: this, initialIndex: widget.initialTab);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          TabBar(
            controller: _tabs,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.accent,
            tabs: const [
              Tab(text: 'Keys'),
              Tab(text: 'Snippets'),
              Tab(text: 'History'),
              Tab(text: 'Themes'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _KeysGrid(onKey: widget.onKey, onClose: () => Navigator.pop(context)),
                _SnippetsTab(onInsert: (c) {
                  widget.onInsert(c);
                  Navigator.pop(context);
                }),
                _HistoryTab(sessionId: widget.sessionId, onInsert: (c) {
                  widget.onInsert(c);
                  Navigator.pop(context);
                }),
                const SingleChildScrollView(
                  padding: EdgeInsets.all(MobileTokens.space4),
                  child: TerminalAppearanceControls(layout: AppearanceControlsLayout.rows),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeysGrid extends StatelessWidget {
  final void Function(TerminalKey key, {bool ctrl, bool alt}) onKey;
  final VoidCallback onClose;
  const _KeysGrid({required this.onKey, required this.onClose});

  static const _keys = <(String, TerminalKey)>[
    ('Esc', TerminalKey.escape),
    ('Tab', TerminalKey.tab),
    ('Home', TerminalKey.home),
    ('End', TerminalKey.end),
    ('PgUp', TerminalKey.pageUp),
    ('PgDn', TerminalKey.pageDown),
    ('↑', TerminalKey.arrowUp),
    ('↓', TerminalKey.arrowDown),
    ('←', TerminalKey.arrowLeft),
    ('→', TerminalKey.arrowRight),
    ('F1', TerminalKey.f1),
    ('F2', TerminalKey.f2),
    ('F3', TerminalKey.f3),
    ('F4', TerminalKey.f4),
    ('F5', TerminalKey.f5),
    ('F6', TerminalKey.f6),
    ('F7', TerminalKey.f7),
    ('F8', TerminalKey.f8),
    ('F9', TerminalKey.f9),
    ('F10', TerminalKey.f10),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 5,
      padding: const EdgeInsets.all(MobileTokens.space3),
      mainAxisSpacing: MobileTokens.space2,
      crossAxisSpacing: MobileTokens.space2,
      childAspectRatio: 1.8,
      children: [
        for (final (label, key) in _keys)
          InkWell(
            borderRadius: BorderRadius.circular(MobileTokens.radiusAvatar),
            onTap: () => onKey(key),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(MobileTokens.radiusAvatar),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
            ),
          ),
      ],
    );
  }
}

class _SnippetsTab extends StatefulWidget {
  final void Function(String command) onInsert;
  const _SnippetsTab({required this.onInsert});

  @override
  State<_SnippetsTab> createState() => _SnippetsTabState();
}

class _SnippetsTabState extends State<_SnippetsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = context.watch<SnippetProvider>().snippets;
    final shown = filterSnippets(all, _query);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(MobileTokens.space3),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Search snippets',
              prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
            ),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const Center(
                  child: Text('No snippets',
                      style: TextStyle(color: AppColors.textSecondary)))
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final s = shown[i];
                    return ListTile(
                      title: Text(s.label,
                          style: const TextStyle(color: AppColors.textPrimary)),
                      subtitle: Text(s.command,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                      onTap: () => widget.onInsert(s.command),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final String sessionId;
  final void Function(String command) onInsert;
  const _HistoryTab({required this.sessionId, required this.onInsert});

  @override
  Widget build(BuildContext context) {
    final entries =
        context.watch<CommandHistoryProvider>().historyFor(sessionId).entries;
    if (entries.isEmpty) {
      return const Center(
          child: Text('No command history yet',
              style: TextStyle(color: AppColors.textSecondary)));
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final cmd = entries[entries.length - 1 - i]; // newest first
        return ListTile(
          title: Text(cmd,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontFamily: 'monospace', fontSize: 13)),
          onTap: () => onInsert(cmd),
        );
      },
    );
  }
}
```

> NOTE: Before running, confirm each `TerminalKey` value used (`home`, `end`, `pageUp`, `pageDown`, `f1`…`f10`) exists in the `xterm` fork's `TerminalKey` enum. If any name differs, drop or rename it — `flutter analyze` will flag unknown members.

- [ ] **Step 4: Run tests + analyze**

Run: `cd app && flutter test test/mobile/terminal_side_panel_test.dart && flutter analyze`
Expected: PASS + "No issues found!".

- [ ] **Step 5: Commit**

```bash
git add app/lib/mobile/terminal/terminal_side_panel.dart app/test/mobile/terminal_side_panel_test.dart
git commit -m "feat(mobile): terminal side panel (keys/snippets/history/themes)"
```

### Task 10: Wire side panel + cursor gestures + pill tabs into the Sessions screen

**Files:**
- Modify: `app/lib/mobile/screens/mobile_sessions_screen.dart`

**Interfaces:**
- Consumes: `showTerminalSidePanel(...)`, `CursorDragMapper`, `AccessoryKeyBar(onOpenPanel:)`, existing `SessionProvider.setActive`, `session.terminal.keyInput/textInput`.

- [ ] **Step 1: Replace the snippets-only icon with the side-panel trigger**

In `_MobileSessionsScreenState`, replace `_openSnippets` with a panel opener and update the toolbar `IconButton`:

```dart
  void _openPanel(SshSession active, {int initialTab = 0}) {
    showTerminalSidePanel(
      context,
      sessionId: active.id,
      onInsert: (cmd) => active.terminal.textInput(cmd),
      onKey: (k, {ctrl = false, alt = false}) =>
          active.terminal.keyInput(k, ctrl: ctrl, alt: alt),
      initialTab: initialTab,
    );
  }
```

In `build`, change the toolbar button to:

```dart
                IconButton(
                  icon: const Icon(Icons.dashboard_customize_outlined,
                      color: AppColors.textSecondary),
                  tooltip: 'Keyboard, snippets, history, themes',
                  onPressed: () => _openPanel(active),
                ),
```

Add the import: `import '../terminal/terminal_side_panel.dart';` and remove the now-unused `import '../terminal/mobile_snippets_sheet.dart';` if no longer referenced.

- [ ] **Step 2: Pass the panel opener into `_SessionBody` → `AccessoryKeyBar`**

Add `final VoidCallback onOpenPanel;` to `_SessionBody`, thread it from `build` (`onOpenPanel: () => _openPanel(active)`), and pass `onOpenPanel: onOpenPanel` to `AccessoryKeyBar`.

- [ ] **Step 3: Add long-press-drag cursor movement over the terminal**

In `_SessionBody.build`, wrap the `TerminalView` `GestureDetector` to also handle a long-press drag. Add a `CursorDragMapper` owned by the state (`_MobileSessionsScreenState`), passed down. Use `onLongPressMoveUpdate` to feed deltas and `onLongPressEnd` to reset:

```dart
            child: GestureDetector(
              onScaleStart: onScaleStart,
              onScaleUpdate: onScaleUpdate,
              onLongPressMoveUpdate: (d) {
                for (final k in cursorMapper.addDelta(
                    d.offsetFromOrigin.dx - lastDrag.dx,
                    d.offsetFromOrigin.dy - lastDrag.dy)) {
                  session.terminal.keyInput(k);
                }
                lastDrag = d.offsetFromOrigin;
              },
              onLongPressEnd: (_) {
                cursorMapper.reset();
                lastDrag = Offset.zero;
              },
              child: TerminalView(...),
            ),
```

Implementation detail: `lastDrag` is `Offset` state held alongside `cursorMapper` in `_MobileSessionsScreenState` (reset to `Offset.zero` in `onLongPressEnd`). `onLongPressMoveUpdate.offsetFromOrigin` is cumulative from the press origin, so subtract the previous offset to get the per-event delta. Pass both `cursorMapper` and a `lastDrag` getter/setter (or wrap in a small holder) into `_SessionBody`.

> Add `final CursorDragMapper cursorMapper;` to `_SessionBody`; hold `final _cursor = CursorDragMapper();` and `Offset _lastDrag = Offset.zero;` in `_MobileSessionsScreenState`; thread a setter callback `onDragOffset` so `_SessionBody` can update `_lastDrag` (or make `_SessionBody` stateful and own `_lastDrag` itself — preferred, since `_lastDrag` is view-local). Simplest: make `_SessionBody` a `StatefulWidget` owning both `_cursor` and `_lastDrag`. Keep pinch (`onScaleStart/Update`) callbacks as-is.

Add import: `import '../terminal/terminal_cursor_gestures.dart';`

- [ ] **Step 4: Restyle the session strip as pill tabs with a close button**

Replace `_SessionStrip`'s `ChoiceChip` loop with pill tabs that show a host-color dot + label + a close ×, plus a trailing "+" affordance is out of scope here (Hosts FAB already adds). Each pill:

```dart
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
              child: _SessionPill(
                session: s,
                selected: s.id == activeId,
                onTap: () => context.read<SessionProvider>().setActive(s.id),
                onClose: () => context.read<SessionProvider>().closeSession(s.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionPill extends StatelessWidget {
  final SshSession session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;
  const _SessionPill({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.card : AppColors.bg,
          borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
          border: Border.all(
              color: selected ? AppColors.accent : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AppColors.hostColor(session.host.host),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(session.tabLabel,
                style: TextStyle(
                    color: selected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: 13)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close,
                  size: 14, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
```

Add import: `import '../theme/mobile_tokens.dart';`

- [ ] **Step 5: Analyze + run mobile suite + commit**

Run: `cd app && flutter analyze && flutter test test/mobile/`
Expected: clean + green.

```bash
git add app/lib/mobile/screens/mobile_sessions_screen.dart
git commit -m "feat(mobile): side panel, cursor-drag gestures, pill session tabs"
```

---

## Milestone 4 — SFTP screen

### Task 11: Reskin SFTP (breadcrumb + typed rows + transfer strip)

**Files:**
- Modify: `app/lib/mobile/screens/mobile_sftp_screen.dart` (reskin `_bar` → breadcrumb, `_row` → typed cards; keep all load/download/upload logic unchanged)

**Interfaces:**
- Consumes: existing `_load`, `_download`, `_upload`, `_path`, `_entries`; `MobileTokens`, `AppColors`, `SectionHeader` not needed here.

- [ ] **Step 1: Replace `_bar` with a breadcrumb path bar**

```dart
  Widget _bar(Host host) {
    final parts = _path == '.' ? <String>[] : _path.split('/').where((s) => s.isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MobileTokens.space2, vertical: MobileTokens.space2),
      color: AppColors.card,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, color: AppColors.textSecondary),
            onPressed: _path == '.' || _path == '/'
                ? null
                : () => _load(host, p.posix.dirname(_path)),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  _crumb(host, 'home', _path == '.' ? null : () => _load(host, '.')),
                  for (var i = 0; i < parts.length; i++) ...[
                    const Icon(Icons.chevron_right, size: 16, color: AppColors.textTertiary),
                    _crumb(
                      host,
                      parts[i],
                      i == parts.length - 1
                          ? null
                          : () => _load(host, '/${parts.sublist(0, i + 1).join('/')}'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: () => _load(host, _path),
          ),
        ],
      ),
    );
  }

  Widget _crumb(Host host, String label, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(label,
            style: TextStyle(
                color: onTap == null ? AppColors.textPrimary : AppColors.accent,
                fontSize: 13)),
      ),
    );
  }
```

- [ ] **Step 2: Replace `_row` with a typed row + human size**

```dart
  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }

  IconData _iconFor(SftpName e) {
    if (e.attr.isDirectory) return Icons.folder;
    final name = e.filename.toLowerCase();
    if (RegExp(r'\.(zip|tar|gz|tgz|bz2|xz|7z|rar)$').hasMatch(name)) return Icons.folder_zip;
    if (RegExp(r'\.(png|jpe?g|gif|webp|svg|bmp)$').hasMatch(name)) return Icons.image;
    if (RegExp(r'\.(sh|bash|zsh|py|js|ts|go|rs|c|cpp|dart|rb|json|ya?ml|toml|conf)$').hasMatch(name)) return Icons.description;
    return Icons.insert_drive_file;
  }

  Widget _row(Host host, SftpName e) {
    final isDir = e.attr.isDirectory;
    return ListTile(
      leading: Icon(_iconFor(e), color: isDir ? AppColors.accent : AppColors.textSecondary),
      title: Text(e.filename, style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: isDir
          ? null
          : Text(_fmtSize(e.attr.size ?? 0),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      trailing: isDir
          ? const Icon(Icons.chevron_right, color: AppColors.textTertiary)
          : IconButton(
              icon: const Icon(Icons.download, color: AppColors.textSecondary),
              onPressed: () => _download(host, e),
            ),
      onTap: isDir ? () => _load(host, _join(e.filename)) : null,
    );
  }
```

Add import: `import '../theme/mobile_tokens.dart';`

- [ ] **Step 3: Analyze + run + commit**

Run: `cd app && flutter analyze && flutter test test/mobile/`
Expected: clean + green.

```bash
git add app/lib/mobile/screens/mobile_sftp_screen.dart
git commit -m "feat(mobile): SFTP breadcrumb + typed file rows + human sizes"
```

---

## Milestone 5 — Settings + Add host

### Task 12: Sectioned Settings via SectionHeader + MobileCard

**Files:**
- Modify: `app/lib/mobile/screens/mobile_settings_screen.dart` (replace the inline bold `Text(...)` section titles with `SectionHeader`, wrap each group's controls in a `MobileCard`; keep all logic — `_save`, `_pull`, `_scan`, `_field`, app-lock switch — unchanged)

**Interfaces:**
- Consumes: `SectionHeader`, `MobileCard`, `MobileTokens`.

- [ ] **Step 1: Swap section titles + wrap groups**

Replace each `const Text('Cloud Sync', style: …16/w600)` (and 'P2P transfer', 'Security', 'Terminal appearance') with `const SectionHeader('Cloud sync')` etc., and wrap the controls under each header in a `MobileCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [...]))`. Example for the Security group:

```dart
            const SectionHeader('Security'),
            MobileCard(
              padding: const EdgeInsets.symmetric(horizontal: MobileTokens.space2),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _appLock,
                onChanged: (v) async {
                  setState(() => _appLock = v);
                  final p = await SharedPreferences.getInstance();
                  await p.setBool(kAppLockPrefKey, v);
                },
                title: const Text('Require biometrics to open',
                    style: TextStyle(color: AppColors.textPrimary)),
                subtitle: const Text('Applies on next app launch',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
            ),
            const SizedBox(height: MobileTokens.space4),
```

Apply the same pattern to Cloud sync (fields + Save/Pull buttons + error), P2P transfer (description + Scan button), and Terminal appearance (the `TerminalAppearanceControls`). Keep `_field`, `_save`, `_pull`, `_scan` verbatim.

Add imports: `import '../theme/mobile_tokens.dart';`, `import '../widgets/section_header.dart';`, `import '../widgets/mobile_card.dart';`

- [ ] **Step 2: Analyze + run + commit**

Run: `cd app && flutter analyze && flutter test test/mobile/`
Expected: clean + green.

```bash
git add app/lib/mobile/screens/mobile_settings_screen.dart
git commit -m "feat(mobile): sectioned settings with cards and headers"
```

### Task 13: Polish Add-host form

**Files:**
- Modify: `app/lib/mobile/screens/mobile_add_host_screen.dart` (group fields under `SectionHeader`s: "Connection" (label/host/port/username) and "Authentication" (key switch / key dropdown / password); keep `_save` and `_field` unchanged)

**Interfaces:**
- Consumes: `SectionHeader`, `MobileTokens`.

- [ ] **Step 1: Insert section headers**

In `build`'s `ListView`, prepend `const SectionHeader('Connection'),` before `_field(_label, …)` and `const SectionHeader('Authentication'),` before the `SwitchListTile`. Add imports `import '../theme/mobile_tokens.dart';`, `import '../widgets/section_header.dart';`.

- [ ] **Step 2: Analyze + run + commit**

Run: `cd app && flutter analyze && flutter test test/mobile/`
Expected: clean + green.

```bash
git add app/lib/mobile/screens/mobile_add_host_screen.dart
git commit -m "feat(mobile): grouped add-host form"
```

---

## Milestone 6 — Verification

### Task 14: Full analyze + test sweep

- [ ] **Step 1: Analyze the whole app**

Run: `cd app && flutter analyze`
Expected: "No issues found!"

- [ ] **Step 2: Run the full test suite**

Run: `cd app && flutter test`
Expected: all green (existing + new mobile tests).

- [ ] **Step 3: Manual smoke (device/emulator), if available**

Run: `cd app && flutter run -d <android-device>` and verify: hosts cards render with avatars + status dots; tag filter works; long-press deletes; session pill tabs switch/close; the keyboard-panel button opens the 4-tab sheet; long-press-drag moves the cursor; SFTP breadcrumb navigates; settings/add-host show grouped sections.

> If no device is available, state that the manual smoke was skipped and rely on analyze + widget tests.

---

## Self-Review

**Spec coverage:**
- Design tokens → Task 1. Shared widgets (HostAvatar/StatusDot/TagChip/SectionHeader/MobileCard) → Tasks 2–4. ✓
- Hosts cards + search/filter + swipe/long-press + empty state → Tasks 5–6 (delete via long-press confirm; trailing-swipe-to-edit dropped — see note below). ✓
- Terminal: accessory regroup → Task 8; side panel (Keys/Snippets/History/Themes) → Task 9; pill tabs + gestures → Task 10. ✓
- SFTP breadcrumb + typed rows → Task 11. (Transfer-progress strip: the mobile screen uses `SftpTransferService.uploadFile`/direct download without a progress stream wired into this screen; a progress strip is deferred and called out here rather than faked. ✓ documented, not silently dropped.)
- Settings sectioned → Task 12. Add-host polish → Task 13. ✓
- Tests for avatar/status/gestures/accessory/host-card/hosts-screen/side-panel → Tasks 2,3,4,5,6,7,8,9. ✓

**Scope deltas from the spec (intentional, documented):**
- "Swipe to Edit/Delete": mobile has no host *editor* screen today (Add-only). Implemented **delete** via long-press + confirm dialog; Edit is out of scope (no editor exists — adding one is separate work). Tap-to-connect preserved.
- "Transfer progress strip" in SFTP: deferred — the current screen has no progress stream; noted in Task 11 self-review rather than stubbed.

**Placeholder scan:** No TBD/TODO; every code step shows full code. The NOTE blocks (test-fake constructors, `TerminalKey` member existence) are verification reminders, not placeholders — they instruct the implementer to check real signatures before running, which is correct given providers/enums weren't all read line-by-line.

**Type consistency:** `HostConnState` (status_dot.dart) used identically in host_card.dart + mobile_hosts_screen.dart. `hostInitials`/`HostAvatar` signatures match their test. `CursorDragMapper.addDelta/reset` match Task 10 usage. `AccessoryKeyBar.onOpenPanel` added in Task 8 and consumed in Task 10. `showTerminalSidePanel` signature in Task 9 matches the call in Task 10. `MobileCard(onTap/onLongPress/padding/child)` matches all callers.
