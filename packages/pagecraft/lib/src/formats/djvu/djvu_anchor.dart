import '../../epubcfi/fake_cfi.dart';
import 'djvu_text_layer.dart';

class DjvuTextAnchor {
  const DjvuTextAnchor({required this.pageIndex, required this.range});
  final int pageIndex;
  final DjvuTextRange range;
}

String djvuTextCfi(int pageIndex, DjvuTextRange range) {
  final page = fakeCfiFromIndex(pageIndex);
  final step = page.substring('epubcfi('.length, page.length - 1);
  return 'epubcfi($step!/2[pagecraft-djvu],/1:${range.start},/1:${range.end})';
}

final _range = RegExp(
  r'^epubcfi\(/6/(\d+)!/2\[pagecraft-djvu\],/1:(\d+),/1:(\d+)\)$',
);

DjvuTextAnchor? djvuTextAnchorFromCfi(String cfi) {
  final match = _range.firstMatch(cfi);
  if (match == null) return null;
  final page = fakeCfiToIndex('epubcfi(/6/${match[1]})');
  final start = int.tryParse(match[2]!);
  final end = int.tryParse(match[3]!);
  if (page == null || start == null || end == null || start > end) return null;
  return DjvuTextAnchor(pageIndex: page, range: DjvuTextRange(start, end));
}

DjvuTextRange? resolveDjvuTextAnchor(
  DjvuTextLayer layer, {
  required String text,
  String? cfiRange,
}) {
  final anchor = cfiRange == null ? null : djvuTextAnchorFromCfi(cfiRange);
  final range = anchor?.range;
  if (anchor?.pageIndex == layer.pageIndex &&
      range != null &&
      range.end <= layer.text.length &&
      _normalized(layer.textOf(range)) == _normalized(text)) {
    return range;
  }
  return layer.rangeOfText(text);
}

String _normalized(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
