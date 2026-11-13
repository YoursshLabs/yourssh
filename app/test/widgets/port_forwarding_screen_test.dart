import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/port_forward.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/port_forward_provider.dart';
import 'package:yourssh/services/port_forward_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/port_forwarding_screen.dart';
import 'package:flutter/services.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

/// Records start/stop instead of dialling.
class _SpyService extends PortForwardService {
  _SpyService(PortForwardProvider p)
      : super(
          acquireTransport: (_) async => throw UnimplementedError(),
          resolveHost: (_) => null,
          onStatus: p.setStatus,
          onConnections: p.setConnections,
        );
  final started = <String>[];
  final stopped = <String>[];

  @override
  Future<void> start(PortForward fwd) async => started.add(fwd.id);

  @override
  Future<void> stop(String forwardId) async => stopped.add(forwardId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _SpyService lastService;

  Future<(PortForwardProvider, Widget)> build({List<Host> seedHosts = const []}) async {
    final provider = PortForwardProvider();
    await provider.ready;
    final hosts = HostProvider(StorageService());
    await hosts.ready;
    for (final h in seedHosts) {
      await hosts.addHost(h);
    }
    final service = _SpyService(provider);
    final widget = MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: provider),
        ChangeNotifierProvider.value(value: hosts),
        Provider<PortForwardService>.value(value: service),
      ],
      child: ysTestApp(const PortForwardingScreen()),
    );
    lastService = service;
    return (provider, widget);
  }

  testWidgets('rule row shows start toggle, error line and conn chip',
      (tester) async {
    final (provider, widget) = await build();
    final fwd = PortForward(
        label: 'db tunnel',
        type: ForwardType.local,
        localPort: 8080,
        remoteHost: 'db',
        remotePort: 5432);
    await provider.add(fwd);

    await tester.pumpWidget(widget);
    await tester.pump();

    expect(find.text('db tunnel'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.play), findsOneWidget);

    provider.setStatus(fwd.id, ForwardStatus.error,
        error: 'Port 8080 already in use');
    await tester.pump();
    expect(find.text('Port 8080 already in use'), findsOneWidget);

    provider.setStatus(fwd.id, ForwardStatus.active);
    provider.setConnections(fwd.id, 3);
    await tester.pump();
    expect(find.byIcon(FLucideIcons.square), findsOneWidget);
    expect(find.text('3 conn'), findsOneWidget);
  });

  testWidgets('tapping a rule opens the edit panel prefilled', (tester) async {
    final (provider, widget) = await build();
    await provider.add(PortForward(
        label: 'edit me',
        type: ForwardType.local,
        localPort: 9090,
        remoteHost: 'web',
        remotePort: 80));

    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.tap(find.text('edit me'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Port Forward Rule'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('pf-label')),
            matching: find.text('edit me')),
        findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Auto-start on launch'), findsOneWidget);
  });

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
    await gesture.down(tester.getCenter(finder));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('right-click opens context menu with Duplicate/Edit/Delete',
      (tester) async {
    final (provider, widget) = await build();
    await provider.add(PortForward(
        label: 'menu me',
        type: ForwardType.local,
        localPort: 7000,
        remoteHost: 'db',
        remotePort: 5432));

    await tester.pumpWidget(widget);
    await tester.pump();
    await rightClick(tester, find.text('menu me'));

    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('Duplicate adds a copy with new id, "(copy)" label, autoStart off',
      (tester) async {
    final (provider, widget) = await build();
    final original = PortForward(
        label: 'db tunnel',
        type: ForwardType.local,
        localHost: '127.0.0.1',
        localPort: 8080,
        remoteHost: 'db.internal',
        remotePort: 5432,
        hostId: 'h1',
        autoStart: true);
    await provider.add(original);

    await tester.pumpWidget(widget);
    await tester.pump();
    await rightClick(tester, find.text('db tunnel'));
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(provider.forwards, hasLength(2));
    final copy =
        provider.forwards.firstWhere((f) => f.id != original.id);
    expect(copy.label, 'db tunnel (copy)');
    expect(copy.type, original.type);
    expect(copy.localHost, original.localHost);
    expect(copy.localPort, original.localPort);
    expect(copy.remoteHost, original.remoteHost);
    expect(copy.remotePort, original.remotePort);
    expect(copy.hostId, original.hostId);
    expect(copy.autoStart, isFalse);
    expect(copy.status, ForwardStatus.idle);
  });

  testWidgets('Edit menu entry opens the edit panel', (tester) async {
    final (provider, widget) = await build();
    await provider.add(PortForward(
        label: 'edit via menu',
        type: ForwardType.local,
        localPort: 9001,
        remoteHost: 'web',
        remotePort: 80));

    await tester.pumpWidget(widget);
    await tester.pump();
    await rightClick(tester, find.text('edit via menu'));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Port Forward Rule'), findsOneWidget);
  });

  testWidgets('Delete menu entry removes the rule', (tester) async {
    final (provider, widget) = await build();
    await provider.add(PortForward(
        label: 'delete via menu',
        type: ForwardType.local,
        localPort: 9002,
        remoteHost: 'web',
        remotePort: 80));

    await tester.pumpWidget(widget);
    await tester.pump();
    await rightClick(tester, find.text('delete via menu'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(provider.forwards, isEmpty);
  });

  Future<void> hover(WidgetTester tester, Finder finder) async {
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: Offset.zero);
    addTearDown(g.removePointer);
    await g.moveTo(tester.getCenter(finder));
    await tester.pump();
  }

  testWidgets('in-tile buttons fire: start, stop, hover delete', (tester) async {
    final (provider, widget) = await build();
    final fwd = PortForward(
        label: 'tile buttons',
        type: ForwardType.local,
        localPort: 8081,
        remoteHost: 'db',
        remotePort: 5432);
    await provider.add(fwd);
    await tester.pumpWidget(widget);
    await tester.pump();

    await tester.tap(find.byTooltip('Start'));
    await tester.pump();
    expect(lastService.started, [fwd.id]);

    provider.setStatus(fwd.id, ForwardStatus.active);
    await tester.pump();
    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
    expect(lastService.stopped, [fwd.id]);

    await hover(tester, find.text('tile buttons'));
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(provider.forwards, isEmpty);
    expect(lastService.stopped, hasLength(2));
  });

  testWidgets('editor: label autofocused, Tab advances, Enter saves',
      (tester) async {
    final (provider, widget) = await build();
    await tester.pumpWidget(widget);
    await tester.pump();

    await tester.tap(find.text('+ New Rule'));
    await tester.pumpAndSettle();
    expect(find.text('New Port Forward Rule'), findsOneWidget);

    // Label holds focus as soon as the panel opens.
    FocusNode? primary() => FocusManager.instance.primaryFocus;
    bool inField(String key) => find
        .descendant(
            of: find.byKey(ValueKey(key)), matching: find.byType(EditableText))
        .evaluate()
        .any((e) => primary()?.context != null &&
            (e.widget as EditableText).focusNode == primary());
    expect(inField('pf-label'), isTrue);

    await tester.enterText(find.byKey(const ValueKey('pf-label')), 'via enter');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(inField('pf-label'), isFalse);
    expect(primary()?.debugLabel, 'FSelect', reason: 'Type select is next');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(inField('pf-local-host'), isTrue, reason: 'then Local Host');

    await tester.enterText(find.byKey(const ValueKey('pf-local-port')), '8088');
    await tester.enterText(find.byKey(const ValueKey('pf-remote-host')), 'db');
    await tester.enterText(find.byKey(const ValueKey('pf-remote-port')), '5432');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(provider.forwards, hasLength(1));
    expect(provider.forwards.single.label, 'via enter');
    expect(provider.forwards.single.localPort, 8088);
    expect(find.text('New Port Forward Rule'), findsNothing,
        reason: 'panel closes after save');
  });

  testWidgets('editor validates required fields and per-type fields',
      (tester) async {
    final (provider, widget) = await build();
    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.tap(find.text('+ New Rule'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Rule'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsWidgets);
    expect(find.text('1–65535'), findsWidgets);
    expect(provider.forwards, isEmpty);

    // Dynamic SOCKS5 hides the remote fields.
    expect(find.byKey(const ValueKey('pf-remote-host')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pf-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dynamic SOCKS5').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pf-remote-host')), findsNothing);
  });

  testWidgets('900x600 with 60-char values does not overflow', (tester) async {
    final long = 'a' * 60;
    final (provider, widget) = await build(seedHosts: [
      Host(id: 'h1', label: 'h' * 60, host: 'h.example', username: 'root'),
    ]);
    final fwd = PortForward(
        label: long,
        type: ForwardType.local,
        localHost: long,
        localPort: 8080,
        remoteHost: long,
        remotePort: 5432,
        hostId: 'h1',
        autoStart: true);
    await provider.add(fwd);
    provider.setStatus(fwd.id, ForwardStatus.error, error: 'e' * 60);

    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.tap(find.byType(FTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Edit Port Forward Rule'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<void> fill(WidgetTester tester, Map<String, String> v) async {
    for (final e in v.entries) {
      await tester.enterText(find.byKey(ValueKey(e.key)), e.value);
    }
  }

  testWidgets('Enter on an invalid form shows errors and adds no rule',
      (tester) async {
    final (provider, widget) = await build();
    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.tap(find.text('+ New Rule'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pf-label')), 'x');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsWidgets);
    expect(find.text('1–65535'), findsWidgets);
    expect(provider.forwards, isEmpty);
    expect(find.text('New Port Forward Rule'), findsOneWidget);
  });

  testWidgets('Enter on the Dynamic type saves without remote fields',
      (tester) async {
    final (provider, widget) = await build();
    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.tap(find.text('+ New Rule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pf-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dynamic SOCKS5').last);
    await tester.pumpAndSettle();
    await fill(tester, {'pf-label': 'socks', 'pf-local-port': '1080'});
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(provider.forwards.single.type, ForwardType.dynamic);
    expect(provider.forwards.single.localPort, 1080);
  });

  testWidgets('a flagged port error clears as soon as the port is corrected',
      (tester) async {
    final (provider, widget) = await build();
    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.tap(find.text('+ New Rule'));
    await tester.pumpAndSettle();
    await fill(tester, {'pf-local-port': '70000'});
    await tester.tap(find.text('Add Rule'));
    await tester.pumpAndSettle();
    final inField = find.descendant(
      of: find.byKey(const ValueKey('pf-local-port')),
      matching: find.text('1–65535'),
    );
    expect(inField, findsOneWidget);
    await fill(tester, {'pf-local-port': '8080'});
    await tester.pumpAndSettle();
    expect(inField, findsNothing);
    expect(provider.forwards, isEmpty);
  });

  testWidgets('validation: whitespace label, ports 0 and 65536 rejected',
      (tester) async {
    final (provider, widget) = await build();
    await tester.pumpWidget(widget);
    await tester.pump();
    await tester.tap(find.text('+ New Rule'));
    await tester.pumpAndSettle();

    await fill(tester, {
      'pf-label': '   ',
      'pf-local-port': '0',
      'pf-remote-host': 'db',
      'pf-remote-port': '65536',
    });
    await tester.tap(find.text('Add Rule'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsOneWidget, reason: 'whitespace label');
    expect(find.text('1–65535'), findsNWidgets(2));
    expect(provider.forwards, isEmpty);

    await fill(tester, {
      'pf-label': 'ok',
      'pf-local-port': '65535',
      'pf-remote-port': '1',
    });
    await tester.ensureVisible(find.text('Add Rule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Rule'));
    await tester.pumpAndSettle();
    expect(provider.forwards, hasLength(1));
  });

  testWidgets('keyboard: Tab to Start reveals Delete, Tab reaches it',
      (tester) async {
    final (provider, widget) = await build();
    await provider.add(PortForward(
        label: 'kbd',
        type: ForwardType.local,
        localPort: 8085,
        remoteHost: 'db',
        remotePort: 1));
    await tester.pumpWidget(widget);
    await tester.pump();

    bool visible() => tester
        .widget<Visibility>(find.ancestor(
            of: find.byTooltip('Delete'), matching: find.byType(Visibility)))
        .visible;
    expect(visible(), isFalse);

    String? focusedTooltip() {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null) return null;
      String? found;
      ctx.visitAncestorElements((e) {
        if (e.widget is Tooltip) {
          found = (e.widget as Tooltip).message;
          return false;
        }
        return true;
      });
      return found;
    }

    for (var i = 0; i < 6 && focusedTooltip() != 'Start'; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(focusedTooltip(), 'Start');
    expect(visible(), isTrue, reason: 'focus inside row shows Delete');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusedTooltip(), 'Delete');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(provider.forwards, isEmpty);
  });
}
