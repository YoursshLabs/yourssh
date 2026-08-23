import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/mobile/widgets/latency_badge.dart';
import 'package:yourssh/mobile/widgets/tag_chip.dart';
import 'package:yourssh/mobile/widgets/list_group.dart';
import 'package:yourssh/mobile/widgets/settings_row.dart';
import 'package:yourssh/mobile/widgets/mobile_card.dart';
import 'package:yourssh/mobile/widgets/section_header.dart';
import 'package:yourssh/mobile/widgets/status_dot.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildMobileTheme(), home: Scaffold(body: child));

void main() {
  // ── LatencyBadge ──────────────────────────────────────────────────────────
  group('LatencyBadge', () {
    testWidgets('renders "24ms" for ms:24', (tester) async {
      await tester.pumpWidget(_wrap(const LatencyBadge(ms: 24)));
      expect(find.text('24ms'), findsOneWidget);
    });

    testWidgets('renders "offline" when offline:true', (tester) async {
      await tester.pumpWidget(_wrap(const LatencyBadge(offline: true)));
      expect(find.text('offline'), findsOneWidget);
    });

    testWidgets('ms<100 uses green pill', (tester) async {
      await tester.pumpWidget(_wrap(const LatencyBadge(ms: 50)));
      final container = tester.widget<Container>(find.byType(Container).first);
      final deco = container.decoration as BoxDecoration;
      expect(deco.color, MobileColors.green);
    });

    testWidgets('offline pill uses grey (textFaint) color', (tester) async {
      await tester.pumpWidget(_wrap(const LatencyBadge(offline: true)));
      final container = tester.widget<Container>(find.byType(Container).first);
      final deco = container.decoration as BoxDecoration;
      expect(deco.color, MobileColors.textFaint);
    });

    testWidgets('no ms and not offline renders "—" not "nullms"', (tester) async {
      await tester.pumpWidget(_wrap(const LatencyBadge()));
      expect(find.text('—'), findsOneWidget);
      expect(find.text('nullms'), findsNothing);
    });
  });

  // ── TagChip ───────────────────────────────────────────────────────────────
  group('TagChip', () {
    testWidgets('selected chip decoration color is accent', (tester) async {
      await tester.pumpWidget(
          _wrap(const TagChip(label: 'prod', selected: true)));
      final container = tester.widget<Container>(find.byType(Container).first);
      final deco = container.decoration as BoxDecoration;
      expect(deco.color, MobileColors.accent);
    });

    testWidgets('unselected chip decoration color is surface', (tester) async {
      await tester.pumpWidget(
          _wrap(const TagChip(label: 'dev', selected: false)));
      final container = tester.widget<Container>(find.byType(Container).first);
      final deco = container.decoration as BoxDecoration;
      expect(deco.color, MobileColors.surface);
    });

    testWidgets('large filter chip uses 13px text, no border, fieldFill bg',
        (tester) async {
      await tester.pumpWidget(
          _wrap(const TagChip(label: 'All', large: true, selected: false)));
      final container = tester.widget<Container>(find.byType(Container).first);
      final deco = container.decoration as BoxDecoration;
      expect(deco.border, isNull); // folder chips have no border
      expect(deco.color, MobileColors.fieldFill);
      final text = tester.widget<Text>(find.text('All'));
      expect(text.style?.fontSize, 13);
      expect(text.textAlign, TextAlign.center);
      // padding + min width so a short label stays a balanced pill, not a circle
      expect(container.padding,
          const EdgeInsets.symmetric(horizontal: 14, vertical: 8));
      expect(container.constraints, const BoxConstraints(minWidth: 64));
    });
  });

  // ── SectionHeader ─────────────────────────────────────────────────────────
  group('SectionHeader', () {
    testWidgets('renders uppercase text', (tester) async {
      await tester.pumpWidget(_wrap(const SectionHeader('hosts')));
      expect(find.text('HOSTS'), findsOneWidget);
    });

    testWidgets('uses sectionLabel style color', (tester) async {
      await tester.pumpWidget(_wrap(const SectionHeader('general')));
      final text = tester.widget<Text>(find.byType(Text).first);
      expect(text.style?.color, MobileColors.textFaint);
    });
  });

  // ── MobileCard ────────────────────────────────────────────────────────────
  group('MobileCard', () {
    testWidgets('renders child', (tester) async {
      await tester.pumpWidget(
          _wrap(const MobileCard(child: Text('card content'))));
      expect(find.text('card content'), findsOneWidget);
    });

    testWidgets('card background is surface (#161618)', (tester) async {
      await tester.pumpWidget(
          _wrap(const MobileCard(child: Text('x'))));
      final container = tester.widget<Container>(find.byType(Container).first);
      final deco = container.decoration as BoxDecoration;
      expect(deco.color, MobileColors.surface);
    });

    testWidgets('card border color is border (#232325)', (tester) async {
      await tester.pumpWidget(
          _wrap(const MobileCard(child: Text('x'))));
      final container = tester.widget<Container>(find.byType(Container).first);
      final deco = container.decoration as BoxDecoration;
      final borderSide = (deco.border as Border).top;
      expect(borderSide.color, MobileColors.border);
    });

    testWidgets('card radius is 15', (tester) async {
      await tester.pumpWidget(
          _wrap(const MobileCard(child: Text('x'))));
      final container = tester.widget<Container>(find.byType(Container).first);
      final deco = container.decoration as BoxDecoration;
      expect((deco.borderRadius as BorderRadius).topLeft.x, 15.0);
    });
  });

  // ── StatusDot ─────────────────────────────────────────────────────────────
  group('StatusDot', () {
    testWidgets('online state uses green color', (tester) async {
      await tester.pumpWidget(
          _wrap(const StatusDot(state: HostConnState.connected)));
      final container = tester.widget<Container>(find.byType(Container).first);
      final deco = container.decoration as BoxDecoration;
      expect(deco.color, MobileColors.green);
    });

    testWidgets('offline state uses grey color', (tester) async {
      await tester.pumpWidget(
          _wrap(const StatusDot(state: HostConnState.offline)));
      final container = tester.widget<Container>(find.byType(Container).first);
      final deco = container.decoration as BoxDecoration;
      expect(deco.color, MobileColors.textFaint);
    });
  });

  // ── ListGroup ─────────────────────────────────────────────────────────────
  group('ListGroup', () {
    testWidgets('2 rows renders exactly 1 divider', (tester) async {
      await tester.pumpWidget(_wrap(
        ListGroup(children: [
          const Text('row1'),
          const Text('row2'),
        ]),
      ));
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('3 rows renders exactly 2 dividers', (tester) async {
      await tester.pumpWidget(_wrap(
        ListGroup(children: [
          const Text('row1'),
          const Text('row2'),
          const Text('row3'),
        ]),
      ));
      expect(find.byType(Divider), findsNWidgets(2));
    });

    testWidgets('renders optional label', (tester) async {
      await tester.pumpWidget(_wrap(
        ListGroup(label: 'Security', children: [const Text('row1')]),
      ));
      expect(find.text('SECURITY'), findsOneWidget);
    });

    testWidgets('renders all children', (tester) async {
      await tester.pumpWidget(_wrap(
        ListGroup(children: [const Text('A'), const Text('B')]),
      ));
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });
  });

  // ── SettingsRow ───────────────────────────────────────────────────────────
  group('SettingsRow', () {
    testWidgets('toggle:true shows a Switch', (tester) async {
      await tester.pumpWidget(_wrap(
        SettingsRow(title: 'Option', toggle: true, onToggle: (_) {}),
      ));
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('toggle:false shows no Switch', (tester) async {
      await tester.pumpWidget(_wrap(
        const SettingsRow(title: 'Option'),
      ));
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(_wrap(
        const SettingsRow(title: 'Privacy'),
      ));
      expect(find.text('Privacy'), findsOneWidget);
    });

    testWidgets('renders value text in mono/grey', (tester) async {
      await tester.pumpWidget(_wrap(
        const SettingsRow(title: 'Host', value: 'localhost'),
      ));
      expect(find.text('localhost'), findsOneWidget);
    });

    testWidgets('shows chevron when onTap is set', (tester) async {
      await tester.pumpWidget(_wrap(
        SettingsRow(title: 'Host', onTap: () {}),
      ));
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('no chevron when onTap is null and no toggle', (tester) async {
      await tester.pumpWidget(_wrap(
        const SettingsRow(title: 'Version', value: '1.0'),
      ));
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });
  });
}
