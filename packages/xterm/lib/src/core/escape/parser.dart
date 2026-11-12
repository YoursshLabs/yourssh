import 'dart:convert';
import 'dart:typed_data';

import 'package:xterm/src/core/color.dart';
import 'package:xterm/src/core/mouse/mode.dart';
import 'package:xterm/src/core/escape/handler.dart';
import 'package:xterm/src/utils/ascii.dart';

/// [EscapeParser] translates control characters and escape sequences into
/// function calls that the terminal can handle.
///
/// Design goals:
///  * Zero object allocation during processing.
///  * No internal state. Same input will always produce same output.
///
/// YOURSSH PATCH (throughput): input is decoded once into a reusable code
/// point buffer and scanned by index; runs of printable text go to an
/// [EscapeTextSink] in one call when the handler implements it. An
/// incomplete trailing sequence stays buffered and is re-scanned from its
/// ESC on the next [write], and when a handler throws, the rest of the chunk
/// is kept and processed by the next [write] — both exactly like the
/// previous queue-based implementation.
class EscapeParser {
  final EscapeHandler handler;

  EscapeParser(this.handler)
      : _sink = handler is EscapeTextSink ? handler as EscapeTextSink : null;

  final EscapeTextSink? _sink;

  /// Decoded code points. `[0, _length)` is input left over from earlier
  /// writes (an incomplete sequence, or the rest of a chunk whose handler
  /// threw); new input is appended after it.
  Uint32List _buf = Uint32List(4096);

  var _length = 0;

  /// Scan position in [_buf]; kept up to date before every handler call so
  /// [tokenEnd] and exception recovery see the consumed prefix.
  var _pos = 0;

  /// Number of code points consumed before `_buf[0]`.
  var _consumedBase = 0;

  /// Whether [_sink] is currently inside [EscapeTextSink.writeChars].
  var _inSink = false;

  /// Start of sequence or character being processed. Useful for debugging.
  var tokenBegin = 0;

  /// End of sequence or character being processed. Useful for debugging.
  int get tokenEnd => _consumedBase + _pos;

  void write(String chunk) {
    final n = chunk.length;
    var w = _length;
    if (w + n > _buf.length) {
      _grow(w + n);
    }
    final buf = _buf;
    // Same code points as `chunk.runes`: a surrogate pair is combined only
    // when both halves are in this chunk; lone surrogates pass through.
    for (var i = 0; i < n; i++) {
      var c = chunk.codeUnitAt(i);
      if (c >= 0xD800 && c <= 0xDBFF && i + 1 < n) {
        final d = chunk.codeUnitAt(i + 1);
        if (d >= 0xDC00 && d <= 0xDFFF) {
          c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
          i++;
        }
      }
      buf[w++] = c;
    }
    _process(w);
  }

  /// Up to three bytes of a UTF-8 sequence cut short by the end of the last
  /// [writeBytes] chunk.
  final _carry = Uint8List(4);

  var _carryLength = 0;

  /// Whether [writeBytes] has decoded any byte yet (a byte order mark is only
  /// dropped at the very start of the byte stream).
  var _bytesStarted = false;

  static const _utf8 = Utf8Decoder(allowMalformed: true);

