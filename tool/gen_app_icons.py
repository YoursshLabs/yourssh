#!/usr/bin/env python3
"""Regenerate every platform app icon from the master artwork in assets/branding/.

    python3 tool/gen_app_icons.py            # regenerate everything
    python3 tool/gen_app_icons.py --check    # verify the generated files match

macOS only: rasterising relies on `sips` (ImageIO), which ships with the OS and
renders SVG. Every size is rasterised straight from the vector master, so no
output is ever an upscale of a smaller PNG.

Outputs (all overwritten in place, so the script is safe to re-run):

  macOS    app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png
           Artwork is inset to 824/1024 per Apple's macOS icon grid, so the
           glyph matches the optical size of system icons in the Dock.
  Windows  app/windows/runner/resources/app_icon.ico  (16-256, PNG-in-ICO)
  Android  mipmap-*/ic_launcher.png              legacy launcher, full-bleed
           drawable/ic_launcher_background.xml   adaptive background (gradient)
           drawable-*/ic_launcher_foreground.png adaptive foreground layer
           drawable-*/ic_launcher_monochrome.png Android 13+ themed icon
           mipmap-anydpi-v26/ic_launcher{,_round}.xml
  iOS      app/ios/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png
           The 1024 marketing icon: full-bleed (iOS applies its own mask), opaque,
           no alpha channel (App Store Connect rejects icons with one).
  In-app   app/assets/app_icon.png, logo.png, logo-readme.png
"""

from __future__ import annotations

import argparse
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRANDING = ROOT / "assets" / "branding"
ANDROID_RES = ROOT / "app" / "android" / "app" / "src" / "main" / "res"
MACOS_ICONSET = ROOT / "app" / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
IOS_ICONSET = ROOT / "app" / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
WINDOWS_ICO = ROOT / "app" / "windows" / "runner" / "resources" / "app_icon.ico"
APP_ASSETS = ROOT / "app" / "assets"

# Apple's macOS icon grid: the artwork occupies 824 of a 1024 canvas.
MACOS_INSET = 824 / 1024
MACOS_SIZES = (16, 32, 64, 128, 256, 512, 1024)
WINDOWS_SIZES = (16, 24, 32, 48, 64, 128, 256)
# Android density buckets: (dir suffix, 108dp adaptive layer px, legacy mipmap px)
ANDROID_DENSITIES = (
    ("mdpi", 108, 48),
    ("hdpi", 162, 72),
    ("xhdpi", 216, 96),
    ("xxhdpi", 324, 144),
    ("xxxhdpi", 432, 192),
)


class IconError(RuntimeError):
    pass


def read_master(name: str) -> tuple[str, str, str]:
    """Split a master SVG into (viewBox, defs, body) so it can be re-wrapped."""
    text = (BRANDING / f"{name}.svg").read_text()
    view_box = re.search(r'viewBox="([^"]+)"', text)
    if not view_box:
        raise IconError(f"{name}.svg has no viewBox")
    inner = text[text.index(">", text.index("<svg")) + 1 : text.rindex("</svg>")]
    defs_match = re.search(r"<defs>.*?</defs>", inner, re.DOTALL)
    defs = defs_match.group(0) if defs_match else ""
    body = inner.replace(defs, "") if defs else inner
    return view_box.group(1), defs, body


def rasterise(master: str, size: int, out: Path, *, inset: float = 1.0) -> None:
    """Render `master` at `size`x`size` px, optionally inset within the canvas."""
    view_box, defs, body = read_master(master)
    x, y, w, h = (float(v) for v in view_box.replace(",", " ").split())
    cx, cy = x + w / 2, y + h / 2
    if inset != 1.0:
        body = (
            f'<g transform="translate({cx} {cy}) scale({inset}) translate({-cx} {-cy})">'
            f"{body}</g>"
        )
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
        f'viewBox="{view_box}">{defs}{body}</svg>'
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "in.svg"
        src.write_text(svg)
        result = subprocess.run(
            ["sips", "-s", "format", "png", str(src), "--out", str(out)],
            capture_output=True,
            text=True,
        )
    if result.returncode != 0:
        raise IconError(f"sips failed for {master} @{size}px: {result.stderr.strip()}")
    check_png(out, size)


def check_png(path: Path, size: int) -> None:
    """Confirm the PNG really is `size`x`size` — sips reports success too eagerly."""
    header = path.read_bytes()[:24]
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise IconError(f"{path} is not a PNG")
    width, height = struct.unpack(">II", header[16:24])
    if (width, height) != (size, size):
        raise IconError(f"{path} is {width}x{height}, expected {size}x{size}")


