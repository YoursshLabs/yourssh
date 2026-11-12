# Plan

1. Probe Skia glyph rasterization (subpixel phases, y snapping, color tinting) in flutter_tester. ✅
2. Pixel-equivalence tests first (atlas path vs paragraph path) with the bundled MesloLGS NF: ASCII, bold/italic/underline, faint, 16/256/truecolor fg+bg, inverse, wide CJK, emoji, combining Vietnamese, keyword highlights; render-level checks for selection and cursor shapes. ✅
3. `GlyphAtlas`: tiles keyed by (code point, bold/italic/faint, color, x phase, y fraction); asynchronous admission (render batch → read back → ink bounds + monochrome check → pack into one page via `toImageSync`); permanent fallback for color glyphs / overflowing ink; reset on style/scale/font/dpr change; thrash guard. ✅
4. `TerminalPainter`: atlas line recording (merged background runs + one `drawRawAtlas` per segment; order-preserving flush when glyph ink would be covered by a later background; fallback cells drawn with the old paragraph code in order); keyword foregrounds stay on paragraphs (now cached); line picture cache keyed also by atlas generation + device fraction. ✅
5. `RenderTerminal`/`TerminalView`: pass device pixel ratio and device-space origin fraction. ✅
6. Measure (paint benchmark + profile E2E), then raise `floodInterval` to 16 ms if throughput holds. ✅
7. Full test suite, analyze, CLAUDE.md patch notes. ✅
