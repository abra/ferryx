#!/usr/bin/env python3
"""Reproduce the Ferryx icon proposals; platform assets are built separately."""

from pathlib import Path
import argparse
import html
import math

ROOT = Path(__file__).resolve().parent
TILE = "M24 82C24 43 43 24 82 24H174C213 24 232 43 232 82V174C232 213 213 232 174 232H82C43 232 24 213 24 174Z"


def svg(title, body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" '
            f'width="256" height="256" role="img" aria-labelledby="title">\n'
            f'<title id="title">{html.escape(title)}</title>\n'
            f'{defs}\n{body}\n</svg>\n')


def helm(version):
    # A single annular rim, eight round-ended spokes, and a solid hub.
    width, top, outer, inner, hub = (12, 40, 70, 54, 21)
    if version == 'v2':
        outer, hub = 68, 18
    # Bake rotations into coordinates so the material has one lighting
    # direction, rather than a different gradient on each rotated spoke.
    spokes = []
    half = width / 2
    for angle in range(0, 360, 45):
        radians = math.radians(angle)
        u = (math.sin(radians), -math.cos(radians))
        v = (math.cos(radians), math.sin(radians))
        def point(distance, side):
            return f'{128 + distance*u[0] + side*v[0]:.2f} {128 + distance*u[1] + side*v[1]:.2f}'
        spokes.append(f'M{point(0, -half)}L{point(128-top-half, -half)}'
                      f'A{half:g} {half:g} 0 0 1 {point(128-top-half, half)}L{point(0, half)}Z')
    spokes = f'<path d="{" ".join(spokes)}"/>'
    if version == 'v1':
        spokes = ''.join(
            f'<rect x="{128-width/2:g}" y="{top}" width="{width}" height="{128-top}" '
            f'rx="{width/2:g}" transform="rotate({angle} 128 128)"/>'
            for angle in range(0, 360, 45)
        )
    ring = (f'M{128-outer} 128a{outer} {outer} 0 1 0 {outer*2} 0'
            f'a{outer} {outer} 0 1 0 {-outer*2} 0Z'
            f'M{128-inner} 128a{inner} {inner} 0 1 0 {inner*2} 0'
            f'a{inner} {inner} 0 1 0 {-inner*2} 0Z')
    return f'{spokes}<path fill-rule="evenodd" d="{ring}"/><circle cx="128" cy="128" r="{hub}"/>'


def crossing(version):
    # Two piers exchange direction around an open diagonal channel.
    pier = 'M76 52H164Q176 52 176 64V88H100V116L136 152L112 176L64 128V64Q64 52 76 52Z'
    if version == 'v2':
        # The two piers remain separated even in the monochrome version.
        pier = 'M68 44H172Q188 44 188 60V76H92V108L124 140L100 164L52 116V60Q52 44 68 44Z'
    return f'<path d="{pier}"/><path d="{pier}" transform="rotate(180 128 128)"/>'


def course(version):
    # The F is drawn as one filled outline: two decks and a cut stem.
    if version == 'v1':
        return '<path d="M72 54H192L160 86H108V112H168L136 144H108V180L72 216Z"/>'
    return '<path d="M88 48H200L168 80H116V108H176L144 140H116V172L80 208V56Q80 48 88 48Z"/>'


CONCEPTS = [
    ('a-helm', 'A — Штурвал', helm, '#143A65', '#081A31', '#FFE9AE', '#D2A056'),
    ('b-crossing', 'B — Переправа', crossing, '#F1EEE7', '#DBE5DF', '#155A62', '#073F4B'),
    ('c-course', 'C — Курс', course, '#1C527F', '#092C4E', '#B9F4E7', '#63CDBB'),
]


def build(version):
    folder = ROOT / 'iterations' / version
    folder.mkdir(parents=True, exist_ok=True)
    for key, title, geometry, top, bottom, light, dark in CONCEPTS:
        mark = geometry(version)
        (folder / f'{key}-symbol.svg').write_text(svg(title, f'<g fill="#171D24">{mark}</g>'))
        light_axis = ('x1="0" y1="0" x2="0.8" y2="1"' if version == 'v1' else
                      'gradientUnits="userSpaceOnUse" x1="48" y1="36" x2="190" y2="216"')
        defs = (f'<defs><linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">'
                f'<stop stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>'
                f'<linearGradient id="mark" {light_axis}>'
                f'<stop stop-color="{light}"/><stop offset="1" stop-color="{dark}"/></linearGradient></defs>')
        body = (f'<path d="{TILE}" fill="url(#tile)"/>'
                f'<g fill="url(#mark)">{mark}</g>')
        (folder / f'{key}-icon.svg').write_text(svg(title, body, defs))
    print(folder)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version', choices=['v1', 'v2'])
    build(parser.parse_args().version)
