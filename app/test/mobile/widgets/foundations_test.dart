import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/theme/mobile_tokens.dart';
import 'package:yourssh/mobile/theme/toast_inset.dart';
import 'package:yourssh/mobile/widgets/mobile_card.dart';
import 'package:yourssh/mobile/widgets/tag_chip.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh/mobile/widgets/forward_rule_row.dart';
import 'package:yourssh/mobile/widgets/host_card.dart';
import 'package:yourssh/mobile/widgets/key_card.dart';
import 'package:yourssh/mobile/widgets/mobile_fab.dart';
import 'package:yourssh/mobile/widgets/mobile_tab_bar.dart';
import 'package:yourssh/mobile/widgets/settings_row.dart';
import 'package:yourssh/mobile/widgets/snippet_card.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/port_forward.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../helpers/ys_test_app.dart';

final _long = 'x' * 60;

Future<void> _smallPhone(WidgetTester t) async {
  t.view.physicalSize = const Size(360, 640);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  setUp(() => mobileToastInset.value = 0);
  tearDown(() => mobileToastInset.value = 0);

  group('MobileTokens aliases', () {
    test('spacing/radius alias the Ys tokens', () {
      expect(MobileTokens.space1, YsSpace.s1);
      expect(MobileTokens.space3, YsSpace.s3);
      expect(MobileTokens.space5, YsSpace.s5);
      expect(MobileTokens.radiusCard, YsRadius.mobileCard);
      expect(MobileTokens.touchTarget, 44);
    });
  });

  group('MobileTabBar', () {
    testWidgets('built on FBottomNavigationBar, 4 tabs in order, taps select', (
      t,
    ) async {
      final picked = <MobileTab>[];
      await t.pumpWidget(
        ysTestApp(
          Align(
            alignment: Alignment.bottomCenter,
            child: MobileTabBar(current: MobileTab.hosts, onSelect: picked.add),
          ),
          touch: true,
        ),
      );
      expect(find.byType(FBottomNavigationBar), findsOneWidget);
      expect(find.byType(FBottomNavigationBarItem), findsNWidgets(4));
      final labels = ['Hosts', 'Snippets', 'Keys', 'Settings'];
      for (final l in labels) {
        expect(find.text(l), findsOneWidget);
      }
      final xs = [for (final l in labels) t.getCenter(find.text(l)).dx];
      expect([...xs]..sort(), xs, reason: 'tab order');
      await t.tap(find.text('Keys'));
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      expect(picked, [MobileTab.keys, MobileTab.settings]);
    });

    testWidgets('each tab item has a >=44 px hit area', (t) async {
      await _smallPhone(t);
      await t.pumpWidget(
        ysTestApp(
          Align(
            alignment: Alignment.bottomCenter,
            child: MobileTabBar(current: MobileTab.hosts, onSelect: (_) {}),
          ),
          touch: true,
        ),
      );
      expect(
        t.getSize(find.byType(FBottomNavigationBar)).height,
        MobileTokens.tabBarHeight,
      );
      final items = find.bySubtype<FTappable>();
      expect(items, findsNWidgets(4));
      for (var i = 0; i < 4; i++) {
        final s = t.getSize(items.at(i));
        expect(s.height, greaterThanOrEqualTo(44), reason: 'tab $i height');
        expect(s.width, greaterThanOrEqualTo(44), reason: 'tab $i width');
        // Real hit area: the centre and the +-22 px edges all hit the tappable.
        final c = t.getCenter(items.at(i));
        for (final d in [
          Offset.zero,
          const Offset(0, 22),
          const Offset(0, -22),
          const Offset(22, 0),
          const Offset(-22, 0),
        ]) {
          expect(
            _hits(t, c + d, items.at(i)),
            isTrue,
            reason: 'tab $i hit at $d',
          );
        }
      }
    });

    group('toast inset', () {
      final nav = GlobalKey<NavigatorState>();

      Future<void> pumpShell(WidgetTester t) async {
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            navigatorObservers: [mobileRouteObserver],
            builder: ysRootBuilderTouch,
            home: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: MobileTabBar(
                current: MobileTab.hosts,
                onSelect: (_) {},
              ),
            ),
          ),
        );
        await t.pump();
        expect(mobileToastInset.value, MobileTokens.tabBarHeight);
      }

      testWidgets('kept while a dialog is open', (t) async {
        await pumpShell(t);
        showDialog<void>(
          context: nav.currentContext!,
          builder: (_) => const AlertDialog(),
        );
        await t.pumpAndSettle();
        expect(mobileToastInset.value, MobileTokens.tabBarHeight);
        nav.currentState!.pop();
        await t.pumpAndSettle();
        expect(mobileToastInset.value, MobileTokens.tabBarHeight);
      });

      testWidgets('kept while a modal bottom sheet is open', (t) async {
        await pumpShell(t);
        showModalBottomSheet<void>(
          context: nav.currentContext!,
          builder: (_) => const SizedBox(height: 100),
        );
        await t.pumpAndSettle();
        expect(mobileToastInset.value, MobileTokens.tabBarHeight);
        nav.currentState!.pop();
        await t.pumpAndSettle();
        expect(mobileToastInset.value, MobileTokens.tabBarHeight);
      });

      testWidgets('dropped under a full-screen page, back on pop', (t) async {
        await pumpShell(t);
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('pushed')),
          ),
        );
        await t.pumpAndSettle();
        expect(mobileToastInset.value, 0);
        // A dialog over the full-screen page does not bring it back.
        showDialog<void>(
          context: nav.currentContext!,
          builder: (_) => const AlertDialog(),
        );
        await t.pumpAndSettle();
        expect(mobileToastInset.value, 0);
        nav.currentState!.pop();
        await t.pumpAndSettle();
        expect(mobileToastInset.value, 0);
        nav.currentState!.pop();
        await t.pumpAndSettle();
        expect(mobileToastInset.value, MobileTokens.tabBarHeight);
      });

      testWidgets('zero once the tab bar is unmounted', (t) async {
        await pumpShell(t);
        await t.pumpWidget(
          MaterialApp(
            builder: ysRootBuilderTouch,
            home: const Scaffold(body: Text('no tab bar')),
          ),
        );
        await t.pump();
        expect(mobileToastInset.value, 0);
      });
    });
  });

  group('MobileFab', () {
    testWidgets('>=44 px hit size and fires onTap', (t) async {
      var taps = 0;
      await t.pumpWidget(
        ysTestApp(Center(child: MobileFab(onTap: () => taps++)), touch: true),
      );
      final s = t.getSize(find.byType(FButton));
      expect(s.width, greaterThanOrEqualTo(44));
      expect(s.height, greaterThanOrEqualTo(44));
      await t.tap(find.byType(MobileFab));
      await t.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('HostCard on YsHostCard', () {
    testWidgets('composes YsHostCard, keeps tap + long-press', (t) async {
      var tap = 0, lp = 0;
      await t.pumpWidget(
        ysTestApp(
          HostCard(
            host: Host(label: 'web-01', host: '10.0.0.1', username: 'root'),
            onTap: () => tap++,
            onLongPress: () => lp++,
          ),
          touch: true,
        ),
      );
      expect(find.byType(YsHostCard), findsOneWidget);
      await t.tap(find.text('web-01'));
      expect(tap, 1);
      await t.longPress(find.text('web-01'));
      expect(lp, 1);
    });
  });

  group('KeyCard', () {
    SshKeyEntry key(String label) => SshKeyEntry(
      label: label,
      algorithm: KeyAlgorithm.ed25519,
      publicKey: '',
      privateKeyPath: 'embedded',
    );

    testWidgets('smoke: label, subtitle, tap, long-press', (t) async {
      var tap = 0, lp = 0;
      await t.pumpWidget(
        ysTestApp(
          KeyCard(
            entry: key('deploy-key'),
            hostCount: 2,
            onTap: () => tap++,
            onLongPress: () => lp++,
          ),
          touch: true,
        ),
      );
      expect(find.text('deploy-key'), findsOneWidget);
      expect(find.text('Ed25519 · 2 hosts'), findsOneWidget);
      await t.tap(find.text('deploy-key'));
      await t.pumpAndSettle();
      await t.longPress(find.text('deploy-key'));
      await t.pumpAndSettle();
      expect([tap, lp], [1, 1]);
    });

    testWidgets('unused key subtitle', (t) async {
      await t.pumpWidget(
        ysTestApp(KeyCard(entry: key('k'), hostCount: 0), touch: true),
      );
      expect(find.text('Ed25519 · unused'), findsOneWidget);
    });

    testWidgets('360x640, 60-char label: no overflow', (t) async {
      await _smallPhone(t);
      await t.pumpWidget(
        ysTestApp(
          KeyCard(entry: key(_long), hostCount: 1, onTap: () {}),
          touch: true,
        ),
      );
      expect(t.takeException(), isNull);
    });
  });

  group('SnippetCard', () {
    testWidgets('smoke: label, tag, command, tap', (t) async {
      var tap = 0;
      await t.pumpWidget(
        ysTestApp(
          SnippetCard(
            snippet: Snippet(label: 'Disk', command: 'df -h', tag: 'ops'),
            onTap: () => tap++,
          ),
          touch: true,
        ),
      );
      expect(find.text('Disk'), findsOneWidget);
      expect(find.text('ops'), findsOneWidget);
      expect(find.text('df -h'), findsOneWidget);
      await t.tap(find.text('Disk'));
      await t.pumpAndSettle();
      expect(tap, 1);
    });

    testWidgets('360x640, 60-char label: no overflow', (t) async {
      await _smallPhone(t);
      await t.pumpWidget(
        ysTestApp(
          SnippetCard(
            snippet: Snippet(label: _long, command: _long * 3, tag: 'ops'),
            onTap: () {},
          ),
          touch: true,
        ),
      );
      expect(t.takeException(), isNull);
    });
  });

  group('ForwardRuleRow', () {
    PortForward rule(ForwardType type) => PortForward(
      label: 'r',
      type: type,
      localPort: 8080,
      remoteHost: 'db.internal',
      remotePort: 5432,
    );

    testWidgets('smoke: type chip, summary, Start tooltip toggles', (t) async {
      var toggles = 0;
      await t.pumpWidget(
        ysTestApp(
          ForwardRuleRow(
            rule: rule(ForwardType.local),
            isRunning: false,
            onToggle: () => toggles++,
          ),
          touch: true,
        ),
      );
      expect(find.text('LOCAL'), findsOneWidget);
      expect(find.text(':8080 → db.internal:5432'), findsOneWidget);
      expect(find.byTooltip('Start'), findsOneWidget);
      await t.tap(find.byTooltip('Start'));
      await t.pumpAndSettle();
      expect(toggles, 1);
    });

    testWidgets('running shows Stop tooltip; toggle >=44 px', (t) async {
      await t.pumpWidget(
        ysTestApp(
          ForwardRuleRow(
            rule: rule(ForwardType.dynamic),
            isRunning: true,
            onToggle: () {},
          ),
          touch: true,
        ),
      );
      expect(find.text('DYNAMIC'), findsOneWidget);
      expect(find.text('SOCKS5 :8080'), findsOneWidget);
      final s = t.getSize(find.byTooltip('Stop'));
      expect(s.width, greaterThanOrEqualTo(44));
      expect(s.height, greaterThanOrEqualTo(44));
    });

    testWidgets('360x640, 60-char host: no overflow', (t) async {
      await _smallPhone(t);
      await t.pumpWidget(
        ysTestApp(
          ForwardRuleRow(
            rule: PortForward(
              label: 'r',
              type: ForwardType.local,
              localPort: 1,
              remoteHost: _long,
              remotePort: 2,
            ),
            isRunning: true,
            onToggle: () {},
          ),
          touch: true,
        ),
      );
      expect(t.takeException(), isNull);
    });
  });

  group('SettingsRow', () {
    testWidgets('toggle uses FSwitch and reports changes', (t) async {
      bool? got;
      await t.pumpWidget(
        ysTestApp(
          SettingsRow(title: 'Opt', toggle: false, onToggle: (v) => got = v),
          touch: true,
        ),
      );
      expect(find.byType(FSwitch), findsOneWidget);
      await t.tap(find.byType(FSwitch));
      await t.pumpAndSettle();
      expect(got, true);
    });

    testWidgets('360x640, 60-char title and value: no overflow', (t) async {
      await _smallPhone(t);
      await t.pumpWidget(
        ysTestApp(
          SettingsRow(
            title: _long,
            value: _long,
            onTap: () {},
            leading: const Icon(FLucideIcons.plus),
          ),
          touch: true,
        ),
      );
      expect(t.takeException(), isNull);
    });
  });

  group('HostCard overflow', () {
    testWidgets('360x640, 60-char label', (t) async {
      await _smallPhone(t);
      await t.pumpWidget(
        ysTestApp(
          HostCard(
            host: Host(
              label: _long,
              host: _long,
              username: 'root',
              tags: ['a', 'b'],
            ),
            online: true,
            latencyMs: 12,
            onTap: () {},
          ),
          touch: true,
        ),
      );
      expect(t.takeException(), isNull);
    });
  });

  group('Migrated primitives', () {
    testWidgets('SettingsRow row is >=44 px tall and tappable', (t) async {
      var taps = 0;
      await t.pumpWidget(
        ysTestApp(SettingsRow(title: 'A', onTap: () => taps++), touch: true),
      );
      expect(
        t.getSize(find.byType(SettingsRow)).height,
        greaterThanOrEqualTo(44),
      );
      await t.tap(find.byType(SettingsRow));
      await t.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('KeyCard main tap area is >=44 px', (t) async {
      await t.pumpWidget(
        ysTestApp(
          KeyCard(
            entry: SshKeyEntry(
              label: 'k',
              algorithm: KeyAlgorithm.ed25519,
              publicKey: '',
              privateKeyPath: 'embedded',
            ),
            hostCount: 1,
            onTap: () {},
          ),
          touch: true,
        ),
      );
      final area = find.descendant(
        of: find.byType(MobileCard),
        matching: find.bySubtype<FTappable>(),
      );
      expect(t.getSize(area).height, greaterThanOrEqualTo(44));
      expect(t.getSize(area).width, greaterThanOrEqualTo(44));
    });

    testWidgets('MobileCard fires tap and long-press', (t) async {
      var tap = 0, lp = 0;
      await t.pumpWidget(
        ysTestApp(
          MobileCard(
            onTap: () => tap++,
            onLongPress: () => lp++,
            child: const Text('c'),
          ),
          touch: true,
        ),
      );
      await t.tap(find.text('c'));
      await t.pumpAndSettle();
      await t.longPress(find.text('c'));
      await t.pumpAndSettle();
      expect([tap, lp], [1, 1]);
    });

    testWidgets('tappable TagChip taps and exposes selected semantics', (
      t,
    ) async {
      var taps = 0;
      final h = t.ensureSemantics();
      await t.pumpWidget(
        ysTestApp(
          TagChip(label: 'prod', selected: true, onTap: () => taps++),
          touch: true,
        ),
      );
      await t.tap(find.text('prod'));
      await t.pumpAndSettle();
      expect(taps, 1);
      expect(
        t.getSemantics(find.bySubtype<FTappable>()),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          label: 'prod',
        ),
      );
      h.dispose();
    });
  });
}

bool _hits(WidgetTester t, Offset p, Finder target) {
  final result = t.hitTestOnBinding(p);
  final ro = t.renderObject(target);
  return result.path.any((e) => e.target == ro) ||
      result.path.any((e) {
        final tg = e.target;
        return tg is RenderObject && _isDescendant(tg, ro);
      });
}

bool _isDescendant(RenderObject node, RenderObject ancestor) {
  RenderObject? n = node;
  while (n != null) {
    if (n == ancestor) return true;
    n = n.parent;
  }
  return false;
}
