/// Whitespace as the HTML spec counts it, for text read out of markup.
library;

/// Strips and collapses ASCII whitespace (`normalizeWhitespace`), as the
/// HTML spec defines it; null and empty come back empty.
String normalizeWhitespace(String? text) {
  if (text == null || text.isEmpty) return '';
  return text
      .replaceAll(_asciiWhitespace, ' ')
      .replaceFirst(RegExp(r'^ '), '')
      .replaceFirst(RegExp(r' $'), '');
}

final _asciiWhitespace = RegExp('[\t\n\f\r ]+');
