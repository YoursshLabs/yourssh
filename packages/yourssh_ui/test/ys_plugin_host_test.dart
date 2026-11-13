// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

class _Probe extends StatelessWidget {
  const _Probe();
  @override
  Widget build(BuildContext context) => Text(
    '${FTheme.of(context).colors.primary == YsColors.primary}',
  );
}

void main() {
  testWidgets('supplies the Ys theme when none is in scope', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: YsPluginHost(child: _Probe())),
    );
    expect(find.text('true'), findsOneWidget);
  });

  testWidgets('passes through under an existing Ys theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (c, child) => FTheme(data: ysThemeDataTouch(), child: child!),
        home: const YsPluginHost(child: _Probe()),
      ),
    );
    expect(find.text('true'), findsOneWidget);
    // No extra Material was inserted by the host.
    expect(find.descendant(of: find.byType(YsPluginHost), matching: find.byType(FToaster)), findsNothing);
  });
}
