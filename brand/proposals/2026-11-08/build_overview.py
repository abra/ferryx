#!/usr/bin/env python3
"""Compose the proposal sheet from the SVG concepts, without raster edits."""

from pathlib import Path
import html
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
BRAND = ROOT.parents[1]
ET.register_namespace('', 'http://www.w3.org/2000/svg')
ET.register_namespace('xlink', 'http://www.w3.org/1999/xlink')


def artwork(path, key, x, y, size, white=False):
    root = ET.parse(path).getroot()
    ids = {e.get('id'): f'{key}-{e.get("id")}' for e in root.iter() if e.get('id')}
    for element in root.iter():
        for name, value in list(element.attrib.items()):
            if name == 'id' or name == 'aria-labelledby':
                value = ids.get(value, value)
            for old, new in ids.items():
                value = value.replace(f'url(#{old})', f'url(#{new})')
                if name.endswith('href') and value == f'#{old}':
                    value = f'#{new}'
            if white and name in ('fill', 'stroke') and value.startswith('#'):
                value = '#ffffff'
            element.set(name, value)
    root.set('x', str(x))
    root.set('y', str(y))
    root.set('width', str(size))
    root.set('height', str(size))
    return ET.tostring(root, encoding='unicode')


def text(x, y, content, size=18, color='#172B35', weight=400, anchor='start'):
    return (f'<text x="{x}" y="{y}" font-family="Arial,Helvetica,sans-serif" '
            f'font-size="{size}" font-weight="{weight}" fill="{color}" '
            f'text-anchor="{anchor}">{html.escape(content)}</text>')


def rect(x, y, width, height, fill, radius=0, stroke='none'):
    return (f'<rect x="{x}" y="{y}" width="{width}" height="{height}" '
            f'rx="{radius}" fill="{fill}" stroke="{stroke}"/>')


def build():
    version = ROOT / 'iterations/v2'
    for key in ('a-helm', 'b-crossing', 'c-course'):
        shutil.copyfile(version / f'{key}-icon.svg', ROOT / f'{key}.svg')
        shutil.copyfile(version / f'{key}-symbol.svg', ROOT / f'{key}-symbol.svg')
    entries = [
        ('ИСХОДНАЯ ИКОНКА', 'Сейчас', BRAND / 'ferryx-macos.svg', BRAND / 'ferryx-symbolic.svg',
         'Морской характер Ferryx.', 'Отправная точка сравнения.'),
        ('ВАРИАНТ A', 'Штурвал', ROOT / 'a-helm.svg', ROOT / 'a-helm-symbol.svg',
         'Один обод, светлая латунь.', 'Знакомый образ, чище силуэт.'),
        ('ВАРИАНТ B', 'Переправа', ROOT / 'b-crossing.svg', ROOT / 'b-crossing-symbol.svg',
         'Две стороны и проход между ними.', 'Более абстрактное направление.'),
        ('ВАРИАНТ C', 'Курс', ROOT / 'c-course.svg', ROOT / 'c-course-symbol.svg',
         'Буква F с направленными срезами.', 'Лаконичный знак для малых размеров.'),
    ]
    parts = [rect(0, 0, 1760, 1090, '#F3F3EF')]
    parts += [text(56, 65, 'Ferryx', 25, weight=700),
              text(56, 111, 'Три направления иконки приложения', 34, weight=700),
              text(1704, 65, 'КОНЦЕПЦИИ  /  08.11.2026', 13, '#64747B', anchor='end'),
              text(1704, 105, 'Сравнение в одинаковом масштабе', 16, '#64747B', anchor='end')]
    for index, (label, name, icon, symbol, note1, note2) in enumerate(entries):
        x = 56 + index * 418
        parts.append(rect(x, 157, 394, 849, '#FFFFFF', 22, '#D8DEDA' if index != 1 else '#8AABAA'))
        parts.append(text(x+25, 193, label, 12, '#64747B', 700))
        parts.append(text(x+25, 233, name, 27, weight=700))
        parts.append(artwork(icon, f'hero{index}', x+49, 266, 296))
        parts.append(text(x+25, 599, note1, 17))
        parts.append(text(x+25, 626, note2, 17, '#64747B'))
        parts.append(text(x+25, 676, 'В СПИСКЕ ПРИЛОЖЕНИЙ', 11, '#64747B', 700))
        for size, offset in [(64, 57), (32, 173), (16, 277)]:
            parts.append(artwork(icon, f'icon{index}-{size}', x+offset, 699+64-size, size))
            parts.append(text(x+offset+size/2, 788, f'{size} px', 12, '#64747B', anchor='middle'))
        parts.append(text(x+25, 830, 'СИЛУЭТ НА СВЕТЛОМ И ТЁМНОМ ФОНЕ', 11, '#64747B', 700))
        parts.append(rect(x+25, 848, 165, 83, '#F4F4F0', 10))
        parts.append(rect(x+204, 848, 165, 83, '#142C3A', 10))
        parts.append(artwork(symbol, f'black{index}', x+67, 850, 80))
        parts.append(artwork(symbol, f'white{index}', x+247, 850, 80, white=True))
        if index == 1:
            parts.append(rect(x+25, 955, 344, 29, '#E6F0E9', 8))
            parts.append(text(x+197, 974, 'Рекомендую для обновления Ferryx', 13, '#275B4B', 700, 'middle'))
        elif index == 2:
            parts.append(text(x+25, 974, 'Смена образа: штурвал → движение', 13, '#64747B'))
        elif index == 3:
            parts.append(text(x+25, 974, 'Смена образа: штурвал → буква F', 13, '#64747B'))
    parts.append(text(56, 1053, 'A сохраняет преемственность. B и C показывают два варианта более смелого обновления.', 17, '#64747B'))
    output = ('<svg xmlns="http://www.w3.org/2000/svg" width="1760" height="1090" '
              'viewBox="0 0 1760 1090"><title>Ferryx — варианты иконки</title>' + ''.join(parts) + '</svg>')
    (ROOT / 'icon-comparison.svg').write_text(output)
    print(ROOT / 'icon-comparison.svg')


if __name__ == '__main__':
    build()
