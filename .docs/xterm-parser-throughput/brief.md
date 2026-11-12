# xterm parser throughput — brief

**What:** Make the xterm fork's output path (`EscapeParser` → `Buffer` → `BufferLine`) parse and apply terminal output close to Ghostty's speed without changing behavior. Branch `perf/parser`; the output pipeline (PTY/SSH read path, `Terminal.write` notification batching, render invalidation, DEC 2026) is a separate branch.

**Why:** `Terminal.write` ran at ~10–20 MB/s AOT (~100 ns/byte); `cat` of a large log or a fast TUI was parser-bound. Ghostty handles the benchmark corpora at ≈167 / 92 / 61 / 98 MB/s (plain / color / unicode / tui).

**Targets (AOT, 120x40, 10000 lines, 16–64 KiB chunks):** plain ≥ 100, color ≥ 60, unicode ≥ 40, tui ≥ 60 MB/s; stretch: match Ghostty.

**Constraint:** identical behavior, including fork patches 1–9 (NFC composition, `BufferLine.version` picture cache, `droppedLines`, DoS limits) and the existing quirks/bugs of the old code.
