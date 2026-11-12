# Context

## Hot path (before)
- `Terminal.write(String)` → `EscapeParser.write` → `ByteConsumer.add` (`runes.toList()` per chunk into a `ListQueue`) → per character: `consume()`, `FastLookupTable` closure dispatch, `handler.writeChar` → `Buffer.writeChar` (charset closure, `wcwidth`, `currentLine` lookup through `IndexAwareCircularBuffer`, `BufferLine.setCell`).
- CSI params were a growable list; `clear()` on a growable list reallocates its backing store (VM shrink-to-fit), so every CSI allocated.
- Every line feed with full scrollback allocated a new `BufferLine` (`Uint32List`, 2 KiB at 120 columns).
- Patch 8 ran `unorm.nfc` on two fresh strings for every combining mark (≈40% of the unicode corpus).

## Profile (JIT CPU samples, baseline)
- plain: `runes.toList` / growable-list growth 27%, `ByteConsumer.consume` + `ListQueue.first` 10%, `Buffer.writeChar` 34% incl. (`setCell` 10%, charset 5%, `currentLine` 8%).
- color/tui: `_GrowableList._allocateData` 18–22% (rune lists + CSI params).
- unicode: `_tryComposeMark` 39% (`nfc` 33%).
- After the main rewrite: `TypedData.fillRange` clearing recycled lines 37% (it is an element loop in the VM) → replaced by `setRange` from a zero block.

## Files
- `packages/xterm/lib/src/core/escape/parser.dart`, `handler.dart` (`EscapeTextSink`)
- `packages/xterm/lib/src/core/buffer/buffer.dart` (`writeChars`, compose cache, `_lineForPush`), `line.dart` (`writeAsciiRun`, `tryRecycle`)
- `packages/xterm/lib/src/terminal.dart` (`writeChars`, `writeBytes`), `core/charset.dart` (`isIdentity`), `utils/circular_buffer.dart` (`pushVictim`), `utils/unicode_v11.dart` (`unicodeV11Table`)
- Benchmark: `packages/xterm/benchmark/write_benchmark.dart` (compile with `--packages=../../app/.dart_tool/package_config.json`; the xterm package cannot resolve its own dev_dependencies).
- Tests: `app/test/widgets/xterm_write_snapshot_test.dart`, `xterm_line_recycling_test.dart`, `xterm_write_bytes_test.dart`.

## Pre-existing bugs
Fixed afterwards (see `app/test/widgets/xterm_robustness_test.dart` and `xterm_fuzz_test.dart`): replaceWith/reflow scrambling the scrollback, scroll/deleteLines detaching lines, `ESC[1K`/`ESC[1J` at column 0 and truncated SGR 38/48 throwing, plus fuzz finds (insert start-index wrap, trimStart absolute index, reflow at width 1 / wide char in the last column / mixed grow, DECRC out of bounds, DCH at pending wrap).

Still open:
- `Buffer.resize` asserts when the scrollback (`maxLines`) is smaller than the 24 rows the buffers are created with.
