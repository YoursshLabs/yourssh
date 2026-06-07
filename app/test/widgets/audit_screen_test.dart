import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/models/audit_event.dart';
import 'package:yourssh/providers/audit_provider.dart';
import 'package:yourssh/services/audit_service.dart';
import 'package:yourssh/widgets/audit_screen.dart';

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
      child: const MaterialApp(home: Scaffold(body: AuditScreen())),
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
      child: const MaterialApp(home: Scaffold(body: AuditScreen())),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Audit log unavailable'), findsOneWidget);
  });
}
