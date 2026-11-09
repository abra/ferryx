import '../css/css_syntax.dart';
import '../css/stylesheet_loader.dart';

/// An embedded font a section's style sheets declare (`@font-face`): the
/// CSS [family], and its `url()` [sources] as written, which resolve
/// against [base] (the sheet's href, or the document's for a `<style>`).
class BookFontFace {
  const BookFontFace({
    required this.family,
    required this.base,
    required this.sources,
    this.weight,
    this.style,
  });

  final String family;
  final String base;
  final List<String> sources;
  final String? weight;
  final String? style;

  @override
  bool operator ==(Object other) =>
      other is BookFontFace &&
      other.family == family &&
      other.base == base &&
      _same(other.sources, sources) &&
      other.weight == weight &&
      other.style == style;

  @override
  int get hashCode =>
      Object.hash(family, base, Object.hashAll(sources), weight, style);

  @override
  String toString() => 'BookFontFace($family, $sources from $base)';
}

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The `@font-face` rules of [sheets], whose URLs resolve against
/// [bases] (one per sheet), with a source each.
List<BookFontFace> bookFontFacesOf(
  List<CssStyleSheet> sheets,
  List<String> bases,
) => [
  for (var i = 0; i < sheets.length; i++)
    for (final face in cssFontFacesOf(sheets[i]))
      if (face.sources.isNotEmpty)
        BookFontFace(
          family: face.family,
          base: bases[i],
          sources: face.sources,
          weight: face.weight,
          style: face.style,
        ),
];
