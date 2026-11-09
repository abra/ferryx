/// EPUB path helpers beyond resolving (`resolveBookUrl`): external links
/// and relative paths between container files, as `epub.js` has them.
library;

/// Whether [uri] points outside the container (`isExternal`): it has a
/// scheme, other than a blob URL.
bool isExternalEpubUri(String uri) => _external.hasMatch(uri);

final _external = RegExp(r'^(?!blob)\w+:', caseSensitive: false);

/// The directory part of [path], with its trailing slash (`pathDirname`).
String epubPathDirname(String path) =>
    path.substring(0, path.lastIndexOf('/') + 1);

/// The relative path from [from] to [to], like Node's `path.relative`.
String epubPathRelative(String from, String to) {
  if (from.isEmpty) return to;
  final as = from.replaceFirst(RegExp(r'/$'), '').split('/');
  final bs = to.replaceFirst(RegExp(r'/$'), '').split('/');
  final longer = as.length > bs.length ? as : bs;
  var i = 0;
  while (i < longer.length &&
      i < as.length &&
      i < bs.length &&
      as[i] == bs[i]) {
    i++;
  }
  if (i == longer.length) return '';
  return [
    for (var k = i; k < as.length; k++) '..',
    ...bs.skip(i),
  ].join('/');
}
