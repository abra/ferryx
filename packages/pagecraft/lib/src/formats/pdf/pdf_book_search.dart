import 'pdf_book.dart';
import 'pdf_text_layer.dart';
import 'pdf_text_layer_cache.dart';
import '../../search/text_search.dart';

/// One search hit: its page, range and excerpt.
class PdfSearchHit {
  const PdfSearchHit({required this.page, required this.match});

  final int page;
  final TextSearchMatch match;

  PdfTextRange get range => PdfTextRange(match.start, match.end);

  @override
  String toString() => 'PdfSearchHit(page $page, $match)';
}

/// Searches [book] page by page, yielding each page's hits as its text is
/// read; cancelling the subscription stops at the next page. Layers come
/// from [cache] when given, so the pages around the reader stay warm,
/// and are loaded and dropped otherwise.
Stream<List<PdfSearchHit>> searchPdfBook(
  PdfBook book,
  String query, {
  PdfTextLayerCache? cache,
}) async* {
  if (foldSearchText(query).text.trim().isEmpty) return;
  for (var page = 0; page < book.pageCount; page++) {
    final layer = cache == null
        ? await PdfTextLayer.load(book, page)
        : await cache.load(page);
    final hits = [
      for (final match in layer.search(query))
        PdfSearchHit(page: page, match: match),
    ];
    if (hits.isNotEmpty) yield hits;
  }
}
