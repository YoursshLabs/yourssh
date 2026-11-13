import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/remote_workspace_chrome.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

void main() {
  for (final size in const [Size(1100, 700), Size(900, 600)]) {
    testWidgets('Retry is a normal-width centred button at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ysTestApp(
          const RemoteStatusOverlay(
            message: 'Disconnected by user',
            showRetry: true,
          ),
        ),
      );
      final button = tester.getRect(find.widgetWithText(FButton, 'Retry'));
      expect(button.width, lessThan(240));
      expect(
        (button.center.dx - tester.getCenter(find.byType(RemoteStatusOverlay)).dx)
            .abs(),
        lessThan(1),
      );
      final text = tester.getRect(find.text('Disconnected by user'));
      expect(button.top, greaterThan(text.bottom));
    });
  }
}
