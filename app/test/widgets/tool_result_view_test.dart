import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/tool_result.dart';
import 'package:yourssh/widgets/tool_result_view.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

void main() {
  testWidgets('empty state prompts to run a tool', (tester) async {
    await tester.pumpWidget(ysTestApp(const ToolResultView()));
    expect(find.text('Run a tool to see output'), findsOneWidget);
  });

  testWidgets('loading shows a progress indicator', (tester) async {
    await tester.pumpWidget(ysTestApp(const ToolResultView(isLoading: true)));
    expect(find.byType(FCircularProgress), findsOneWidget);
  });

  testWidgets('success shows duration, output and Copy output copies it', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      ysTestApp(
        ToolResultView(
          result: ToolResult.success(output: 'line one', durationMs: 42),
        ),
      ),
    );
    expect(find.text('Success (42ms)'), findsOneWidget);
    expect(find.text('line one'), findsOneWidget);
    expect(find.byTooltip('Copy output'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy output'));
    await tester.pump();
    expect(copied, 'line one');
    expect(find.text('Copied'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('failure shows Error and the error text', (tester) async {
    await tester.pumpWidget(
      ysTestApp(ToolResultView(result: ToolResult.failure(error: 'boom'))),
    );
    expect(find.text('Error'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
  });

  testWidgets('long output line does not overflow at 900x600', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ysTestApp(
        ToolResultView(
          result: ToolResult.success(output: 'x' * 400, durationMs: 1),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
