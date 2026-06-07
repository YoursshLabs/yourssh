import 'package:flutter/services.dart';

/// (scancode, isExtended) for the RDP set-1 keyboard layer, or null if the
/// key has no single-scancode RDP equivalent.
///
/// Deliberately unmapped: Pause (E1-prefixed sequence E1 1D 45, which
/// (scancode, extended) cannot express). PrintScreen is mapped to E0 0x37,
/// the pragmatic single code most servers accept.
(int, bool)? rdpScancodeFor(PhysicalKeyboardKey key) => _table[key.usbHidUsage];

(int, int) sessionPointFor({
  required double localX,
  required double localY,
  required double renderOffsetX,
  required double renderOffsetY,
  required double renderScale,
  required int sessionWidth,
  required int sessionHeight,
}) {
  final x = ((localX - renderOffsetX) / renderScale)
      .clamp(0, sessionWidth - 1)
      .round();
  final y = ((localY - renderOffsetY) / renderScale)
      .clamp(0, sessionHeight - 1)
      .round();
  return (x, y);
}

// USB HID usage → (set-1 scancode, extended). Source: USB HID-to-PS/2
// scan code translation table (Microsoft) — keys present on common layouts.
final Map<int, (int, bool)> _table = {
  0x00070004: (0x1E, false), 0x00070005: (0x30, false), 0x00070006: (0x2E, false), // A B C
  0x00070007: (0x20, false), 0x00070008: (0x12, false), 0x00070009: (0x21, false), // D E F
  0x0007000A: (0x22, false), 0x0007000B: (0x23, false), 0x0007000C: (0x17, false), // G H I
  0x0007000D: (0x24, false), 0x0007000E: (0x25, false), 0x0007000F: (0x26, false), // J K L
  0x00070010: (0x32, false), 0x00070011: (0x31, false), 0x00070012: (0x18, false), // M N O
  0x00070013: (0x19, false), 0x00070014: (0x10, false), 0x00070015: (0x13, false), // P Q R
  0x00070016: (0x1F, false), 0x00070017: (0x14, false), 0x00070018: (0x16, false), // S T U
  0x00070019: (0x2F, false), 0x0007001A: (0x11, false), 0x0007001B: (0x2D, false), // V W X
  0x0007001C: (0x15, false), 0x0007001D: (0x2C, false),                            // Y Z
  0x0007001E: (0x02, false), 0x0007001F: (0x03, false), 0x00070020: (0x04, false), // 1 2 3
  0x00070021: (0x05, false), 0x00070022: (0x06, false), 0x00070023: (0x07, false), // 4 5 6
  0x00070024: (0x08, false), 0x00070025: (0x09, false), 0x00070026: (0x0A, false), // 7 8 9
  0x00070027: (0x0B, false),                                                       // 0
  0x00070028: (0x1C, false), 0x00070029: (0x01, false), 0x0007002A: (0x0E, false), // Enter Esc Bksp
  0x0007002B: (0x0F, false), 0x0007002C: (0x39, false),                            // Tab Space
  0x0007002D: (0x0C, false), 0x0007002E: (0x0D, false),                            // - =
  0x0007002F: (0x1A, false), 0x00070030: (0x1B, false), 0x00070031: (0x2B, false), // [ ] \
  0x00070033: (0x27, false), 0x00070034: (0x28, false), 0x00070035: (0x29, false), // ; ' `
  0x00070036: (0x33, false), 0x00070037: (0x34, false), 0x00070038: (0x35, false), // , . /
  0x00070039: (0x3A, false),                                                       // CapsLock
  0x0007003A: (0x3B, false), 0x0007003B: (0x3C, false), 0x0007003C: (0x3D, false), // F1-F3
  0x0007003D: (0x3E, false), 0x0007003E: (0x3F, false), 0x0007003F: (0x40, false), // F4-F6
  0x00070040: (0x41, false), 0x00070041: (0x42, false), 0x00070042: (0x43, false), // F7-F9
  0x00070043: (0x44, false), 0x00070044: (0x57, false), 0x00070045: (0x58, false), // F10-F12
  0x00070046: (0x37, true),  0x00070047: (0x46, false),                            // PrtSc(approx) ScrLk
  // 0x00070048 Pause: intentionally unmapped (E1 sequence)
  0x00070049: (0x52, true),  0x0007004A: (0x47, true),  0x0007004B: (0x49, true),  // Ins Home PgUp
  0x0007004C: (0x53, true),  0x0007004D: (0x4F, true),  0x0007004E: (0x51, true),  // Del End PgDn
  0x0007004F: (0x4D, true),  0x00070050: (0x4B, true),  0x00070051: (0x50, true),  // → ← ↓
  0x00070052: (0x48, true),                                                        // ↑
  0x00070053: (0x45, false),                                                       // NumLock
  0x00070054: (0x35, true),  0x00070055: (0x37, false), 0x00070056: (0x4A, false), // KP/ KP* KP-
  0x00070057: (0x4E, false), 0x00070058: (0x1C, true),                             // KP+ KPEnter
  0x00070059: (0x4F, false), 0x0007005A: (0x50, false), 0x0007005B: (0x51, false), // KP1-3
  0x0007005C: (0x4B, false), 0x0007005D: (0x4C, false), 0x0007005E: (0x4D, false), // KP4-6
  0x0007005F: (0x47, false), 0x00070060: (0x48, false), 0x00070061: (0x49, false), // KP7-9
  0x00070062: (0x52, false), 0x00070063: (0x53, false),                            // KP0 KP.
  0x000700E0: (0x1D, false), 0x000700E1: (0x2A, false), 0x000700E2: (0x38, false), // LCtrl LShift LAlt
  0x000700E3: (0x5B, true),                                                        // LWin/Cmd
  0x000700E4: (0x1D, true),  0x000700E5: (0x36, false), 0x000700E6: (0x38, true),  // RCtrl RShift RAlt
  0x000700E7: (0x5C, true),                                                        // RWin/Cmd
};