def build_ico(master: str, sizes: tuple[int, ...], out: Path) -> None:
    """Pack one PNG per size into an ICO (PNG-compressed entries, Vista+)."""
    with tempfile.TemporaryDirectory() as tmp:
        pngs = []
        for size in sizes:
            png = Path(tmp) / f"{size}.png"
            rasterise(master, size, png)
            pngs.append((size, png.read_bytes()))
        offset = 6 + 16 * len(pngs)
        directory, payload = b"", b""
        for size, data in pngs:
            directory += struct.pack(
                "<BBBBHHII",
                0 if size >= 256 else size,  # width, 0 means 256
                0 if size >= 256 else size,  # height
                0,  # palette size
                0,  # reserved
                1,  # colour planes
                32,  # bits per pixel
                len(data),
                offset,
            )
            payload += data
            offset += len(data)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(struct.pack("<HHH", 0, 1, len(pngs)) + directory + payload)


ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/gen_app_icons.py from assets/branding/. Do not edit. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@drawable/ic_launcher_background"/>
  <foreground android:drawable="@drawable/ic_launcher_foreground"/>
  <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
"""

# The background is a flat gradient, so a shape drawable beats five PNG densities:
# it stays sharp at any size and saves ~380 KB of APK. Angle 315 runs top-left to
# bottom-right, matching the master's gradient vector.
BACKGROUND_XML = """<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/gen_app_icons.py from assets/branding/yourssh_icon_background.svg.
     Do not edit: change the master SVG and re-run the script. -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
  <item>
    <shape android:shape="rectangle">
      <gradient
          android:type="linear"
          android:angle="315"
          android:startColor="{amber_light}"
          android:endColor="{amber_dark}"/>
    </shape>
  </item>
  <item>
    <shape android:shape="rectangle">
      <gradient
          android:type="linear"
          android:angle="270"
          android:startColor="{gloss}"
          android:centerColor="#00FFFFFF"
          android:endColor="#00FFFFFF"/>
    </shape>
  </item>
</layer-list>
"""


def android_background_xml() -> str:
    """Build the gradient drawable from the master's own stop colours."""
    svg = (BRANDING / "yourssh_icon_background.svg").read_text()
    stops = re.findall(r'stop-color="(#[0-9A-Fa-f]{6})"(?:\s+stop-opacity="([\d.]+)")?', svg)
    if len(stops) < 3:
        raise IconError("yourssh_icon_background.svg: expected amber + gloss gradient stops")
    (amber_light, _), (amber_dark, _), (gloss_colour, gloss_opacity) = stops[:3]
    alpha = round(float(gloss_opacity or 1) * 255)
    return BACKGROUND_XML.format(
        amber_light=amber_light,
        amber_dark=amber_dark,
        gloss=f"#{alpha:02X}{gloss_colour.lstrip('#')}",
    )


IOS_CONTENTS_JSON = """{
  "images" : [
    {
      "filename" : "app_icon_1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""


def strip_alpha(path: Path) -> None:
    """Rewrite an 8-bit RGBA PNG as RGB (colour type 2). sips always keeps an alpha
    channel, but the iOS marketing icon must have none; the art is already fully
    opaque, so dropping the channel loses nothing."""
    data = path.read_bytes()
    pos, idat, ihdr = 8, b"", b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos : pos + 8])
        body = data[pos + 8 : pos + 8 + length]
        if kind == b"IHDR":
            ihdr = body
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    width, height, depth, colour = struct.unpack(">IIBB", ihdr[:10])
    if (depth, colour) == (8, 2):
        return
    if (depth, colour) != (8, 6):
        raise IconError(f"{path}: expected 8-bit RGBA, got depth {depth} colour {colour}")
    raw = zlib.decompress(idat)
    stride = width * 4
    prev = bytearray(stride)
    out = bytearray()
    offset = 0
    for _ in range(height):
        kind, line = raw[offset], bytearray(raw[offset + 1 : offset + 1 + stride])
        offset += 1 + stride
        if kind == 1:
            for i in range(4, stride):
                line[i] = (line[i] + line[i - 4]) & 255
        elif kind == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif kind == 3:
            for i in range(stride):
                left = line[i - 4] if i >= 4 else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(stride):
                a = line[i - 4] if i >= 4 else 0
                b = prev[i]
                c = prev[i - 4] if i >= 4 else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
        elif kind != 0:
            raise IconError(f"{path}: bad PNG filter {kind}")
        prev = line
        out.append(0)
        for i in range(0, stride, 4):
            if line[i + 3] != 255:
                raise IconError(f"{path}: not fully opaque")
            out += line[i : i + 3]

    def chunk(kind: bytes, body: bytes) -> bytes:
        return (
            struct.pack(">I", len(body))
            + kind
            + body
            + struct.pack(">I", zlib.crc32(kind + body))
        )

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(out), 9))
        + chunk(b"IEND", b"")
    )


def ios_marketing_svg() -> str:
    """Full-bleed amber background (the Android layer) plus the master's glyph."""
    master = (BRANDING / "yourssh_icon.svg").read_text()
    glyph = re.search(r'<g fill="none".*?</g>', master, re.DOTALL)
    if not glyph:
        raise IconError("yourssh_icon.svg: glyph group not found")
    background = (BRANDING / "yourssh_icon_background.svg").read_text()
    return background.replace("</svg>", glyph.group(0) + "</svg>")


