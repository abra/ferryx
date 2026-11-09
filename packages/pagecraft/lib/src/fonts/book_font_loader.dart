import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;

import '../text_book/text_book_source.dart';
import 'book_font_face.dart';
import 'font_data.dart';
import 'font_ink.dart';

/// Registers font [fonts] with the engine as family [family].
typedef FontRegistrar =
    Future<void> Function(String family, List<Uint8List> fonts);

/// The engine's font families, which stay registered until the process
/// ends (Flutter cannot remove one): each family is registered once, so
/// opening a book again, or another book with the same fonts, costs
/// nothing more.
class EngineFontRegistry {
  EngineFontRegistry._();

  static final instance = EngineFontRegistry._();

  final _families = <String>{};

  Future<void> register(String family, List<Uint8List> fonts) async {
    if (!_families.add(family)) return;
    final loader = FontLoader(family);
    for (final font in fonts) {
      loader.addFont(Future.value(ByteData.sublistView(font)));
    }
    await loader.load();
  }
}

/// A book's embedded fonts: reads the faces its sections declare from the
/// book (de-obfuscated, KF8 font records decoded), registers each CSS
/// family's files as one engine family named after their content, and
/// keeps the CSS family to engine family map `BookFonts.bookFamilies`
/// wants. A family whose files cannot be read is left to the fallback
/// chain, as the browser leaves it.
class BookFontLoader {
  BookFontLoader(this.source, {FontRegistrar? register})
    : _register = register ?? EngineFontRegistry.instance.register;

  final TextBookSource source;
  final FontRegistrar _register;
  final _families = <String, String>{};
  final _ink = <String, FontInk>{};
  final _tried = <String>{};

  /// CSS family names, lowercased, to registered families.
  Map<String, String> get families => UnmodifiableMapView(_families);

  /// Registered families to their ink (`fontInkOf` of their first face).
  Map<String, FontInk> get ink => UnmodifiableMapView(_ink);

  /// Loads the families of [faces] not tried yet; true when one was
  /// added, so text styled before needs styling again.
  Future<bool> load(Iterable<BookFontFace> faces) async {
    final byFamily = <String, List<BookFontFace>>{};
    for (final face in faces) {
      final family = face.family.toLowerCase();
      if (_tried.contains(family)) continue;
      byFamily.putIfAbsent(family, () => []).add(face);
    }
    var added = false;
    for (final MapEntry(key: family, value: list) in byFamily.entries) {
      _tried.add(family);
      final fonts = <Uint8List>[];
      for (final face in list) {
        final font = await _read(face);
        if (font != null && !fonts.any((f) => _sameBytes(f, font))) {
          fonts.add(font);
        }
      }
      if (fonts.isEmpty) continue;
      final name = 'pagecraft-${_hashOf(fonts).toRadixString(16)}';
      await _register(name, fonts);
      _families[family] = name;
      if (fontInkOf(fonts.first) case final ink?) _ink[name] = ink;
      added = true;
    }
    return added;
  }

  /// The face's first source that is a font the engine can load.
  Future<Uint8List?> _read(BookFontFace face) async {
    for (final src in face.sources) {
      final bytes = await source.readImage(source.imageKey(face.base, src));
      final font = bytes == null ? null : sfntOf(bytes);
      if (font != null) return font;
    }
    return null;
  }
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// FNV-1a over the fonts' bytes, 64-bit.
int _hashOf(List<Uint8List> fonts) {
  var hash = 0xcbf29ce484222325;
  for (final font in fonts) {
    for (final byte in font) {
      hash = (hash ^ byte) * 0x100000001b3;
    }
    hash = (hash ^ 0xFF) * 0x100000001b3;
  }
  return hash & 0x7FFFFFFFFFFFFFFF;
}
