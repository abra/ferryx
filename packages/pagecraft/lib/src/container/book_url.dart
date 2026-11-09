/// Paths inside a book's container, resolved the way `epub.js` resolves
/// them: a manifest href is relative to the package document, a link or
/// a style sheet relative to the document that names it, and the result
/// is a plain container path (no scheme, no query, percent-escapes
/// decoded). Every format's sections resolve their links and sheets this
/// way.
library;

/// Resolves [url] against [relativeTo], a container path (`resolveURL`).
///
/// An absolute URL (with a scheme) is returned resolved as a URL. Calibre
/// percent-encodes `,` and `:` that are expected raw, so those are put
/// back first; `OEBPS:` is a known false scheme in old files.
String resolveBookUrl(String url, String relativeTo) {
  final fixed = url
      .replaceAll(RegExp('%2c', caseSensitive: false), ',')
      .replaceAll(RegExp('%3a', caseSensitive: false), ':');
  try {
    if (relativeTo.contains(':') && !relativeTo.startsWith('OEBPS')) {
      return Uri.parse(relativeTo).resolve(fixed).toString();
    }
    // The base must be a valid URL: use one and strip it again.
    const root = 'https://invalid.invalid/';
    final resolved = Uri.parse(root + relativeTo).resolve(fixed);
    // Drop the query (`obj.search = ''`), keep the fragment as written.
    final withoutQuery = resolved.toString().replaceFirst(
      RegExp(r'\?[^#]*'),
      '',
    );
    return decodeBookUri(withoutQuery.replaceFirst(root, ''));
  } on FormatException {
    return url;
  }
}

/// Percent-decodes [text] the way JavaScript's `decodeURI` does: every
/// escape except the reserved characters `;/?:@&=+\$,#`, which stay
/// encoded. Manifest paths are compared after this decoding, so a link
/// written `ch%2C1.html` does not find `ch,1.html` (`epub.js` parity).
String decodeBookUri(String text) {
  if (!text.contains('%')) return text;
  final out = StringBuffer();
  final bytes = <int>[];
  void flush() {
    if (bytes.isEmpty) return;
    out.write(
      String.fromCharCodes(
        Uri.decodeComponent(
          bytes.map((b) => '%${b.toRadixString(16).padLeft(2, '0')}').join(),
        ).runes,
      ),
    );
    bytes.clear();
  }

  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (c == '%' && i + 2 < text.length + 0 && _isHex(text, i + 1)) {
      final byte = int.parse(text.substring(i + 1, i + 3), radix: 16);
      final char = String.fromCharCode(byte);
      if (byte < 0x80 && _reservedUri.contains(char)) {
        flush();
        out.write(text.substring(i, i + 3));
      } else {
        bytes.add(byte);
      }
      i += 3;
      continue;
    }
    flush();
    out.write(c);
    i++;
  }
  flush();
  return out.toString();
}

const _reservedUri = r';/?:@&=+$,#';

bool _isHex(String text, int at) {
  if (at + 1 >= text.length) return false;
  return int.tryParse(text.substring(at, at + 2), radix: 16) != null;
}
