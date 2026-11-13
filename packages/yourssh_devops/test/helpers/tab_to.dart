// Migrating the app to material_ui is a separate later step.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Presses Tab until the primary focus sits on [target] or an ancestor of it (or [max] presses
/// pass). Returns the number of presses, or -1 when never reached.
Future<int> tabTo(WidgetTester tester, Finder target, {int max = 30}) async {
  final targetElement = tester.element(target.first);
  for (var i = 1; i <= max; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) continue;
    // Focus lands on the control that wraps the target (button, tile).
    var found = identical(focused, targetElement);
    if (!found) {
      targetElement.visitAncestorElements((e) {
        if (identical(e, focused)) {
          found = true;
          return false;
        }
        return true;
      });
    }
    if (!found) {
      // Or the target wraps the focused control (a Tooltip around a button).
      focused.visitAncestorElements((e) {
        if (identical(e, targetElement)) {
          found = true;
          return false;
        }
        return true;
      });
    }
    if (found) return i;
  }
  return -1;
}
