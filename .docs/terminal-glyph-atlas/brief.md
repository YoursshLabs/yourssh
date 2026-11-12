# Terminal glyph atlas — brief

**What:** Render terminal text through a glyph atlas (`Canvas.drawRawAtlas`) instead of one `drawParagraph` per cell, so a frame during an output flood costs ≤ 2 ms build / ≤ 4 ms raster at 121x40, then raise the flood repaint rate from 30 to 60 fps. Branch `perf/terminal`.

**Why:** Throughput is near Ghostty, but every flood frame re-records ~40 line pictures at ~130 µs/line (one `drawParagraph` per cell), ~6 ms build + ~4 ms raster, so `TerminalWriteQueue` throttles flood repaints to 30 fps.

**Constraints:** pixel output identical to the paragraph path (tiny, justified tolerance at most), including backgrounds, inverse, faint, underline, wide chars, selection, cursor and baked keyword highlights; keep the per-line picture LRU semantics (fork patch 4); throughput within 10% of now (plain ≤ 0.42 s, color ≤ 0.31, unicode ≤ 0.14, tui ≤ 0.24); CI Flutter 3.47.1 APIs only.
