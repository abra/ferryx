#!/usr/bin/env python3
"""Build an original raster PDF with an unembedded Cyrillic OCR text layer.

Regeneration needs Pillow; normal tests read the committed PDF. The image uses
the repository's Open Sans font, while OCR glyph names deliberately exercise
PDFium's missing-font tight-box fallback.
"""

from io import BytesIO
from pathlib import Path
import base64
import hashlib
import zlib

from PIL import Image, ImageDraw, ImageFont


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
LINES = ("Проверка границ", "Точный выбор слова")
WIDTH, HEIGHT, SCALE = 240, 144, 3
FONT_SIZE, ADVANCE = 12, 8
BASELINES = (100, 76)


def build():
    font = ImageFont.truetype(
        str(ROOT / "packages/component_library/fonts/OpenSans-Variable.ttf"),
        FONT_SIZE * SCALE,
    )
    image = Image.new("RGB", (WIDTH * SCALE, HEIGHT * SCALE), "white")
    draw = ImageDraw.Draw(image)
    characters = sorted(set("".join(LINES)))
    codes = {character: index for index, character in enumerate(characters)}
    for line, baseline in zip(LINES, BASELINES):
        for index, character in enumerate(line):
            draw.text(
                ((24 + index * ADVANCE) * SCALE, (HEIGHT - baseline) * SCALE),
                character,
                font=font,
                fill="black",
                anchor="ls",
            )
    mapping = "\n".join(
        f"<{codes[character]:02X}> <{ord(character):04X}>"
        for character in characters
    )
    cmap = (
        "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n"
        "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n"
        "/CMapName /OriginalCyrillic def\n/CMapType 2 def\n"
        "1 begincodespacerange\n<00> <FF>\nendcodespacerange\n"
        f"{len(characters)} beginbfchar\n{mapping}\nendbfchar\n"
        "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n"
    ).encode("ascii")
    encoding = " ".join(
        "/space" if character == " " else f"/uni{ord(character):04X}"
        for character in characters
    )
    text = "\n".join(
        f"BT /F0 {FONT_SIZE} Tf 1 0 0 1 24 {baseline} Tm "
        f"<{''.join(f'{codes[character]:02X}' for character in line)}> Tj ET"
        for line, baseline in zip(LINES, BASELINES)
    )
    content = (
        f"{text}\nq {WIDTH} 0 0 {HEIGHT} 0 0 cm /Scan Do Q\n"
    ).encode("ascii")

    def stream(data, attributes=""):
        return (
            f"<< /Length {len(data)} {attributes} >>\nstream\n".encode("ascii")
            + data
            + b"\nendstream"
        )

    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R 9 0 R] /Count 2 >>",
        (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {WIDTH} {HEIGHT}] "
            "/Resources << /Font << /F0 4 0 R >> /XObject << /Scan 8 0 R >> >> "
            "/Contents 7 0 R >>"
        ).encode("ascii"),
        (
            "<< /Type /Font /Subtype /TrueType /BaseFont /TimesNewRomanPSMT "
            f"/FirstChar 0 /LastChar {len(characters) - 1} "
            f"/Widths [{' '.join(['667'] * len(characters))}] "
            f"/Encoding << /Type /Encoding /BaseEncoding /WinAnsiEncoding "
            f"/Differences [0 {encoding}] >> "
            "/FontDescriptor 5 0 R /ToUnicode 6 0 R >>"
        ).encode("ascii"),
        b"<< /Type /FontDescriptor /FontName /TimesNewRomanPSMT /Flags 34 "
        b"/FontBBox [-200 -200 1200 900] /ItalicAngle 0 "
        b"/Ascent 800 /Descent -200 /CapHeight 700 /StemV 80 >>",
        stream(cmap),
        stream(content),
        stream(
            zlib.compress(image.tobytes()),
            f"/Type /XObject /Subtype /Image /Width {image.width} "
            f"/Height {image.height} /ColorSpace /DeviceRGB "
            "/BitsPerComponent 8 /Filter /FlateDecode",
        ),
        (
            f"<< /Type /Page /Parent 2 0 R "
            f"/MediaBox [0 0 {WIDTH + 40} {HEIGHT + 40}] "
            f"/CropBox [20 20 {WIDTH + 20} {HEIGHT + 20}] /Rotate 90 "
            "/Resources << /Font << /F0 4 0 R >> /XObject << /Scan 8 0 R >> >> "
            "/Contents 10 0 R >>"
        ).encode("ascii"),
        stream(b"q 1 0 0 1 20 20 cm\n" + content + b"Q\n"),
    ]
    output = BytesIO()
    output.write(b"%PDF-1.4\n% Original Pagecraft test fixture\n")
    offsets = []
    for index, obj in enumerate(objects, 1):
        offsets.append(output.tell())
        output.write(f"{index} 0 obj\n".encode("ascii") + obj + b"\nendobj\n")
    xref = output.tell()
    output.write(f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode("ascii"))
    for offset in offsets:
        output.write(f"{offset:010d} 00000 n \n".encode("ascii"))
    output.write(
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
        f"startxref\n{xref}\n%%EOF\n".encode("ascii")
    )
    return output.getvalue()


if __name__ == "__main__":
    destination = HERE / "unembedded_cyrillic.pdf"
    data = build()
    destination.write_bytes(data)
    encoded = base64.b64encode(data).decode("ascii")
    literals = "\n".join(
        f"    '{encoded[index:index + 72]}'"
        for index in range(0, len(encoded), 72)
    )
    (HERE / "unembedded_cyrillic_fixture.dart").write_text(
        "// Generated by generate_unembedded_cyrillic.py. Original test content.\n"
        "import 'dart:convert';\nimport 'dart:typed_data';\n\n"
        "const unembeddedCyrillicFixtureSha256 =\n"
        f"    '{hashlib.sha256(data).hexdigest()}';\n\n"
        "Uint8List unembeddedCyrillicFixtureBytes() => base64Decode(_bytes);\n\n"
        f"const _bytes =\n{literals};\n",
        encoding="utf-8",
    )
    print(f"{destination.name}: {destination.stat().st_size} bytes")
