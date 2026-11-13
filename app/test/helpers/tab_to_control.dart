import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Strict variant of `tabTo`: presses Tab until the primary focus node sits
/// on [target] itself or a descendant of it (never on an enclosing Focus, which
/// `tabTo` also accepts). Returns the number of presses, or -1 if never reached.
Future<int> tabToControl(WidgetTester tester, Finder target,
    {int max = 40}) async {
  final targetElement = tester.element(target.first);
  for (var i = 1; i <= max; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) continue;
    if (identical(focused, targetElement)) return i;
    var found = false;
    focused.visitAncestorElements((e) {
      if (identical(e, targetElement)) {
        found = true;
        return false;
      }
      return true;
    });
    if (found) return i;
  }
  return -1;
}
