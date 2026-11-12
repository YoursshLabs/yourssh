# Context

- `packages/xterm/lib/src/ui/painter.dart` — `TerminalPainter`: `paintLine` / `paintCell*` (paragraph per cell via `ParagraphCache`, keyed by a cell hash), `getLinePicture` (per-line `Picture` LRU keyed by `BufferLine.version`, keyword highlights baked in), cursor/highlight helpers.
- `packages/xterm/lib/src/ui/render.dart` — `RenderTerminal._paint` replays line pictures at `(offset.dx, offset.dy + trunc(y))`, then cursor, controller highlights, selection (not cached).
- `app/lib/services/terminal_write_queue.dart` — repaint throttle: `commitInterval` 16 ms, `floodInterval` 33 ms when ≥ 32 KiB arrive per window.
- `app/test/widgets/xterm_line_picture_cache_test.dart` — cache + pixel-equivalence tests; `xterm_paint_benchmark_test.dart` — paint microbenchmark.
- Perf harness: `app/integration_test/terminal_perf_test.dart` (profile, macOS, local shell, `bench.sh` corpora plain/color/unicode/tui).

## Rendering facts measured in flutter_tester (Skia), MesloLGS NF 13 pt

- Horizontal subpixel positioning: 4 phases, `v = x_device + 1/8`, mask at `floor(v)`, phase `floor(frac(v) * 4)`.
- Vertical: the glyph snaps to the rounded device origin; same fractional origin ⇒ same mask (no model needed if tiles are rendered at the target's fractional y).
- A white glyph tinted with `BlendMode.modulate` differs from the directly colored glyph by up to 65/255 (Skia picks a luminance-dependent gamma for the mask); a tile rendered in the target color and composited with srcOver differs by at most 1/255 (premultiplied 8-bit rounding).
