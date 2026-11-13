import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/models/audit_event.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/audit_provider.dart';
import 'package:yourssh/services/audit_service.dart';
import 'package:yourssh/widgets/audit_screen.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

void main() {
  testWidgets('renders rows and narrows by type filter', (tester) async {
    final svc = AuditService()..initInMemory();
    svc.record(AuditEvent.now(
        type: AuditEventType.exec, command: 'docker ps', exitCode: 0));
    svc.record(AuditEvent.now(type: AuditEventType.connect));
    final provider = AuditProvider(svc)..refresh();

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider.value(value: provider)],
      child: ysTestApp(const AuditScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('docker ps'), findsOneWidget);
    expect(find.text('connect'), findsWidgets);

    provider.setType('connect');
    await tester.pumpAndSettle();
    expect(find.text('docker ps'), findsNothing);

    svc.dispose();
  });

  testWidgets('shows the unavailable state when the DB failed to open',
      (tester) async {
    final svc = AuditService(); // never initialized
    final provider = AuditProvider(svc);

    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider.value(value: provider)],
      child: ysTestApp(const AuditScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Audit log unavailable'), findsOneWidget);
  });

  Widget wrap(AuditProvider p) => MultiProvider(
    providers: [ChangeNotifierProvider.value(value: p)],
    child: ysTestApp(const AuditScreen()),
  );

  testWidgets('header actions, filters and search are present', (tester) async {
    final svc = AuditService()..initInMemory();
    final provider = AuditProvider(svc)..refresh();
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(provider));
    await tester.pumpAndSettle();

    expect(find.text('AUDIT LOG'), findsOneWidget);
    expect(find.text('CSV'), findsOneWidget);
    expect(find.text('JSON'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('No audit events'), findsOneWidget);
    for (final r in ['Today', '7d', '30d', 'All']) {
      expect(find.text(r), findsOneWidget);
    }
    expect(find.text('Search command or host…'), findsOneWidget);

    await tester.tap(find.text('7d'));
    await tester.pumpAndSettle();
    expect(provider.rangeDays, 7);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(provider.rangeDays, 1);

    await tester.tap(find.byKey(const ValueKey('audit-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('exec').last);
    await tester.pumpAndSettle();
    expect(provider.type, 'exec');

    svc.dispose();
  });

  testWidgets('search submits on Enter and the box mirrors the provider',
      (tester) async {
    final svc = AuditService()..initInMemory();
    svc.record(AuditEvent.now(type: AuditEventType.exec, command: 'docker ps'));
    svc.record(AuditEvent.now(type: AuditEventType.exec, command: 'ls -la'));
    final provider = AuditProvider(svc)
      ..search = 'docker'
      ..refresh();
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(provider));
    await tester.pumpAndSettle();

    final box = find.descendant(
      of: find.byKey(const ValueKey('audit-search')),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(box).controller.text, 'docker');

    await tester.enterText(find.byKey(const ValueKey('audit-search')), 'ls');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(provider.search, 'ls');
    expect(find.text('ls -la'), findsOneWidget);
    expect(find.text('docker ps'), findsNothing);
    svc.dispose();
  });

  testWidgets('Load more pages in the next 200 rows', (tester) async {
    final svc = AuditService()..initInMemory();
    for (var i = 0; i < 201; i++) {
      svc.record(AuditEvent.now(type: AuditEventType.exec, command: 'cmd $i'));
    }
    final provider = AuditProvider(svc)..refresh();
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(provider));
    await tester.pumpAndSettle();
    expect(provider.events, hasLength(200));
    expect(provider.hasMore, isTrue);

    await tester.scrollUntilVisible(
      find.text('Load more'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(provider.events, hasLength(201));
    svc.dispose();
  });

  testWidgets('Clear confirms with Cancel focused and clears on confirm',
      (tester) async {
    final svc = AuditService()..initInMemory();
    svc.record(AuditEvent.now(type: AuditEventType.exec, command: 'docker ps'));
    final provider = AuditProvider(svc)..refresh();
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Clear audit log?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(provider.events, hasLength(1));

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FButton, 'Clear').last);
    await tester.pumpAndSettle();
    expect(provider.events, isEmpty);
    svc.dispose();
  });

  testWidgets('900x600 with 60-char host, command and error does not overflow',
      (tester) async {
    final svc = AuditService()..initInMemory();
    final long = 'x' * 60;
    svc.record(AuditEvent.now(
        type: AuditEventType.exec,
        host: Host(label: long, host: 'h.example', username: long),
        command: long,
        exitCode: 127));
    svc.record(AuditEvent.now(
        type: AuditEventType.disconnect, meta: {'error': long, 'source': long}));
    final provider = AuditProvider(svc)..refresh();
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(provider));
    await tester.pumpAndSettle();
    expect(find.byType(FButton), findsWidgets);
    expect(tester.takeException(), isNull);
    svc.dispose();
  });

  testWidgets('time-range chips expose selected semantics', (tester) async {
    final svc = AuditService()..initInMemory();
    final provider = AuditProvider(svc)..refresh();
    final sem = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(provider));
    await tester.pumpAndSettle();

    bool selected(int days) {
      final node = tester.getSemantics(find.byKey(ValueKey('audit-range-$days')));
      return containsSemantics(isSelected: true).matches(node, {});
    }

    final current = provider.rangeDays;
    final other = current == 7 ? 30 : 7;
    expect(selected(current), isTrue);
    expect(selected(other), isFalse);

    provider.setRange(other);
    await tester.pumpAndSettle();
    expect(selected(other), isTrue);
    expect(selected(current), isFalse);

    sem.dispose();
    svc.dispose();
  });
}
