import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

Widget _wrap(Widget child, {double w = 400}) => MaterialApp(
  theme: ysMaterialTheme(),
  builder: (context, child) => FTheme(data: ysThemeData(), child: child!),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: w, child: child),
    ),
  ),
);

BoxDecoration _cardDeco(WidgetTester tester) =>
    tester
            .widget<Container>(find.byKey(const Key('ys-host-card-box')))
            .decoration!
        as BoxDecoration;

void main() {
  testWidgets('host card shows title, subtitle, badges, tags, meta', (t) async {
    await t.pumpWidget(
      _wrap(
        YsHostCard(
          leading: const YsOsTile(glyph: Icon(Icons.dns), color: Colors.orange),
          title: 'prod-web-01',
          subtitle: 'deploy@10.0.1.11:22',
          badges: const [YsStatusBadge('RDP')],
          tags: const [YsTag('prod')],
          meta: '2 sessions',
        ),
      ),
    );
    expect(find.text('prod-web-01'), findsOneWidget);
    expect(find.text('deploy@10.0.1.11:22'), findsOneWidget);
    expect(find.text('RDP'), findsOneWidget);
    expect(find.text('prod'), findsOneWidget);
    expect(find.text('2 sessions'), findsOneWidget);
  });

  testWidgets('selected card has primary 1px border; default uses border', (
    t,
  ) async {
    Widget card(bool sel) => _wrap(
      YsHostCard(
        leading: const SizedBox(),
        title: 'a',
        subtitle: 'b',
        selected: sel,
      ),
    );
    await t.pumpWidget(card(true));
    var deco = _cardDeco(t);
    expect((deco.border! as Border).top.color, YsColors.primary);
    expect((deco.border! as Border).top.width, 1);
    expect(deco.borderRadius, BorderRadius.circular(YsRadius.card));
    expect(deco.color, YsColors.card);
    await t.pumpWidget(card(false));
    deco = _cardDeco(t);
    expect((deco.border! as Border).top.color, YsColors.border);
  });

  testWidgets('hover switches background to secondary', (t) async {
    await t.pumpWidget(
      _wrap(YsHostCard(leading: const SizedBox(), title: 'a', subtitle: 'b')),
    );
    final g = await t.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: Offset.zero);
    await g.moveTo(t.getCenter(find.byKey(const Key('ys-host-card-box'))));
    await t.pump();
    expect(_cardDeco(t).color, YsColors.secondary);
  });

  testWidgets('tap, double tap, secondary tap, long press fire', (t) async {
    var tap = 0, dbl = 0, sec = 0, lp = 0;
    Offset? pos;
    await t.pumpWidget(
      _wrap(
        YsHostCard(
          leading: const SizedBox(),
          title: 'a',
          subtitle: 'b',
          onTap: () => tap++,
          onDoubleTap: () => dbl++,
          onSecondaryTap: (p) {
            sec++;
            pos = p;
          },
          onLongPress: () => lp++,
        ),
      ),
    );
    final c = t.getCenter(find.byKey(const Key('ys-host-card-box')));
    await t.tapAt(c);
    await t.pump(const Duration(milliseconds: 400));
    expect(tap, 1);
    await t.tapAt(c);
    await t.pump(const Duration(milliseconds: 50));
    await t.tapAt(c);
    await t.pump(const Duration(milliseconds: 400));
    expect(dbl, 1);
    await t.tapAt(c, buttons: kSecondaryButton);
    await t.pump();
    expect(sec, 1);
    expect(pos, isNotNull);
    await t.longPressAt(c);
    await t.pump();
    expect(lp, 1);
  });

  testWidgets('trailing action and status dot render', (t) async {
    await t.pumpWidget(
      _wrap(
        YsHostCard(
          leading: const SizedBox(),
          title: 'a',
          subtitle: 'b',
          statusDot: const SizedBox(key: Key('dot'), width: 6, height: 6),
          trailingAction: const Text('Connect'),
        ),
      ),
    );
    expect(find.byKey(const Key('dot')), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('60-char title does not overflow at 900x600', (t) async {
    t.view.physicalSize = const Size(900, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final long = 'x' * 60;
    await t.pumpWidget(
      _wrap(
        w: 420,
        YsHostCard(
          leading: const YsOsTile(glyph: Icon(Icons.dns), color: Colors.red),
          title: long,
          subtitle: 'u@${'h' * 60}:22',
          tags: List.generate(5, (i) => YsTag('tag-number-$i')),
          badges: const [YsStatusBadge('RDP')],
          meta: 'meta ' * 10,
          trailingAction: const Text('Connect'),
        ),
      ),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('os tile renders glyph with size', (t) async {
    await t.pumpWidget(
      _wrap(
        const Align(
          alignment: Alignment.topLeft,
          child: YsOsTile(glyph: Text('G'), color: Colors.blue, size: 40),
        ),
      ),
    );
    expect(find.text('G'), findsOneWidget);
    expect(t.getSize(find.byKey(const Key('ys-os-tile'))), const Size(40, 40));
  });

  testWidgets('section header shows title and trailing', (t) async {
    await t.pumpWidget(
      _wrap(const YsSectionHeader(title: 'Hosts', trailing: '6 online')),
    );
    expect(find.text('Hosts'), findsOneWidget);
    expect(find.text('6 online'), findsOneWidget);
  });

  testWidgets('empty state shows icon, texts and action', (t) async {
    await t.pumpWidget(
      _wrap(
        const YsEmptyState(
          icon: FLucideIcons.server,
          title: 'No hosts',
          message: 'Add one',
          action: Text('New host'),
        ),
      ),
    );
    expect(find.byIcon(FLucideIcons.server), findsOneWidget);
    expect(find.text('No hosts'), findsOneWidget);
    expect(find.text('Add one'), findsOneWidget);
    expect(find.text('New host'), findsOneWidget);
  });

  testWidgets('badges render labels over FBadge', (t) async {
    await t.pumpWidget(
      _wrap(
        const Column(
          children: [
            YsTag('prod'),
            YsStatusBadge('lag 4.2 s', status: YsStatus.warn),
          ],
        ),
      ),
    );
    expect(find.byType(FBadge), findsNWidgets(2));
    expect(find.text('prod'), findsOneWidget);
    expect(find.text('lag 4.2 s'), findsOneWidget);
  });

  testWidgets('subtitle uses mono font family and fallback', (t) async {
    await t.pumpWidget(
      _wrap(YsHostCard(leading: const SizedBox(), title: 'a', subtitle: 'sub')),
    );
    final style = t.widget<Text>(find.text('sub')).style!;
    expect(style.fontFamily, kYsMonoFontFamily);
    expect(style.fontFamilyFallback, kYsMonoFontFallback);
  });

  testWidgets('card is focusable, Enter and Space fire onTap', (t) async {
    var tap = 0;
    await t.pumpWidget(
      _wrap(
        YsHostCard(
          leading: const SizedBox(),
          title: 'a',
          subtitle: 'b',
          onTap: () => tap++,
        ),
      ),
    );
    final node = Focus.of(t.element(find.byKey(const Key('ys-host-card-box'))));
    node.requestFocus();
    await t.pump();
    expect(node.hasFocus, isTrue);
    expect((_cardDeco(t).border! as Border).top.width, 2, reason: 'focus ring');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    expect(tap, 2);
  });

  testWidgets('onActivate: focusable without onTap; Enter fires onActivate', (
    t,
  ) async {
    var activate = 0;
    var doubleTap = 0;
    await t.pumpWidget(
      _wrap(
        YsHostCard(
          leading: const SizedBox(),
          title: 'a',
          subtitle: 'b',
          onDoubleTap: () => doubleTap++,
          onActivate: () => activate++,
        ),
      ),
    );
    // A single click does nothing when only onActivate is set.
    await t.tap(find.text('a'));
    await t.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    expect(activate, 0);
    expect(doubleTap, 0);

    final node = Focus.of(t.element(find.byKey(const Key('ys-host-card-box'))));
    node.requestFocus();
    await t.pump();
    expect(node.hasFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    expect(activate, 2);
  });

  testWidgets('focusNode: the caller can focus the card', (t) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    var activate = 0;
    await t.pumpWidget(
      _wrap(
        YsHostCard(
          leading: const SizedBox(),
          title: 'a',
          subtitle: 'b',
          focusNode: node,
          onActivate: () => activate++,
        ),
      ),
    );
    node.requestFocus();
    await t.pump();
    expect(
      Focus.of(t.element(find.byKey(const Key('ys-host-card-box')))),
      same(node),
    );
    expect((_cardDeco(t).border! as Border).top.width, 2, reason: 'focus ring');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activate, 1);
  });

  testWidgets('onActivate overrides onTap for the keyboard only', (t) async {
    var tap = 0;
    var activate = 0;
    await t.pumpWidget(
      _wrap(
        YsHostCard(
          leading: const SizedBox(),
          title: 'a',
          subtitle: 'b',
          onTap: () => tap++,
          onActivate: () => activate++,
        ),
      ),
    );
    await t.tap(find.text('a'));
    expect(tap, 1);
    final node = Focus.of(t.element(find.byKey(const Key('ys-host-card-box'))));
    node.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activate, 1);
    expect(tap, 1);
  });

  testWidgets('semantics label contains title', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(
      _wrap(
        YsHostCard(
          leading: const SizedBox(),
          title: 'prod-web-01',
          subtitle: 'sub',
          selected: true,
          onTap: () {},
        ),
      ),
    );
    final d = t.getSemantics(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.button == true,
      ),
    );
    expect(d.label, contains('prod-web-01'));
    expect(d.flagsCollection.isSelected, Tristate.isTrue);
    h.dispose();
  });

  testWidgets('240px card with 3 badges and 60-char title: no overflow', (
    t,
  ) async {
    await t.pumpWidget(
      _wrap(
        w: 240,
        YsHostCard(
          leading: const YsOsTile(glyph: Icon(Icons.dns), color: Colors.red),
          title: 'x' * 60,
          subtitle: 'b',
          statusDot: const SizedBox(width: 6, height: 6),
          badges: const [
            YsStatusBadge('RDP'),
            YsStatusBadge('lag 4.2 s'),
            YsStatusBadge('degraded'),
          ],
        ),
      ),
    );
    expect(t.takeException(), isNull);
  });
}
