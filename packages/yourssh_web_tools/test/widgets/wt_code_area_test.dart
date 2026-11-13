import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_web_tools/src/widgets/wt_widgets.dart';

import '../helpers/ys_test_app.dart';

void main() {
  for (final text in ['', 'hello world & friends']) {
    testWidgets('WtCodeArea top-aligns ${text.isEmpty ? 'hint' : 'text'}',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = TextEditingController(text: text);
      await tester.pumpWidget(ysTestApp(SizedBox(
        height: 400,
        child: WtCodeArea(controller: c, hint: 'Type here'),
      )));
      await tester.pump();

      final field = tester.getRect(find.byType(WtCodeArea));
      final inner = tester.getRect(find.byType(EditableText));
      final shown = text.isEmpty ? find.text('Type here') : find.byType(EditableText);
      final top = tester.getRect(shown.first).top;
      expect(top - field.top, lessThan(40),
          reason: 'text must sit near the top of the 400px box '
              '(editable=$inner field=$field)');
    });
  }
}
