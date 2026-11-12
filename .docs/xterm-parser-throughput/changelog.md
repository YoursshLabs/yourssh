# Changelog

All numbers: AOT (`dart compile exe`), Apple M1 Max, 120x40, 10000 lines, 64 KiB chunks, best of 5, MB/s (plain / color / unicode / tui). Ghostty: ≈167 / 92 / 61 / 98.

- 2026-11-12 — Baseline `Terminal.write`: 17 / 19 / 14 / 20.
- `test(xterm)`: AOT benchmark (`packages/xterm/benchmark/write_benchmark.dart`) + behavior snapshot test recorded on the old code (`app/test/widgets/xterm_write_snapshot_test.dart`: 6 corpus digests, 240 fuzz cases, generic handler path). Mutations of the new code (CSI length cap, recycle clearing, wrap flag, charset bypass, compose-cache key) all fail it.
- `perf(xterm)`: parser over a reusable code point buffer, switch dispatch, allocation-free CSI params → 45 / 65 / 18 / 75.
- `perf(xterm)`: `EscapeTextSink` + `Buffer.writeChars` (bulk ASCII into line storage, one line lookup per line) → 81 / 80 / 20 / 193.
- `perf(xterm)`: memoized NFC composition → unicode 71.
- `perf(xterm)`: reuse the trimmed scrollback line → 94 / 88 / 77 / 191 (+ `xterm_line_recycling_test.dart`).
- `perf(xterm)`: clear reused lines with `setRange` (VM `fillRange` is an element loop) → 162 / 112 / 105 / 194.
- `perf(xterm)`: sink finds the end of each run (one scan) → 185 / 113 / 110 / 210.
- `feat(xterm)`: `Terminal.writeBytes(Uint8List)`; bytes-in end to end: decoder+write 161 / 102 / 82 / 190 vs writeBytes 189 / 112 / 101 / 214 (+ `xterm_write_bytes_test.dart`, differential against `Utf8Decoder` + `write`).
- `refactor(xterm)`: removed the unused `ByteConsumer`.
- Final `Terminal.write`: 180 / 111 / 111 / 214 (16 KiB chunks: 181 / 112 / 113 / 218). Full-corpus state digests identical to the baseline build.
- Verification: app `flutter test` 1892 passed / 3 skipped (1880 + 12 new; the 2 extra skips are the BENCH_DIR-gated perf tests from `b79439e`); `flutter analyze --no-fatal-infos` reports nothing in the touched files (one pre-existing warning: unused `dart:ui` import in `integration_test/terminal_perf_test.dart`, from `b79439e`).
