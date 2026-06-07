import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/util/rdp_input_mapping.dart';

void main() {
  test('letters, digits, modifiers map to set-1 scancodes', () {
    expect(rdpScancodeFor(PhysicalKeyboardKey.keyA), (0x1E, false));
    expect(rdpScancodeFor(PhysicalKeyboardKey.digit1), (0x02, false));
    expect(rdpScancodeFor(PhysicalKeyboardKey.enter), (0x1C, false));
    expect(rdpScancodeFor(PhysicalKeyboardKey.controlLeft), (0x1D, false));
    expect(rdpScancodeFor(PhysicalKeyboardKey.altRight), (0x38, true)); // E0
    expect(rdpScancodeFor(PhysicalKeyboardKey.arrowUp), (0x48, true));
    expect(rdpScancodeFor(PhysicalKeyboardKey.delete), (0x53, true));
    expect(rdpScancodeFor(PhysicalKeyboardKey.pause), isNull); // E1 — unsupported
    expect(rdpScancodeFor(PhysicalKeyboardKey.f24), isNull); // unmapped
  });

  test('mouse coordinates scale back to session space', () {
    // session 1920x1080 rendered into a 960x540 box at offset (10, 20)
    final p = sessionPointFor(
      localX: 490,
      localY: 290,
      renderOffsetX: 10,
      renderOffsetY: 20,
      renderScale: 0.5,
      sessionWidth: 1920,
      sessionHeight: 1080,
    );
    expect(p, (960, 540));
    // out of the rendered image → clamped
    final q = sessionPointFor(
      localX: 0,
      localY: 0,
      renderOffsetX: 10,
      renderOffsetY: 20,
      renderScale: 0.5,
      sessionWidth: 1920,
      sessionHeight: 1080,
    );
    expect(q, (0, 0));
  });
}
