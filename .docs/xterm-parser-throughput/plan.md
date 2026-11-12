# Plan

1. Benchmark (AOT, pure-Dart xterm core) + behavior snapshot test recorded on the old code (corpora, 240 fuzz cases incl. malformed input/exceptions/resizes, generic handler path). ✅
2. Parser: decode each chunk once into a reusable `Uint32List`, index-based scan, switch dispatch, allocation-free CSI params; keep re-scan of incomplete sequences and resume-after-exception semantics. ✅
3. `EscapeTextSink`: hand runs of text to `Terminal.writeChars` → `Buffer.writeChars` (one line lookup per line, ASCII runs copied straight into the line's storage, exact `writeChar` semantics otherwise). ✅
4. Memoize NFC composition of (base, mark). ✅
5. Reuse the line a full-scrollback line feed trims (skip lines with anchors / different capacity; bump version). ✅
6. Clear reused lines with `setRange` from a zero block. ✅
7. Let the sink find the end of the run (one scan instead of two). ✅
8. `Terminal.writeBytes(Uint8List)` decoding UTF-8 straight into the parser, identical to chunked `Utf8Decoder(allowMalformed: true)` + `write`. ✅
9. Full app test suite + analyze; document patch 10 in CLAUDE.md. ✅
