#!/usr/bin/env python3
"""Builds every platform's app icon from the SVG masters in this folder.

    python3 brand/build_icons.py      (or: make icons)

Needs `rsvg-convert` (librsvg: `brew install librsvg`, `apt install
librsvg2-bin`) and nothing else: PNGs come from it, the Windows .ico is
packed here with the standard library.

Each platform gets its own drawing, after its own rules:
  macOS      ferryx-macos.svg         the tile with depth, 1024 grid / 824 body
             ferryx-macos-small.svg   16 and 32 px: one bullet, one line
  Windows    ferryx-windows.svg       Fluent: the object without a plate
             ferryx-windows-small.svg 16-32 px
  Linux      ferryx-gnome.svg         GNOME HIG: front-facing, palette, lips
             ferryx-symbolic.svg      one colour, recoloured by the desktop
"""
import os
import struct
import subprocess
import sys
import tempfile

BRAND = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(BRAND)
APP_ID = "dev.ferryx.ferryx"

MACOS_SET = os.path.join(ROOT, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
WINDOWS_ICO = os.path.join(ROOT, "windows/runner/resources/app_icon.ico")
LINUX_ICONS = os.path.join(ROOT, "linux/packaging/icons/hicolor")


def png(svg: str, size: int, out: str) -> None:
    """Renders [svg] (a master in this folder) to a [size]² PNG at [out]."""
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), "-o", out,
         os.path.join(BRAND, svg)],
        check=True,
    )


def macos() -> None:
    # The file names Contents.json lists; ≤32 px use the small drawing.
    for size in (16, 32, 64, 128, 256, 512, 1024):
        svg = "ferryx-macos-small.svg" if size <= 32 else "ferryx-macos.svg"
        png(svg, size, os.path.join(MACOS_SET, f"app_icon_{size}.png"))


def windows() -> None:
    """A multi-size .ico of PNG entries (Windows Vista and later read them)."""
    sizes = (16, 20, 24, 32, 40, 48, 64, 96, 128, 256)
    with tempfile.TemporaryDirectory() as tmp:
        images = []
        for size in sizes:
            svg = "ferryx-windows-small.svg" if size <= 32 else "ferryx-windows.svg"
            out = os.path.join(tmp, f"{size}.png")
            png(svg, size, out)
            with open(out, "rb") as fh:
                images.append((size, fh.read()))
    header = struct.pack("<HHH", 0, 1, len(images))
    offset = len(header) + 16 * len(images)
    entries, data = b"", b""
    for size, blob in images:
        side = 0 if size >= 256 else size  # 0 means 256 in an ICO entry
        entries += struct.pack("<BBBBHHII", side, side, 0, 0, 1, 32,
                               len(blob), offset + len(data))
        data += blob
    with open(WINDOWS_ICO, "wb") as fh:
        fh.write(header + entries + data)


def linux() -> None:
    """The hicolor theme a package installs, plus the scalable masters."""
    for size in (16, 24, 32, 48, 64, 128, 256, 512):
        png("ferryx-gnome.svg", size,
            os.path.join(LINUX_ICONS, f"{size}x{size}/apps/{APP_ID}.png"))
    for svg, name in (("ferryx-gnome.svg", f"{APP_ID}.svg"),
                      ("ferryx-symbolic.svg", f"{APP_ID}-symbolic.svg")):
        folder = "scalable" if "symbolic" not in name else "symbolic"
        dest = os.path.join(LINUX_ICONS, f"{folder}/apps/{name}")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(os.path.join(BRAND, svg), "rb") as src, open(dest, "wb") as out:
            out.write(src.read())


def readme() -> None:
    """The picture at the top of the README."""
    png("ferryx-macos.svg", 256, os.path.join(BRAND, "ferryx-256.png"))


if __name__ == "__main__":
    try:
        macos()
        windows()
        linux()
        readme()
    except FileNotFoundError:
        sys.exit("rsvg-convert not found: install librsvg (see the header)")
    print("icons written: macOS asset catalog, Windows .ico, Linux hicolor")
