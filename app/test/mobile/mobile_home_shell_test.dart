import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/screens/mobile_home_shell.dart';

void main() {
  testWidgets('shows four destinations and Hosts first', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MobileHomeShell()));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Hosts'), findsWidgets);
    expect(find.text('Sessions'), findsWidgets);
    expect(find.text('SFTP'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);

    // Hosts tab body is shown first.
    expect(find.text('Hosts — coming soon'), findsOneWidget);
  });

  testWidgets('tapping a destination switches the body', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MobileHomeShell()));

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.text('Settings — coming soon'), findsOneWidget);
    expect(find.text('Hosts — coming soon'), findsNothing);
  });
}
