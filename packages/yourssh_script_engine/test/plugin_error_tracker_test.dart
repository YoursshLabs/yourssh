import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_script_engine/src/plugin_error_tracker.dart';

void main() {
  test('isDisabled false below threshold of 10', () {
    final t = PluginErrorTracker('p1');
    for (var i = 0; i < 9; i++) t.recordError();
    expect(t.isDisabled, false);
  });

  test('isDisabled true at 10 errors', () {
    final t = PluginErrorTracker('p1');
    for (var i = 0; i < 10; i++) t.recordError();
    expect(t.isDisabled, true);
  });

  test('shouldWarn true at 5 errors', () {
    final t = PluginErrorTracker('p1');
    for (var i = 0; i < 5; i++) t.recordError();
    expect(t.shouldWarn, true);
    expect(t.isDisabled, false);
  });

  test('reset() clears error count', () {
    final t = PluginErrorTracker('p1');
    for (var i = 0; i < 10; i++) t.recordError();
    t.reset();
    expect(t.isDisabled, false);
    expect(t.errorCount, 0);
  });
}
