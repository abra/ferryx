/// Anchors for text on PDF pages.
///
/// The WebView reader anchored PDF highlights with CFIs into the DOM text
/// layer `pdf.js` built (`epubcfi(/6/N!/4/4/M,/1:a,/1:b)`), paths that
/// only that DOM can resolve. pagecraft keeps the page step, which both
/// readers understand ([fakeCfiToIndex]), and writes the character range of
/// its own text layer after it: `epubcfi(/6/N!/2[pagecraft],/1:start,/1:end)`.
/// A highlight's saved text is the anchor both readers share: when a CFI
/// is not pagecraft's, or the page's text changed, the text is searched on
/// the page.
library;

import 'pdf_text_layer.dart';
import '../../epubcfi/fake_cfi.dart';

/// A character range on a page.
class PdfTextAnchor {
  const PdfTextAnchor({required this.pageIndex, required this.range});

  final int pageIndex;
  final PdfTextRange range;

  @override
  bool operator ==(Object other) =>
      other is PdfTextAnchor &&
      other.pageIndex == pageIndex &&
      other.range == range;

  @override
  int get hashCode => Object.hash(pageIndex, range);

  @override
  String toString() => 'PdfTextAnchor(page $pageIndex, $range)';
}

final _pagecraftRange = RegExp(
  r'^epubcfi\(/6/(\d+)!/2\[pagecraft\],/1:(\d+),/1:(\d+)\)$',
);

/// The CFI pagecraft writes for [range] on page [pageIndex].
String pdfTextCfi(int pageIndex, PdfTextRange range) {
  final page = fakeCfiFromIndex(pageIndex);
  final step = page.substring('epubcfi('.length, page.length - 1);
  return 'epubcfi($step!/2[pagecraft],/1:${range.start},/1:${range.end})';
}

/// The anchor a pagecraft-written CFI names, or null for any other CFI
/// (the page of those is still [fakeCfiToIndex]).
PdfTextAnchor? pdfTextAnchorFromCfi(String cfi) {
  final match = _pagecraftRange.firstMatch(cfi);
  if (match == null) return null;
  final pageIndex = fakeCfiToIndex('epubcfi(/6/${match.group(1)})');
  final start = int.parse(match.group(2)!);
  final end = int.parse(match.group(3)!);
  if (pageIndex == null || start > end) return null;
  return PdfTextAnchor(pageIndex: pageIndex, range: PdfTextRange(start, end));
}

/// Where a saved highlight lies on [layer]: the CFI's own range when it is
/// pagecraft's and still reads as [text], otherwise the first occurrence of
/// [text] on the page; null when the text is no longer there.
PdfTextRange? resolvePdfTextAnchor(
  PdfTextLayer layer, {
  required String text,
  String? cfiRange,
}) {
  final anchor = cfiRange == null ? null : pdfTextAnchorFromCfi(cfiRange);
  if (anchor != null &&
      anchor.pageIndex == layer.pageIndex &&
      anchor.range.end <= layer.text.length &&
      _sameText(layer.textOf(anchor.range), text)) {
    return anchor.range;
  }
  return layer.rangeOfText(text);
}

final _whitespace = RegExp(r'\s+');

bool _sameText(String a, String b) =>
    a.replaceAll(_whitespace, ' ').trim() ==
    b.replaceAll(_whitespace, ' ').trim();
