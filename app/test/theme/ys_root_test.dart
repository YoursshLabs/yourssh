import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

void main() {
  testWidgets('FButton renders inside ysTestApp', (tester) async {
    await tester.pumpWidget(
      ysTestApp(FButton(onPress: () {}, child: const Text('Go'))),
    );
    expect(find.text('Go'), findsOneWidget);
  });

  testWidgets('touch root provides touch FTheme', (tester) async {
    late FThemeData theme;
    await tester.pumpWidget(
      ysTestApp(
        Builder(
          builder: (c) {
            theme = FTheme.of(c);
            return const SizedBox();
          },
        ),
        touch: true,
      ),
    );
    expect(
      theme.typography.body.md.fontSize,
      ysThemeDataTouch().typography.body.md.fontSize,
    );
    expect(
      theme.typography.body.md.fontSize,
      isNot(ysThemeData().typography.body.md.fontSize),
    );
  });

  testWidgets('dialog on the root navigator inherits FTheme', (tester) async {
    late BuildContext dialogCtx;
    await tester.pumpWidget(
      ysTestApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (c) {
                dialogCtx = c;
                return const FCard(child: Text('in dialog'));
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('in dialog'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // FTheme.of falls back silently, so assert the actual token.
    expect(FTheme.of(dialogCtx).colors.primary, YsColors.primary);
  });

  testWidgets('showFToast works under the root', (tester) async {
    await tester.pumpWidget(
      ysTestApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showFToast(context: context, title: const Text('toasted')),
            child: const Text('toast'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('toast'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('toasted'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('Material text theme uses Inter', (tester) async {
    late String? family;
    await tester.pumpWidget(
      ysTestApp(
        Builder(
          builder: (c) {
            family = Theme.of(c).textTheme.bodyMedium!.fontFamily;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(family, 'Inter');
  });

  test('mobile text styles use bundled fonts', () {
    expect(mobileBody().fontFamily, 'Inter');
    expect(mobileHeading().fontFamily, 'Inter');
    expect(mobileHeading().fontWeight, FontWeight.w600);
    expect(mobileMono().fontFamily, 'Roboto Mono for Powerline');
  });
}