  /// Writes UTF-8 encoded input. Equivalent to feeding the byte stream to one
  /// chunked `Utf8Decoder(allowMalformed: true)` and calling [write] with
  /// every string it produces — malformed bytes become U+FFFD exactly as
  /// that decoder reports them, a byte order mark at the start of the stream
  /// is dropped, and a sequence split across chunks is joined — but without
  /// building the intermediate strings.
  void writeBytes(Uint8List bytes) {
    var data = bytes;
    var end = bytes.length;
    if (_carryLength > 0) {
      data = Uint8List(_carryLength + end)
        ..setRange(0, _carryLength, _carry)
        ..setRange(_carryLength, _carryLength + end, bytes);
      end = data.length;
      _carryLength = 0;
    }

    // Hold back a sequence that the end of this chunk cut short.
    var stop = end;
    for (var k = end - 1; k >= 0 && k >= end - 3; k--) {
      final b = data[k];
      if (b < 0x80) break;
      if (b >= 0xC0) {
        final need = b >= 0xF0 ? 4 : (b >= 0xE0 ? 3 : 2);
        if (b >= 0xC2 && b <= 0xF4 && end - k < need) stop = k;
        break;
      }
    }
    for (var k = stop; k < end; k++) {
      _carry[_carryLength++] = data[k];
    }

    var i = 0;
    if (!_bytesStarted && stop > 0) {
      _bytesStarted = true;
      if (stop >= 3 &&
          data[0] == 0xEF &&
          data[1] == 0xBB &&
          data[2] == 0xBF) {
        i = 3;
      }
    }

    var w = _length;
    if (w + (stop - i) > _buf.length) {
      _grow(w + (stop - i));
    }
    final buf = _buf;

    while (i < stop) {
      var b0 = data[i];
      if (b0 < 0x80) {
        do {
          buf[w++] = b0;
          if (++i == stop) break;
          b0 = data[i];
        } while (b0 < 0x80);
        continue;
      }
      if (b0 >= 0xC2) {
        if (b0 < 0xE0) {
          if (i + 1 < stop) {
            final b1 = data[i + 1];
            if (b1 & 0xC0 == 0x80) {
              buf[w++] = ((b0 & 0x1F) << 6) | (b1 & 0x3F);
              i += 2;
              continue;
            }
          }
        } else if (b0 < 0xF0) {
          if (i + 2 < stop) {
            final b1 = data[i + 1];
            final b2 = data[i + 2];
            if (b1 >= (b0 == 0xE0 ? 0xA0 : 0x80) &&
                b1 <= (b0 == 0xED ? 0x9F : 0xBF) &&
                b2 & 0xC0 == 0x80) {
              buf[w++] = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F);
              i += 3;
              continue;
            }
          }
        } else if (b0 <= 0xF4) {
          if (i + 3 < stop) {
            final b1 = data[i + 1];
            final b2 = data[i + 2];
            final b3 = data[i + 3];
            if (b1 >= (b0 == 0xF0 ? 0x90 : 0x80) &&
                b1 <= (b0 == 0xF4 ? 0x8F : 0xBF) &&
                b2 & 0xC0 == 0x80 &&
                b3 & 0xC0 == 0x80) {
              buf[w++] = ((b0 & 0x07) << 18) |
                  ((b1 & 0x3F) << 12) |
                  ((b2 & 0x3F) << 6) |
                  (b3 & 0x3F);
              i += 4;
              continue;
            }
          }
        }
      }
      // Malformed: let the platform decoder report the bytes up to the next
      // ASCII byte (always a sequence boundary for it), so replacement
      // characters match it exactly.
      var k = i + 1;
      while (k < stop && data[k] >= 0x80) {
        k++;
      }
      final text = _utf8.convert(data, i, k);
      for (var j = 0; j < text.length; j++) {
        var c = text.codeUnitAt(j);
        if (c >= 0xD800 && c <= 0xDBFF && j + 1 < text.length) {
          final d = text.codeUnitAt(j + 1);
          if (d >= 0xDC00 && d <= 0xDFFF) {
            c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
            j++;
          }
        }
        buf[w++] = c;
      }
      i = k;
    }
    _process(w);
  }

  void _grow(int needed) {
    var capacity = _buf.length * 2;
    while (capacity < needed) {
      capacity *= 2;
    }
    final grown = Uint32List(capacity);
    grown.setRange(0, _length, _buf);
    _buf = grown;
  }

  /// Processes `_buf[0, end)` and keeps whatever was not consumed.
  void _process(int end) {
    _pos = 0;
    try {
      _run(end);
    } finally {
      if (_inSink) {
        _inSink = false;
        _pos = _sink!.writeCharsFailedAt + 1;
      }
      final rest = end - _pos;
      if (rest > 0 && _pos > 0) {
        _buf.setRange(0, rest, _buf, _pos);
      }
      _consumedBase += _pos;
      _length = rest;
      _pos = 0;
      if (_buf.length > _maxIdleBuffer && rest < _maxIdleBuffer ~/ 2) {
        final shrunk = Uint32List(_maxIdleBuffer ~/ 2);
        shrunk.setRange(0, rest, _buf);
        _buf = shrunk;
      }
    }
  }

  /// Buffers larger than this (in code points) are released after a write.
  static const _maxIdleBuffer = 1 << 20;

  void _run(int end) {
    final buf = _buf;
    final sink = _sink;
    var i = 0;
    while (i < end) {
      final c = buf[i];

      if (c >= 0x10 && c != Ascii.ESC) {
        // A run of characters the parser hands to writeChar.
        if (sink != null) {
          tokenBegin = _consumedBase + i;
          _inSink = true;
          i = sink.writeChars(buf, i, end);
          _inSink = false;
          continue;
        }
        do {
          tokenBegin = _consumedBase + i;
          _pos = i + 1;
          handler.writeChar(buf[i]);
          i++;
        } while (i < end && buf[i] >= 0x10 && buf[i] != Ascii.ESC);
        continue;
      }

      tokenBegin = _consumedBase + i;

      if (c == Ascii.ESC) {
        final next = _processEscape(i + 1, end);
        if (next < 0) {
          // Incomplete sequence: keep it (from the ESC) for the next write.
          _pos = i;
          return;
        }
        i = next;
        continue;
      }

      _pos = ++i;
      _processChar(c);
    }
    _pos = end;
  }

  /// Handles a C0 control character (`char < 0x10`).
  void _processChar(int char) {
    switch (char) {
      case 0x07:
        return handler.bell();
      case 0x08:
        return handler.backspaceReturn();
      case 0x09:
        return handler.tab();
      case 0x0a:
      case 0x0b:
      case 0x0c:
        return handler.lineFeed();
      case 0x0d:
        return handler.carriageReturn();
      case 0x0e:
        return handler.shiftOut();
      case 0x0f:
        return handler.shiftIn();
      default:
        return handler.unkownEscape(char);
    }
  }

  /// Processes a sequence that starts with the ESC before `_buf[i]`. Returns
  /// the index after the sequence, or -1 if the sequence is not complete.
  int _processEscape(int i, int end) {
    if (i >= end) return -1;

    final escapeChar = _buf[i++];

    switch (escapeChar) {
      case 0x5b: // [
        return _escHandleCSI(i, end);
      case 0x5d: // ]
        return _escHandleOSC(i, end);
      case 0x37: // 7 — Save Cursor (DECSC)
        _pos = i;
        handler.saveCursor();
        return i;
      case 0x38: // 8 — Restore Cursor (DECRC)
        _pos = i;
        handler.restoreCursor();
        return i;
      case 0x44: // D — Index (IND)
        _pos = i;
        handler.index();
        return i;
      case 0x45: // E — Next Line (NEL)
        _pos = i;
        handler.nextLine();
        return i;
      case 0x48: // H — Horizontal Tab Set (HTS)
        _pos = i;
        handler.setTapStop();
        return i;
      case 0x4d: // M — Reverse Index (RI)
        _pos = i;
        handler.reverseIndex();
        return i;
      case 0x28: // ( — SCS G0
      case 0x29: // ) — SCS G1
        if (i >= end) return -1;
        final name = _buf[i++];
        _pos = i;
        handler.designateCharset(escapeChar == 0x28 ? 0 : 1, name);
        return i;
      case 0x3e: // > — Normal Keypad (DECKPNM)
        _pos = i;
        handler.setAppKeypadMode(false);
        return i;
      case 0x3d: // = — Application Keypad (DECKPAM)
        _pos = i;
        handler.setAppKeypadMode(true);
        return i;
      default:
        _pos = i;
        handler.unkownEscape(escapeChar);
        return i;
    }
  }

  int _escHandleCSI(int i, int end) {
    final next = _consumeCsi(i, end);
    if (next < 0 || _csiDropped) return next;

    _pos = next;
    _dispatchCsi(_csi.finalByte);
    return next;
  }

  /// The last parsed [_Csi]. This is a mutable singletion by design to reduce
  /// object allocations.
  final _csi = _Csi();

  /// Largest numeric CSI parameter kept; bigger values are clamped so they
  /// can neither overflow negative nor drive huge loops/allocations.
  static const _maxCsiParam = 65535;

  /// Longest CSI body (after `ESC [`) scanned before the sequence is dropped.
  static const _maxCsiLength = 4096;

  /// Longest OSC body (after `ESC ]`) scanned before the sequence is dropped.
  static const _maxOscLength = 64 * 1024;

  /// Set by [_consumeCsi] when the sequence was dropped for being too long.
  bool _csiDropped = false;

  /// Parses a CSI starting at `_buf[i]` (after `ESC [`). Returns the index
  /// after it, or -1 if the CSI isn't complete. After a CSI is successfully
  /// parsed, [_csi] is updated.
  int _consumeCsi(int i, int end) {
    if (i >= end) {
      return -1;
    }

    final buf = _buf;
    final params = _csi.params;
    params.clear();
    _csiDropped = false;
    var scanned = 0;

    // test whether the csi is a `CSI ? Ps ...` or `CSI Ps ...`
    final prefix = buf[i];
    if (prefix >= Ascii.colon && prefix <= Ascii.questionMark) {
      _csi.prefix = prefix;
      i++;
    } else {
      _csi.prefix = null;
    }

    var param = 0;
    var hasParam = false;
    while (true) {
      // The sequence isn't completed, just ignore it.
      if (i >= end) {
        return -1;
      }

      final char = buf[i++];

      if (++scanned > _maxCsiLength) {
        params.clear();
        _csiDropped = true;
        return i;
      }

      if (char == Ascii.semicolon) {
        if (hasParam) {
          params.add(param);
        }
        param = 0;
        continue;
      }

      if (char >= Ascii.num0 && char <= Ascii.num9) {
        hasParam = true;
        param = param * 10 + (char - Ascii.num0);
        if (param > _maxCsiParam) param = _maxCsiParam;
        continue;
      }

      if (char > Ascii.NULL && char < Ascii.num0) {
        // intermediates.add(char);
        continue;
      }

      if (char >= Ascii.atSign && char <= Ascii.tilde) {
        if (hasParam) {
          params.add(param);
        }

        _csi.finalByte = char;
        return i;
      }
    }
  }

  void _dispatchCsi(int finalByte) {
    switch (finalByte) {
      // case 0x61: // a
      //   return _csiHandleCursorHorizontalRelative();
      case 0x62: // b
        return _csiHandleRepeatPreviousCharacter();
      case 0x63: // c
        return _csiHandleSendDeviceAttributes();
      case 0x64: // d
        return _csiHandleLinePositionAbsolute();
      case 0x66: // f
        return _csiHandleCursorPosition();
      case 0x67: // g
        return _csiHandelClearTabStop();
      case 0x68: // h
      case 0x6c: // l
        return _csiHandleMode();
      case 0x6d: // m
        return _csiHandleSgr();
      case 0x6e: // n
        return _csiHandleDeviceStatusReport();
      case 0x72: // r
        return _csiHandleSetMargins();
      case 0x74: // t
        return _csiWindowManipulation();
      case 0x41: // A
        return _csiHandleCursorUp();
      case 0x42: // B
        return _csiHandleCursorDown();
      case 0x43: // C
        return _csiHandleCursorForward();
      case 0x44: // D
        return _csiHandleCursorBackward();
      case 0x45: // E
        return _csiHandleCursorNextLine();
      case 0x46: // F
        return _csiHandleCursorPrecedingLine();
      case 0x47: // G
        return _csiHandleCursorHorizontalAbsolute();
      case 0x48: // H
        return _csiHandleCursorPosition();
      case 0x4a: // J
        return _csiHandleEraseDisplay();
      case 0x4b: // K
        return _csiHandleEraseLine();
      case 0x4c: // L
        return _csiHandleInsertLines();
      case 0x4d: // M
        return _csiHandleDeleteLines();
      case 0x50: // P
        return _csiHandleDelete();
      case 0x53: // S
        return _csiHandleScrollUp();
      case 0x54: // T
        return _csiHandleScrollDown();
      case 0x58: // X
        return _csiHandleEraseCharacters();
      case 0x40: // @
        return _csiHandleInsertBlankCharacters();
      default:
        return handler.unknownCSI(finalByte);
    }
  }

  /// `ESC [ Ps a` Cursor Horizontal Position Relative (HPR)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sa/
  // void _csiHandleCursorHorizontalRelative() {
  //   if (_csi.params.isEmpty) {
  //     handler.cursorHorizontal(1);
  //   } else {
  //     handler.cursorHorizontal(_csi.params[0]);
  //   }
  // }

  /// `ESC [ Ps b` Repeat Previous Character (REP)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sb/
  void _csiHandleRepeatPreviousCharacter() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.repeatPreviousCharacter(amount);
  }

  /// `ESC [ Ps c` Device Attributes (DA)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sc/
  void _csiHandleSendDeviceAttributes() {
    switch (_csi.prefix) {
      case Ascii.greaterThan:
        return handler.sendSecondaryDeviceAttributes();
      case Ascii.equal:
        return handler.sendTertiaryDeviceAttributes();
      default:
        handler.sendPrimaryDeviceAttributes();
    }
  }

  /// `ESC [ Ps d` Cursor Vertical Position Absolute (VPA)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sd/
  void _csiHandleLinePositionAbsolute() {
    var y = 1;

    if (_csi.params.isNotEmpty) {
      y = _csi.params[0];
    }

    handler.setCursorY(y - 1);
  }

  /// `ESC [ Ps ; Ps f` Alias: Set Cursor Position
  ///
  /// https://terminalguide.namepad.de/seq/csi_sf/
  void _csiHandleCursorPosition() {
    var row = 1;
    var col = 1;

    if (_csi.params.length == 2) {
      row = _csi.params[0];
      col = _csi.params[1];
    }

    handler.setCursor(col - 1, row - 1);
  }

  /// `ESC [ Ps g` Tab Clear (TBC)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sg/
  void _csiHandelClearTabStop() {
    var cmd = 0;

    if (_csi.params.length == 1) {
      cmd = _csi.params[0];
    }

    switch (cmd) {
      case 0:
        return handler.clearTabStopUnderCursor();
      default:
        return handler.clearAllTabStops();
    }
  }

  /// - `ESC [ [ Pm ] h Set Mode (SM)` https://terminalguide.namepad.de/seq/csi_sm/
  /// - `ESC [ ? [ Pm ] h` Set Mode (?) (SM) https://terminalguide.namepad.de/seq/csi_sh__p/
  /// - `ESC [ [ Pm ] l` Reset Mode (RM) https://terminalguide.namepad.de/seq/csi_rm/
  /// - `ESC [ ? [ Pm ] l` Reset Mode (?) (RM) https://terminalguide.namepad.de/seq/csi_sl__p/
  void _csiHandleMode() {
    final isEnabled = _csi.finalByte == Ascii.h;

    final isDecModes = _csi.prefix == Ascii.questionMark;

    final params = _csi.params;
    if (isDecModes) {
      for (var i = 0; i < params.length; i++) {
        _setDecMode(params[i], isEnabled);
      }
    } else {
      for (var i = 0; i < params.length; i++) {
        _setMode(params[i], isEnabled);
      }
    }
  }

  /// `ESC [ [ Ps ] m` Select Graphic Rendition (SGR)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sm/
  void _csiHandleSgr() {
    final params = _csi.params;

    if (params.isEmpty) {
      return handler.resetCursorStyle();
    }

    // This is a workaround for a bug in the analyzer.
    // ignore: dead_code
    for (var i = 0; i < _csi.params.length; i++) {
      final param = params[i];
      switch (param) {
        case 0:
          handler.resetCursorStyle();
          continue;
        case 1:
          handler.setCursorBold();
          continue;
        case 2:
          handler.setCursorFaint();
          continue;
        case 3:
          handler.setCursorItalic();
          continue;
        case 4:
          handler.setCursorUnderline();
          continue;
        case 5:
          handler.setCursorBlink();
          continue;
        case 7:
          handler.setCursorInverse();
          continue;
        case 8:
          handler.setCursorInvisible();
          continue;
        case 9:
          handler.setCursorStrikethrough();
          continue;

        case 21:
          handler.unsetCursorBold();
          continue;
        case 22:
          handler.unsetCursorFaint();
          continue;
        case 23:
          handler.unsetCursorItalic();
          continue;
        case 24:
          handler.unsetCursorUnderline();
          continue;
        case 25:
          handler.unsetCursorBlink();
          continue;
        case 27:
          handler.unsetCursorInverse();
          continue;
        case 28:
          handler.unsetCursorInvisible();
          continue;
        case 29:
          handler.unsetCursorStrikethrough();
          continue;

        case 30:
          handler.setForegroundColor16(NamedColor.black);
          continue;
        case 31:
          handler.setForegroundColor16(NamedColor.red);
          continue;
        case 32:
          handler.setForegroundColor16(NamedColor.green);
          continue;
        case 33:
          handler.setForegroundColor16(NamedColor.yellow);
          continue;
        case 34:
          handler.setForegroundColor16(NamedColor.blue);
          continue;
        case 35:
          handler.setForegroundColor16(NamedColor.magenta);
          continue;
        case 36:
          handler.setForegroundColor16(NamedColor.cyan);
          continue;
        case 37:
          handler.setForegroundColor16(NamedColor.white);
          continue;
        case 38:
          // A truncated extended color (`ESC [ 38 m`, `ESC [ 38 ; 5 m`,
          // `ESC [ 38 ; 2 ; 1 m`) is ignored along with the rest of the sequence,
          // as xterm does.
          if (i + 1 >= params.length) return;
          switch (params[i + 1]) {
            case 2:
              if (i + 4 >= params.length) return;
              handler.setForegroundColorRgb(
                  params[i + 2], params[i + 3], params[i + 4]);
              i += 4;
              break;
            case 5:
              if (i + 2 >= params.length) return;
              handler.setForegroundColor256(params[i + 2]);
              i += 2;
              break;
          }
          continue;
        case 39:
          handler.resetForeground();
          continue;

        case 40:
          handler.setBackgroundColor16(NamedColor.black);
          continue;
        case 41:
          handler.setBackgroundColor16(NamedColor.red);
          continue;
        case 42:
          handler.setBackgroundColor16(NamedColor.green);
          continue;
        case 43:
          handler.setBackgroundColor16(NamedColor.yellow);
          continue;
        case 44:
          handler.setBackgroundColor16(NamedColor.blue);
          continue;
        case 45:
          handler.setBackgroundColor16(NamedColor.magenta);
          continue;
        case 46:
          handler.setBackgroundColor16(NamedColor.cyan);
          continue;
        case 47:
          handler.setBackgroundColor16(NamedColor.white);
          continue;
        case 48:
          // A truncated extended color (`ESC [ 48 m`, `ESC [ 48 ; 5 m`,
          // `ESC [ 48 ; 2 ; 1 m`) is ignored along with the rest of the sequence,
          // as xterm does.
          if (i + 1 >= params.length) return;
          switch (params[i + 1]) {
            case 2:
              if (i + 4 >= params.length) return;
              handler.setBackgroundColorRgb(
                  params[i + 2], params[i + 3], params[i + 4]);
              i += 4;
              break;
            case 5:
              if (i + 2 >= params.length) return;
              handler.setBackgroundColor256(params[i + 2]);
              i += 2;
              break;
          }
          continue;
        case 49:
          handler.resetBackground();
          continue;

        case 90:
          handler.setForegroundColor16(NamedColor.brightBlack);
          continue;
        case 91:
          handler.setForegroundColor16(NamedColor.brightRed);
          continue;
        case 92:
          handler.setForegroundColor16(NamedColor.brightGreen);
          continue;
        case 93:
          handler.setForegroundColor16(NamedColor.brightYellow);
          continue;
        case 94:
          handler.setForegroundColor16(NamedColor.brightBlue);
          continue;
        case 95:
          handler.setForegroundColor16(NamedColor.brightMagenta);
          continue;
        case 96:
          handler.setForegroundColor16(NamedColor.brightCyan);
          continue;
        case 97:
          handler.setForegroundColor16(NamedColor.brightWhite);
          continue;

        case 100:
          handler.setBackgroundColor16(NamedColor.brightBlack);
          continue;
        case 101:
          handler.setBackgroundColor16(NamedColor.brightRed);
          continue;
        case 102:
          handler.setBackgroundColor16(NamedColor.brightGreen);
          continue;
        case 103:
          handler.setBackgroundColor16(NamedColor.brightYellow);
          continue;
        case 104:
          handler.setBackgroundColor16(NamedColor.brightBlue);
          continue;
        case 105:
          handler.setBackgroundColor16(NamedColor.brightMagenta);
          continue;
        case 106:
          handler.setBackgroundColor16(NamedColor.brightCyan);
          continue;
        case 107:
          handler.setBackgroundColor16(NamedColor.brightWhite);
          continue;

        default:
          handler.unsupportedStyle(param);
          continue;
      }
    }
  }

  /// `ESC [ Ps n` Device Status Report [Dispatch] (DSR)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sn/
  void _csiHandleDeviceStatusReport() {
    if (_csi.params.isEmpty) return;

    switch (_csi.params[0]) {
      case 5:
        return handler.sendOperatingStatus();
      case 6:
        return handler.sendCursorPosition();
    }
  }

  /// `ESC [ Ps ; Ps r` Set Top and Bottom Margins (DECSTBM)
  ///
  /// https://terminalguide.namepad.de/seq/csi_sr/
  void _csiHandleSetMargins() {
    var top = 1;
    int? bottom;

    if (_csi.params.length > 2) return;

    if (_csi.params.isNotEmpty) {
      top = _csi.params[0];

      if (_csi.params.length == 2) {
        bottom = _csi.params[1] - 1;
      }
    }

    handler.setMargins(top - 1, bottom);
  }

  /// `ESC [ Ps t` Window operations [DISPATCH]
  ///
  /// https://terminalguide.namepad.de/seq/csi_st/
  void _csiWindowManipulation() {
    // The sequence needs at least one parameter.
    if (_csi.params.isEmpty) {
      return;
    }
    // Most the commands in this group are either of the scope of this package,
    // or should be disabled for security risks.
    switch (_csi.params[0]) {
      // Window handling is currently not in the scope of the package.
      case 1: // Restore Terminal Window (show window if minimized)
      case 2: // Minimize Terminal Window
      case 3: // Set Terminal Window Position
      case 4: // Set Terminal Window Size in Pixels
      case 5: // Raise Terminal Window
      case 6: // Lower Terminal Window
      case 7: // Refresh/Redraw Terminal Window
        return;
      case 8: // Set Terminal Window Size (in characters)
        // This CSI contains 2 more parameters: width and height.
        if (_csi.params.length != 3) {
          return;
        }
        // Deliberately ignored: a remote peer must not be able to drive the
        // local buffer size (rows x cols allocation); the view owns it.
        return;
      // Window handling is currently no in the scope of the package.
      case 9: // Maximize Terminal Window
      case 10: // Alias: Maximize Terminal Window
      case 11: // Report Terminal Window State
      case 13: // Report Terminal Window Position
      case 14: // Report Terminal Window Size in Pixels
      case 15: // Report Screen Size in Pixels
      case 16: // Report Cell Size in Pixels
        return;
      case 18: // Report Terminal Size (in characters)
        handler.sendSize();
        return;
      // Screen handling is currently no in the scope of the package.
      case 19: // Report Screen Size (in characters)
      // Disabled as these can a security risk.
      case 20: // Get Icon Title
      case 21: // Get Terminal Title
      // Not implemented.
      case 22: // Push Terminal Title
      case 23: // Pop Terminal Title
        return;
      // Unknown CSI.
      default:
        return;
    }
  }

  /// `ESC [ Ps A` Cursor Up (CUU)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ca/
  void _csiHandleCursorUp() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorY(-amount);
  }

  /// `ESC [ Ps B` Cursor Down (CUD)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cb/
  void _csiHandleCursorDown() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorY(amount);
  }

  /// `ESC [ Ps C` Cursor Right (CUF)
  ///
  /// Cursor Right (CUF)
  void _csiHandleCursorForward() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorX(amount);
  }

  /// `ESC [ Ps D` Cursor Left (CUB)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cd/
  void _csiHandleCursorBackward() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.moveCursorX(-amount);
  }

  /// `ESC [ Ps E` Cursor Next Line (CNL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ce/
  void _csiHandleCursorNextLine() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.cursorNextLine(amount);
  }

  /// `ESC [ Ps F` Cursor Previous Line (CPL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cf/
  void _csiHandleCursorPrecedingLine() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
      if (amount == 0) amount = 1;
    }

    handler.cursorPrecedingLine(amount);
  }

  void _csiHandleCursorHorizontalAbsolute() {
    var x = 1;

    if (_csi.params.isNotEmpty) {
      x = _csi.params[0];
      if (x == 0) x = 1;
    }

    handler.setCursorX(x - 1);
  }

  /// ESC [ Ps J Erase Display [Dispatch] (ED)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cj/
  void _csiHandleEraseDisplay() {
    var cmd = 0;

    if (_csi.params.length == 1) {
      cmd = _csi.params[0];
    }

    switch (cmd) {
      case 0:
        return handler.eraseDisplayBelow();
      case 1:
        return handler.eraseDisplayAbove();
      case 2:
        return handler.eraseDisplay();
      case 3:
        return handler.eraseScrollbackOnly();
    }
  }

  /// `ESC [ Ps K` Erase Line [Dispatch] (EL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ck/
  void _csiHandleEraseLine() {
    var cmd = 0;

    if (_csi.params.length == 1) {
      cmd = _csi.params[0];
    }

    switch (cmd) {
      case 0:
        return handler.eraseLineRight();
      case 1:
        return handler.eraseLineLeft();
      case 2:
        return handler.eraseLine();
    }
  }

  /// `ESC [ Ps L` Insert Line (IL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cl/
  void _csiHandleInsertLines() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
    }

    handler.insertLines(amount);
  }

  /// ESC [ Ps M Delete Line (DL)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cm/
  void _csiHandleDeleteLines() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
    }

    handler.deleteLines(amount);
  }

  /// ESC [ Ps P Delete Character (DCH)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cp/
  void _csiHandleDelete() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
    }

    handler.deleteChars(amount);
  }

  /// `ESC [ Ps S` Scroll Up (SU)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cs/
  void _csiHandleScrollUp() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
    }

    handler.scrollUp(amount);
  }

  /// `ESC [ Ps T `Scroll Down (SD)
  ///
  /// https://terminalguide.namepad.de/seq/csi_ct_1param/
  void _csiHandleScrollDown() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
    }

    handler.scrollDown(amount);
  }

  /// `ESC [ Ps X` Erase Character (ECH)
  ///
  /// https://terminalguide.namepad.de/seq/csi_cx/
  void _csiHandleEraseCharacters() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
    }

    handler.eraseChars(amount);
  }

  /// `ESC [ Ps @` Insert Blanks (ICH)
  ///
  /// https://terminalguide.namepad.de/seq/csi_x40_at/
  ///
  /// Inserts amount spaces at current cursor position moving existing cell
  /// contents to the right. The contents of the amount right-most columns in
  /// the scroll region are lost. The cursor position is not changed.
  void _csiHandleInsertBlankCharacters() {
    var amount = 1;

    if (_csi.params.isNotEmpty) {
      amount = _csi.params[0];
    }

    handler.insertBlankChars(amount);
  }

  void _setMode(int mode, bool enabled) {
    switch (mode) {
      case 4:
        return handler.setInsertMode(enabled);
      case 20:
        return handler.setLineFeedMode(enabled);
      default:
        return handler.setUnknownMode(mode, enabled);
    }
  }

  void _setDecMode(int mode, bool enabled) {
    switch (mode) {
      case 1:
        return handler.setCursorKeysMode(enabled);
      case 3:
        return handler.setColumnMode(enabled);
      case 5:
        return handler.setReverseDisplayMode(enabled);
      case 6:
        return handler.setOriginMode(enabled);
      case 7:
        return handler.setAutoWrapMode(enabled);
      case 9:
        return enabled
            ? handler.setMouseMode(MouseMode.clickOnly)
            : handler.setMouseMode(MouseMode.none);
      case 12:
      case 13:
        return handler.setCursorBlinkMode(enabled);
      case 25:
        return handler.setCursorVisibleMode(enabled);
      case 47:
        if (enabled) {
          return handler.useAltBuffer();
        } else {
          return handler.useMainBuffer();
        }
      case 66:
        return handler.setAppKeypadMode(enabled);
      case 1000:
      case 10061000:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScroll)
            : handler.setMouseMode(MouseMode.none);
      case 1001:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScroll)
            : handler.setMouseMode(MouseMode.none);
      case 1002:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScrollDrag)
            : handler.setMouseMode(MouseMode.none);
      case 1003:
        return enabled
            ? handler.setMouseMode(MouseMode.upDownScrollMove)
            : handler.setMouseMode(MouseMode.none);
      case 1004:
        return handler.setReportFocusMode(enabled);
      case 1005:
        return enabled
            ? handler.setMouseReportMode(MouseReportMode.utf)
            : handler.setMouseReportMode(MouseReportMode.normal);
      case 1006:
        return enabled
            ? handler.setMouseReportMode(MouseReportMode.sgr)
            : handler.setMouseReportMode(MouseReportMode.normal);
      case 1007:
        return handler.setAltBufferMouseScrollMode(enabled);
      case 1015:
        return enabled
            ? handler.setMouseReportMode(MouseReportMode.urxvt)
            : handler.setMouseReportMode(MouseReportMode.normal);
      case 1047:
        if (enabled) {
          handler.useAltBuffer();
        } else {
          handler.clearAltBuffer();
          handler.useMainBuffer();
        }
        return;
      case 1048:
        if (enabled) {
          return handler.saveCursor();
        } else {
          return handler.restoreCursor();
        }
      case 1049:
        if (enabled) {
          handler.saveCursor();
          handler.clearAltBuffer();
          handler.useAltBuffer();
        } else {
          handler.useMainBuffer();
        }
        return;
      case 2004:
        return handler.setBracketedPasteMode(enabled);
      default:
        return handler.setUnknownDecMode(mode, enabled);
    }
  }

  /// Parses and dispatches an OSC starting at `_buf[i]` (after `ESC ]`).
  /// Returns the index after it, or -1 if the sequence isn't complete.
  int _escHandleOSC(int i, int end) {
    final next = _consumeOsc(i, end);
    if (next < 0) {
      return -1;
    }

    _pos = next;

    if (_osc.isEmpty) {
      return next;
    }

    // Common OSCs
    if (_osc.length >= 2) {
      final ps = _osc[0];
      final pt = _osc[1];

      switch (ps) {
        case '0':
          handler.setTitle(pt);
          handler.setIconName(pt);
          return next;
        case '1':
          handler.setIconName(pt);
          return next;
        case '2':
          handler.setTitle(pt);
          return next;
      }
    }

    // Private extensions
    handler.unknownOSC(_osc[0], _osc.sublist(1));

    return next;
  }

  final _osc = <String>[];

  final _oscParam = StringBuffer();

  int _consumeOsc(int i, int end) {
    _osc.clear();
    final param = _oscParam..clear();
    final buf = _buf;
    var scanned = 0;

    while (true) {
      if (i >= end) {
        return -1;
      }

      final char = buf[i++];

      // Unterminated and oversized: drop it so it is neither rescanned on
      // every write nor buffered without bound.
      if (++scanned > _maxOscLength) {
        _osc.clear();
        return i;
      }

      // OSC terminates with BEL
      if (char == Ascii.BEL) {
        _osc.add(param.toString());
        return i;
      }

      /// OSC terminates with ST
      if (char == Ascii.ESC) {
        if (i >= end) {
          return -1;
        }

        if (buf[i++] == Ascii.backslash) {
          _osc.add(param.toString());
        }

        return i;
      }

      /// Parse next parameter
      if (char == Ascii.semicolon) {
        _osc.add(param.toString());
        param.clear();
        continue;
      }

      param.writeCharCode(char);
    }
  }
}

class _Csi {
  int? prefix;

  final params = _CsiParams();

  int finalByte = 0;

  @override
  String toString() {
    return params.toString() + String.fromCharCode(finalByte);
  }
}

/// Fixed-capacity, allocation-free parameter list of a CSI. Reading past
/// [length] throws a [RangeError], like the growable list it replaces.
class _CsiParams {
  // A CSI body is at most EscapeParser._maxCsiLength code points, so it
  // cannot hold more parameters than that.
  final _values = Int32List(EscapeParser._maxCsiLength + 1);

  var _length = 0;

  int get length => _length;

  bool get isEmpty => _length == 0;

  bool get isNotEmpty => _length != 0;

  int operator [](int index) {
    if (index < 0 || index >= _length) {
      throw RangeError.range(index, 0, _length - 1, 'index');
    }
    return _values[index];
  }

  void add(int value) {
    _values[_length++] = value;
  }

  void clear() {
    _length = 0;
  }

  @override
  String toString() {
    return [for (var i = 0; i < _length; i++) _values[i]].join(';');
  }
}
