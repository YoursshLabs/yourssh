import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import 'package:yourssh/models/local_session.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/widgets/record_button.dart';

import '../helpers/fake_recording.dart';
import '../helpers/ys_test_app.dart';

void main() {
  testWidgets('toggles recording with matching tooltips', (tester) async {
    final recording = FakeRecording();
    addTearDown(recording.dispose);
    final session = LocalSession(terminal: Terminal());

    await tester.pumpWidget(
      ChangeNotifierProvider<RecordingProvider>.value(
        value: recording,
        child: ysTestApp(Center(child: RecordButton(session: session))),
      ),
    );

    expect(find.byTooltip('Start recording'), findsOneWidget);
    expect(find.text('REC'), findsOneWidget);
    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pumpAndSettle();
    expect(recording.started, [session.id]);
    expect(find.byTooltip('Stop recording'), findsOneWidget);

    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pumpAndSettle();
    expect(recording.stopped, [session.id]);
    expect(find.byTooltip('Start recording'), findsOneWidget);
  });
}
