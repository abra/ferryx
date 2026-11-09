/// The rewrite foliate-js's EPUB loader gives every style sheet, `<style>`
/// element and `style` attribute of a book before the browser reads it
/// (`replaceCSS` in `epub.js`): `-epub-` prefixes dropped, viewport units
/// fixed to the window, and every `px` turned into `em` (a sixteenth per
/// pixel), so publisher sizes scale with the reader's text size and
/// lengths with their element's font. The WebView reader read EPUBs this
/// way; MOBI and FB2 style sheets are read as they are. Pure Dart.
library;

/// [css] as `epub.js`'s `replaceCSS` leaves it, for a window
/// [windowWidth] × [windowHeight] CSS px. URLs are left as they are:
/// `epub.js` has replaced them with blob URLs by then.
String rewriteEpubCss(
  String css, {
  required double windowWidth,
  required double windowHeight,
}) {
  final out = StringBuffer();
  var start = 0;
  for (final url in _url.allMatches(css)) {
    out
      ..write(
        _rewrite(css.substring(start, url.start), windowWidth, windowHeight),
      )
      ..write(url[0]);
    start = url.end;
  }
  out.write(_rewrite(css.substring(start), windowWidth, windowHeight));
  return out.toString();
}

final _url = RegExp(
  r'''url\(\s*["']?[^'"\n]*?\s*["']?\s*\)|@import\s*["'][^"'\n]*?["']''',
  caseSensitive: false,
);
final _epubPrefix = RegExp(r'([{\s;])-epub-', caseSensitive: false);
final _vw = RegExp(r'(\d*\.?\d+)vw', caseSensitive: false);
final _vh = RegExp(r'(\d*\.?\d+)vh', caseSensitive: false);
final _px = RegExp(r'(\d*\.?\d+)px', caseSensitive: false);

String _rewrite(String text, double width, double height) => text
    .replaceAllMapped(_epubPrefix, (m) => m[1]!)
    .replaceAllMapped(
      _vw,
      (m) => '${_number(double.parse(m[1]!) * width / 100)}px',
    )
    .replaceAllMapped(
      _vh,
      (m) => '${_number(double.parse(m[1]!) * height / 100)}px',
    )
    .replaceAllMapped(_px, (m) => '${_number(double.parse(m[1]!) / 16)}em');

/// A number as JavaScript prints it: no `.0` on whole numbers.
String _number(double value) =>
    value == value.truncateToDouble() ? value.toInt().toString() : '$value';