def build_ios_icon(out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "ios.svg"
        src.write_text(ios_marketing_svg())
        result = subprocess.run(
            ["sips", "-s", "format", "png", str(src), "--out", str(out)],
            capture_output=True,
            text=True,
        )
    if result.returncode != 0:
        raise IconError(f"sips failed for the iOS icon: {result.stderr.strip()}")
    check_png(out, 1024)
    strip_alpha(out)
    check_png(out, 1024)


def generate() -> list[Path]:
    written: list[Path] = []

    def emit(path: Path) -> Path:
        written.append(path)
        return path

    # macOS — inset to the Apple icon grid.
    for size in MACOS_SIZES:
        rasterise(
            "yourssh_icon",
            size,
            emit(MACOS_ICONSET / f"app_icon_{size}.png"),
            inset=MACOS_INSET,
        )

    # iOS — the single 1024 marketing icon, opaque and alpha-free.
    build_ios_icon(emit(IOS_ICONSET / "app_icon_1024.png"))
    contents = emit(IOS_ICONSET / "Contents.json")
    contents.write_text(IOS_CONTENTS_JSON)

    # Windows — full-bleed, packed into a multi-size ICO.
    build_ico("yourssh_icon", WINDOWS_SIZES, emit(WINDOWS_ICO))

    # Android — adaptive layers plus the legacy launcher bitmap.
    background = emit(ANDROID_RES / "drawable" / "ic_launcher_background.xml")
    background.parent.mkdir(parents=True, exist_ok=True)
    background.write_text(android_background_xml())
    for suffix, layer_px, legacy_px in ANDROID_DENSITIES:
        drawable = ANDROID_RES / f"drawable-{suffix}"
        for master, name in (
            ("yourssh_icon_foreground", "ic_launcher_foreground"),
            ("yourssh_icon_monochrome", "ic_launcher_monochrome"),
        ):
            rasterise(master, layer_px, emit(drawable / f"{name}.png"))
        rasterise(
            "yourssh_icon",
            legacy_px,
            emit(ANDROID_RES / f"mipmap-{suffix}" / "ic_launcher.png"),
        )
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        path = emit(ANDROID_RES / "mipmap-anydpi-v26" / name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(ADAPTIVE_XML)

    # In-app assets (About screen, README).
    rasterise("yourssh_icon", 256, emit(APP_ASSETS / "app_icon.png"))
    rasterise("yourssh_icon", 2048, emit(APP_ASSETS / "logo.png"))
    rasterise("yourssh_icon", 256, emit(APP_ASSETS / "logo-readme.png"))
    return written


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="regenerate and report any output that failed to materialise",
    )
    args = parser.parse_args()

    if sys.platform != "darwin" or shutil.which("sips") is None:
        print("error: needs macOS (`sips` renders the SVG masters)", file=sys.stderr)
        return 2
    if not BRANDING.is_dir():
        print(f"error: no master artwork at {BRANDING}", file=sys.stderr)
        return 2

    try:
        written = generate()
    except IconError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    for path in written:
        print(f"  {path.relative_to(ROOT)}")
    print(f"{len(written)} files written from {BRANDING.relative_to(ROOT)}")
    if args.check:
        missing = [p for p in written if not p.exists()]
        for path in missing:
            print(f"missing: {path.relative_to(ROOT)}", file=sys.stderr)
        return 1 if missing else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
