import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/terminal/accessory_bar_controller.dart';

void main() {
  test('modifiers default off and consume returns false', () {
    final c = AccessoryBarController();
    final m = c.consumeModifiers();
    expect(m.ctrl, isFalse);
    expect(m.alt, isFalse);
  });

  test('armed ctrl is one-shot: consumed once then cleared', () {
    final c = AccessoryBarController();
    c.armCtrl();
    expect(c.ctrlArmed, isTrue);
    final m1 = c.consumeModifiers();
    expect(m1.ctrl, isTrue);
    expect(c.ctrlArmed, isFalse); // cleared after consume
    final m2 = c.consumeModifiers();
    expect(m2.ctrl, isFalse);
  });

  test('arm toggles off when armed again', () {
    final c = AccessoryBarController();
    c.armCtrl();
    c.armCtrl();
    expect(c.ctrlArmed, isFalse);
  });
}
