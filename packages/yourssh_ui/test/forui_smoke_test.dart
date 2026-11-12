import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

void main() {
  testWidgets('forui button renders under a neutral dark theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: FTheme.neutral.dark.desktop,
          child: FButton(onPress: () {}, child: const Text('ok')),
        ),
      ),
    );
    expect(find.text('ok'), findsOneWidget);
  });
}
