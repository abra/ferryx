#!/usr/bin/env python3
"""Generate the original DjVu test document with DjVuLibre's maintenance tools.

Run from the repository root with Python/Pillow and a built DjVuLibre 3.5.30:
  python3 packages/pagecraft/test/formats/djvu/generate_fixture.py \
    --tools .local/djvulibre-3.5.30/tools
Normal tests use the committed Dart bytes and need neither tool nor Python.
"""

import argparse
import base64
import json
from pathlib import Path
import subprocess
import struct
import tempfile
import textwrap

from PIL import Image, ImageDraw, ImageFont


TITLE = "Pagecraft DjVu fixture"
AUTHOR = "Readflex Tests"


def quoted(value):
    return json.dumps(value, ensure_ascii=False)


def dart_constant(name, data):
    encoded = "\n".join(f"  '{chunk}'" for chunk in
                        textwrap.wrap(base64.b64encode(data).decode("ascii"), 76))
    return f"const {name} =\n{encoded};\n"


def cyclic_bundle(data):
    """Keep DIRM offsets/sizes intact while creating a two-component cycle."""
    result = bytearray(data)
    offset = 0
    for target in (b"page-2.djvu", b"page-1.djvu"):
        offset = result.index(b"Sjbz", offset)
        length = struct.unpack_from(">I", result, offset + 4)[0]
        if length < len(target):
            raise ValueError("Fixture image chunk is too short for an include")
        result[offset:offset + 4] = b"INCL"
        # DjVu trims surrounding newlines from include IDs. Padding preserves
        # the bundle directory exactly without introducing an invalid path.
        result[offset + 8:offset + 8 + length] = (
            b"\n" * (length - len(target)) + target
        )
        offset += 8 + length
    return result


def draw_page(path, size, lines, font_path):
    image = Image.new("1", size, 1)
    draw = ImageDraw.Draw(image)
    draw.rectangle((24, 24, size[0] - 25, size[1] - 25), outline=0, width=3)
    font = ImageFont.truetype(str(font_path), size=26)
    structure = [f"(page 0 0 {size[0]} {size[1]}"]
    for y, text in lines:
        x = 50
        words = []
        for word in text.split():
            # The stored word rectangles use the same font metrics as the
            # bitmap, then convert top-left pixels to DjVu's bottom-left origin.
            left, top, right, bottom = draw.textbbox((x, y), word, font=font)
            draw.text((x, y), word, font=font, fill=0)
            words.append(
                f"(word {left} {size[1] - bottom} {right} "
                f"{size[1] - top} {quoted(word)})"
            )
            x += round(draw.textlength(word + " ", font=font))
        structure.append("  (line 40 0 " + str(size[0] - 40) + " "
                         + str(size[1]) + " " + " ".join(words) + ")")
    structure.append(")")
    if lines:
        draw.rectangle((80, size[1] // 2, size[0] - 80,
                        size[1] // 2 + 120), outline=0, width=5)
        draw.line((80, size[1] // 2, size[0] - 80,
                   size[1] // 2 + 120), fill=0, width=4)
    else:
        draw.rectangle((180, 360, 420, 540), fill=0)
    image.save(path)
    return "\n".join(structure) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tools", type=Path, required=True)
    args = parser.parse_args()
    tools = args.tools.resolve()
    here = Path(__file__).resolve().parent
    repository = here.parents[4]
    font = repository / "packages/component_library/fonts/OpenSans-Variable.ttf"

    def run(tool, *arguments):
        subprocess.run([str(tools / tool), *map(str, arguments)], check=True)

    with tempfile.TemporaryDirectory(prefix="pagecraft-djvu-fixture-") as temporary:
        directory = Path(temporary)
        pages = []
        specs = [
            ((600, 900), [(70, TITLE), (190, "Quiet café Привет reader"),
                          (250, "Original test document")]),
            ((900, 600), [(70, "Second chapter"), (180, "The story continues"),
                          (240, "A quiet afternoon")]),
            ((600, 900), []),
        ]
        for index, (size, lines) in enumerate(specs, 1):
            bitmap = directory / f"page-{index}.pbm"
            page = directory / f"page-{index}.djvu"
            text = draw_page(bitmap, size, lines, font)
            run("cjb2", "-lossless", "-dpi", "300", bitmap, page)
            if lines:
                text_path = directory / f"page-{index}.txt"
                text_path.write_text(text, encoding="utf-8")
                run("djvused", page, "-e", f"select 1; set-txt {text_path}", "-s")
            pages.append(page)

        book = directory / "fixture.djvu"
        run("djvm", "-c", book, *pages)
        outline = directory / "outline.txt"
        outline.write_text(
            '(bookmarks ("First chapter" "#1" '
            '("Second page" "#2")) ("Image only" "#3"))\n', encoding="utf-8",
        )
        metadata = directory / "metadata.txt"
        metadata.write_text(
            f"title\t{quoted(TITLE)}\nauthor\t{quoted(AUTHOR)}\n", encoding="utf-8",
        )
        run("djvused", book, "-e",
            f"select 1; set-meta {metadata}; set-outline {outline}", "-s")
        data = book.read_bytes()
        indirect = directory / "indirect"
        indirect.mkdir()
        run("djvmcvt", "-i", book, indirect, "index.djvu")
        indirect_data = (indirect / "index.djvu").read_bytes()
        single_data = pages[0].read_bytes()
        reference = b"missing-component.djvu"
        include = b"INCL" + struct.pack(">I", len(reference)) + reference
        include += b"\0" * (len(reference) % 2)
        external_data = bytearray(single_data + include)
        struct.pack_into(">I", external_data, 8, len(external_data) - 12)
        (here / "djvu_fixture.dart").write_text(
            "// Generated by generate_fixture.py from original text and artwork.\n"
            "// Do not edit bytes by hand; this fixture contains no third-party book.\n"
            "import 'dart:convert';\nimport 'dart:typed_data';\n\n"
            "Uint8List djvuFixtureBytes() => base64Decode(_fixture);\n\n"
            "Uint8List djvuIndirectFixtureBytes() => base64Decode(_indirect);\n\n"
            "Uint8List djvuExternalIncludeFixtureBytes() => base64Decode(_external);\n\n"
            "Uint8List djvuCyclicBundleFixtureBytes() => base64Decode(_cyclic);\n\n"
            + dart_constant("_fixture", data) + "\n"
            + dart_constant("_indirect", indirect_data) + "\n"
            + dart_constant("_external", external_data) + "\n"
            + dart_constant("_cyclic", cyclic_bundle(data)), encoding="utf-8",
        )
        print(json.dumps({"bytes": len(data), "pages": len(pages),
                          "output": str(here / "djvu_fixture.dart")}))


if __name__ == "__main__":
    main()
