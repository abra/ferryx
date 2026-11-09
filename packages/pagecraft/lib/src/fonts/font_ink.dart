/// How far a font's ink reaches above and below the baseline in a line
/// of text, read from its TrueType outlines: what WebKit's line boxes
/// hold under `-webkit-line-box-contain: glyphs` and Flutter's text API
/// does not tell. Pure Dart.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

/// The ink of a line of text, per em: the tallest ascender or capital
/// above the baseline and the deepest descender below it, and, read from
/// a font, each character's own (Latin, Greek, Cyrillic, punctuation):
/// WebKit holds the glyphs a line has, not the font's tallest.
@immutable
class FontInk {
  const FontInk({required this.ascent, required this.descent}) : _glyphs = null;

  const FontInk._(this.ascent, this.descent, this._glyphs);

  final double ascent;
  final double descent;
  final _GlyphExtents? _glyphs;

  /// The ink of text `[start, end)` of [text], per em: what its glyphs
  /// reach above and below the baseline; [ascent] and [descent] for a
  /// character the font's table does not hold. Text without ink (spaces)
  /// gives zero.
  ({double ascent, double descent}) extentOf(
    String text, [
    int start = 0,
    int? end,
  ]) {
    final glyphs = _glyphs;
    if (glyphs == null) return (ascent: ascent, descent: descent);
    var top = 0.0;
    var bottom = 0.0;
    for (var i = start; i < (end ?? text.length); i++) {
      final extent = glyphs.of(text.codeUnitAt(i));
      if (extent == null) return (ascent: ascent, descent: descent);
      if (extent.top > top) top = extent.top;
      if (extent.bottom > bottom) bottom = extent.bottom;
      if (top >= ascent && bottom >= descent) break;
    }
    return (ascent: top, descent: bottom);
  }

  @override
  bool operator ==(Object other) =>
      other is FontInk &&
      other.ascent == ascent &&
      other.descent == descent &&
      identical(other._glyphs, _glyphs);

  @override
  int get hashCode => Object.hash(ascent, descent, _glyphs);

  @override
  String toString() => 'FontInk(+$ascent, -$descent)';
}

/// Glyph tops and bottoms in font units by UTF-16 code unit, for the
/// [_ranges]; [_none] where the font has no glyph.
class _GlyphExtents {
  _GlyphExtents(this.unitsPerEm, this._tops, this._bottoms);

  static const _ranges = [(0x20, 0x58F), (0x2000, 0x20CF)];
  static const _none = -0x8000;

  static int get length => _ranges.fold(0, (n, r) => n + r.$2 - r.$1 + 1);

  /// Index of [unit] in the tables, or -1.
  static int indexOf(int unit) {
    var offset = 0;
    for (final (first, last) in _ranges) {
      if (unit < first) return -1;
      if (unit <= last) return offset + unit - first;
      offset += last - first + 1;
    }
    return -1;
  }

  final int unitsPerEm;
  final Int16List _tops;
  final Int16List _bottoms;

  /// [unit]'s ink per em above and below the baseline (never negative),
  /// or null for a character the table does not hold.
  ({double top, double bottom})? of(int unit) {
    // Controls, spaces and joiners draw nothing.
    if (unit < 0x21 || unit == 0xA0 || unit == 0xAD || unit == 0x2060) {
      return (top: 0, bottom: 0);
    }
    final i = indexOf(unit);
    if (i < 0 || _tops[i] == _none) return null;
    return (
      top: _tops[i] > 0 ? _tops[i] / unitsPerEm : 0,
      bottom: _bottoms[i] < 0 ? -_bottoms[i] / unitsPerEm : 0,
    );
  }
}

/// Letters that reach a line's top and bottom in Latin and Cyrillic
/// text.
const _ascenders = 'bdfhklABDEFHKLTбБВ';
const _descenders = 'gjpqyру';

/// The ink of [font] (a TrueType `sfnt`, or a collection's first font)
/// from its glyphs' boxes, or null for outlines it does not read (CFF)
/// or a font without the letters.
FontInk? fontInkOf(Uint8List font) {
  try {
    return _FontTables(ByteData.sublistView(font)).ink();
  } on RangeError {
    return null;
  } on FormatException {
    return null;
  }
}

class _FontTables {
  _FontTables(ByteData data) : _data = data {
    var offset = 0;
    // A collection: its first font.
    if (data.getUint32(0) == 0x74746366) offset = data.getUint32(12);
    final count = data.getUint16(offset + 4);
    for (var i = 0; i < count; i++) {
      final entry = offset + 12 + 16 * i;
      _tables[data.getUint32(entry)] = (
        data.getUint32(entry + 8),
        data.getUint32(entry + 12),
      );
    }
  }

