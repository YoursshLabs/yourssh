import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: ysMaterialTheme(),
  builder: (context, c) => FTheme(data: ysThemeDataTouch(), child: c!),
  home: Scaffold(body: Column(children: [child])),
);

void main() {
  testWidgets('FItem is at least 44 px tall in the touch theme', (t) async {
    await t.pumpWidget(
      _wrap(
        FItem(
          prefix: const Icon(FLucideIcons.trash2),
          title: const Text('Remove'),
          onPress: () {},
        ),
      ),
    );
    expect(t.getSize(find.byType(FItem)).height, greaterThanOrEqualTo(44));
  });

  testWidgets('FItem with a suffix is at least 44 px tall in the touch theme', (
    t,
  ) async {
    await t.pumpWidget(
      _wrap(
        FItem(
          title: const Text('Remove'),
          suffix: const Icon(FLucideIcons.chevronRight),
          onPress: () {},
        ),
      ),
    );
    expect(t.getSize(find.byType(FItem)).height, greaterThanOrEqualTo(44));
  });

  testWidgets('FTile is at least 44 px tall in the touch theme', (t) async {
    await t.pumpWidget(
      _wrap(FTile(title: const Text('Remove'), onPress: () {})),
    );
    expect(t.getSize(find.byType(FTile)).height, greaterThanOrEqualTo(44));
  });
}
