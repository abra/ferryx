import 'dart:ui';

import '../../pagecraft_exception.dart';
import '../../search/text_search.dart';

class DjvuTextRange {
  const DjvuTextRange(this.start, this.end)
    : assert(start >= 0 && end >= start);
  final int start;
  final int end;
  int get length => end - start;
  bool get isEmpty => start == end;
  @override
  bool operator ==(Object other) =>
      other is DjvuTextRange && start == other.start && end == other.end;
  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DjvuTextRange($start, $end)';
}

/// DjVu hidden text supplies word zones; character precision is not invented.
class DjvuTextWord {
  const DjvuTextWord({
    required this.text,
    required this.start,
    required this.end,
    required this.box,
  });
  final String text;
  final int start;
  final int end;
  final Rect box;
  DjvuTextRange get range => DjvuTextRange(start, end);
}

class DjvuTextContext {
  const DjvuTextContext({
    required this.contextText,
    required this.markedContextText,
  });
  final String contextText;
  final String markedContextText;
}

/// Reading-order words and their top-left, oriented page coordinates. A scan
/// without hidden text yields an empty layer; this adapter never performs OCR.
class DjvuTextLayer {
  DjvuTextLayer({
    required this.pageIndex,
    required this.width,
    required this.height,
    required this.text,
    required List<DjvuTextWord> words,
  }) : words = List.unmodifiable(words);

  factory DjvuTextLayer.fromJson(int pageIndex, Map<String, Object?> data) {
    final width = (data['width'] as num).toDouble();
    final height = (data['height'] as num).toDouble();
    final rawWords = data['words'] as List;
    if (!width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        rawWords.length > 100000) {
      throw const PagecraftException(
        'Invalid DjVu text layer dimensions or size',
      );
    }
    final words = <DjvuTextWord>[];
    final text = StringBuffer();
    for (final raw in rawWords) {
      final word = (raw as Map).cast<String, Object?>();
      final value = word['text'] as String;
      if (value.isEmpty) continue;
      if (text.isNotEmpty) text.write(' ');
      final start = text.length;
      text.write(value);
      if (text.length > 4000000) {
        throw const PagecraftException('DjVu page text exceeds its budget');
      }
      final x = (word['x'] as num).toDouble();
      final y = (word['y'] as num).toDouble();
      final w = (word['width'] as num).toDouble();
      final h = (word['height'] as num).toDouble();
      if (![x, y, w, h].every((n) => n.isFinite) || w < 0 || h < 0) {
        throw const PagecraftException('Invalid DjVu word coordinates');
      }
      final box = Rect.fromLTWH(
        x,
        y,
        w,
        h,
      ).intersect(Rect.fromLTWH(0, 0, width, height));
      words.add(
        DjvuTextWord(
          text: value,
          start: start,
          end: text.length,
          box: box.isEmpty ? Rect.zero : box,
        ),
      );
    }
    return DjvuTextLayer(
      pageIndex: pageIndex,
      width: width,
      height: height,
      text: text.toString(),
      words: words,
    );
  }

  final int pageIndex;
  final double width;
  final double height;
  final String text;
  final List<DjvuTextWord> words;
  bool get isEmpty => text.trim().isEmpty;

  List<TextSearchMatch> search(String query) => searchText(text, query);

  String textOf(DjvuTextRange range) => text.substring(range.start, range.end);

  List<Rect> boxesOf(DjvuTextRange range) => [
    for (final word in words)
      if (word.start < range.end && word.end > range.start && !word.box.isEmpty)
        word.box,
  ];

  DjvuTextRange? wordAt(int index) {
    if (index < 0 || index >= text.length) return null;
    // Reading order is not geometric order (columns and RTL); offsets are sorted.
    var low = 0;
    var high = words.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final word = words[mid];
      if (index < word.start) {
        high = mid;
      } else if (index >= word.end) {
        low = mid + 1;
      } else {
        return word.range;
      }
    }
    return null;
  }

  DjvuTextRange? wordAtPoint(double x, double y) {
    for (final word in words) {
      if (word.box.contains(Offset(x, y))) return word.range;
    }
    return null;
  }

  int? charIndexAt(double x, double y) => wordAtPoint(x, y)?.start;

  DjvuTextRange? rangeOfText(String value) {
    final matches = search(value);
    return matches.isEmpty
        ? null
        : DjvuTextRange(matches.first.start, matches.first.end);
  }

  DjvuTextContext contextOf(DjvuTextRange range) {
    var start = range.start;
    var end = range.end;
    while (start > 0 &&
        range.start - start < 500 &&
        !_sentenceEnd(text[start - 1])) {
      start--;
    }
    while (end < text.length && end - range.end < 500) {
      final stop = _sentenceEnd(text[end]);
      end++;
      if (stop) break;
    }
    final before = text.substring(start, range.start);
    final selected = textOf(range);
    final after = text.substring(range.end, end);
    return DjvuTextContext(
      contextText: '$before$selected$after'.trim(),
      markedContextText: '$before[[$selected]]$after'.trim(),
    );
  }
}

bool _sentenceEnd(String value) =>
    value == '.' || value == '!' || value == '?' || value == '。';
