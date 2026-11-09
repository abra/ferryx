/// Which Flutter font families stand for the families a book's CSS
/// names. Pure Dart: families are names the host registered (in its
/// pubspec or with `FontLoader`).
library;

import 'package:meta/meta.dart';
import '../fonts/font_ink.dart';

@immutable
class BookFonts {
  const BookFonts({
    this.serif,
    this.sansSerif,
    this.monospace,
    this.systemUi,
    this.fallback = const [],
    this.bookFamilies = const {},
    this.ink = const {},
  });

  /// Families for the CSS generic families; null leaves the platform's.
  final String? serif;
  final String? sansSerif;
  final String? monospace;
  final String? systemUi;

  /// Tried after everything else, for glyphs the text fonts lack (the
  /// reader's symbol font).
  final List<String> fallback;

  /// The book's embedded fonts: a CSS family name, lowercased, to the
  /// family it was registered under.
  final Map<String, String> bookFamilies;

  /// How far a line of text inks above and below its baseline, by the
  /// family registered (`fontInkOf`): known for the fonts whose outlines
  /// were read, for `BookStyle.glyphLineBoxes`.
  final Map<String, FontInk> ink;

  /// These fonts with the book's [families] and their [bookInk].
  BookFonts withBookFamilies(
    Map<String, String> families, {
    Map<String, FontInk> bookInk = const {},
  }) => BookFonts(
    serif: serif,
    sansSerif: sansSerif,
    monospace: monospace,
    systemUi: systemUi,
    fallback: fallback,
    bookFamilies: families,
    ink: bookInk.isEmpty ? ink : {...ink, ...bookInk},
  );

  /// The family for a CSS generic, or null to leave it to the platform.
  String? generic(String name) => switch (name) {
    'serif' || 'ui-serif' => serif,
    'sans-serif' || 'ui-sans-serif' => sansSerif,
    'monospace' || 'ui-monospace' => monospace,
    'system-ui' => systemUi ?? sansSerif,
    _ => null,
  };

  static bool isGeneric(String name) => const {
    'serif',
    'sans-serif',
    'monospace',
    'cursive',
    'fantasy',
    'system-ui',
    'ui-serif',
    'ui-sans-serif',
    'ui-monospace',
    'math',
    'emoji',
  }.contains(name);

  /// The first family and the fallback chain for a CSS `font-family`
  /// list: embedded fonts by their registered name, generics mapped,
  /// other names passed through (the platform resolves installed
  /// families and skips unknown ones), then the serif default and
  /// [fallback].
  ({String? family, List<String> fallback}) resolve(List<String> families) {
    final chain = <String>[];
    void add(String? family) {
      if (family != null && family.isNotEmpty && !chain.contains(family)) {
        chain.add(family);
      }
    }

    for (final name in families) {
      final embedded = bookFamilies[name.toLowerCase()];
      if (embedded != null) {
        add(embedded);
      } else if (isGeneric(name)) {
        add(generic(name));
      } else {
        add(name);
      }
    }
    if (!families.any(isGeneric)) add(serif);
    fallback.forEach(add);
    return (
      family: chain.isEmpty ? null : chain.first,
      fallback: chain.length <= 1 ? const [] : chain.sublist(1),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookFonts &&
      other.serif == serif &&
      other.sansSerif == sansSerif &&
      other.monospace == monospace &&
      other.systemUi == systemUi &&
      _sameList(other.fallback, fallback) &&
      _sameMap(other.bookFamilies, bookFamilies) &&
      other.ink.length == ink.length &&
      other.ink.entries.every((e) => ink[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    serif,
    sansSerif,
    monospace,
    systemUi,
    Object.hashAll(fallback),
    Object.hashAllUnordered(
      bookFamilies.entries.map((e) => '${e.key}=${e.value}'),
    ),
    Object.hashAllUnordered(
      ink.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameMap(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}