  final ByteData _data;
  final _tables = <int, (int, int)>{};

  static const _cmap = 0x636D6170;
  static const _head = 0x68656164;
  static const _loca = 0x6C6F6361;
  static const _glyf = 0x676C7966;

  FontInk? ink() {
    final head = _tables[_head];
    final loca = _tables[_loca];
    final glyf = _tables[_glyf];
    final cmap = _tables[_cmap];
    if (head == null || loca == null || glyf == null || cmap == null) {
      return null;
    }
    final unitsPerEm = _data.getUint16(head.$1 + 18);
    final longOffsets = _data.getInt16(head.$1 + 50) == 1;
    final glyphs = _glyphIds(cmap.$1);
    if (glyphs == null || unitsPerEm == 0) return null;
    ({int yMin, int yMax})? box(int rune, {int? id}) {
      id ??= glyphs(rune);
      if (id == null || id == 0) return null;
      final start = longOffsets
          ? _data.getUint32(loca.$1 + id * 4)
          : _data.getUint16(loca.$1 + id * 2) * 2;
      final end = longOffsets
          ? _data.getUint32(loca.$1 + id * 4 + 4)
          : _data.getUint16(loca.$1 + id * 2 + 2) * 2;
      if (end <= start) return null;
      final at = glyf.$1 + start;
      return (yMin: _data.getInt16(at + 4), yMax: _data.getInt16(at + 8));
    }

    int? top;
    for (final rune in _ascenders.runes) {
      final b = box(rune);
      if (b != null && (top == null || b.yMax > top)) top = b.yMax;
    }
    int? bottom;
    for (final rune in _descenders.runes) {
      final b = box(rune);
      if (b != null && (bottom == null || b.yMin < bottom)) bottom = b.yMin;
    }
    if (top == null || bottom == null) return null;
    final tops = Int16List(_GlyphExtents.length)
      ..fillRange(0, _GlyphExtents.length, _GlyphExtents._none);
    final bottoms = Int16List(_GlyphExtents.length);
    for (final (first, last) in _GlyphExtents._ranges) {
      for (var unit = first; unit <= last; unit++) {
        final id = glyphs(unit);
        if (id == null || id == 0) continue;
        final i = _GlyphExtents.indexOf(unit);
        // A glyph without outlines (a space) has no ink.
        final b = box(unit, id: id) ?? (yMin: 0, yMax: 0);
        tops[i] = b.yMax;
        bottoms[i] = b.yMin;
      }
    }
    return FontInk._(
      top / unitsPerEm,
      bottom < 0 ? -bottom / unitsPerEm : 0,
      _GlyphExtents(unitsPerEm, tops, bottoms),
    );
  }

  /// A lookup of glyph ids by code point, from the Unicode `cmap`
  /// subtable (format 12, else 4).
  int? Function(int)? _glyphIds(int cmap) {
    final count = _data.getUint16(cmap + 2);
    int? format4;
    int? format12;
    for (var i = 0; i < count; i++) {
      final record = cmap + 4 + 8 * i;
      final platform = _data.getUint16(record);
      final encoding = _data.getUint16(record + 2);
      final subtable = cmap + _data.getUint32(record + 4);
      final format = _data.getUint16(subtable);
      final unicode =
          platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
      if (!unicode) continue;
      if (format == 12) format12 ??= subtable;
      if (format == 4) format4 ??= subtable;
    }
    if (format12 != null) {
      final table = format12;
      final groups = _data.getUint32(table + 12);
      return (rune) {
        for (var g = 0; g < groups; g++) {
          final at = table + 16 + 12 * g;
          final first = _data.getUint32(at);
          final last = _data.getUint32(at + 4);
          if (rune >= first && rune <= last) {
            return _data.getUint32(at + 8) + rune - first;
          }
        }
        return null;
      };
    }
    if (format4 != null) {
      final table = format4;
      final segments = _data.getUint16(table + 6) ~/ 2;
      final ends = table + 14;
      final starts = ends + segments * 2 + 2;
      final deltas = starts + segments * 2;
      final ranges = deltas + segments * 2;
      return (rune) {
        if (rune > 0xFFFF) return null;
        for (var s = 0; s < segments; s++) {
          if (rune > _data.getUint16(ends + s * 2)) continue;
          final start = _data.getUint16(starts + s * 2);
          if (rune < start) return null;
          final delta = _data.getInt16(deltas + s * 2);
          final range = _data.getUint16(ranges + s * 2);
          if (range == 0) return (rune + delta) & 0xFFFF;
          final at = ranges + s * 2 + range + (rune - start) * 2;
          final id = _data.getUint16(at);
          return id == 0 ? null : (id + delta) & 0xFFFF;
        }
        return null;
      };
    }
    return null;
  }
}
