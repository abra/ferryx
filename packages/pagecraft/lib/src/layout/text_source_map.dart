import 'dart:typed_data';

/// Where each character of a laid-out paragraph came from in the
/// document, and back: what CFIs, selection, highlights and search need
/// once whitespace has collapsed and text has been transformed.
///
/// The map is a list of segments, five integers each: a range of the
/// paragraph's text and the range of one document node it renders. Most
/// segments are one to one (a run of text copied as is); a collapsed run
/// of whitespace is one paragraph character for several source
/// characters; whitespace dropped at a line start is a source range with
/// no paragraph characters; an image or a line break is one paragraph
/// character for an element. Generated text (list markers, quotes) has no
/// segment. Offsets are UTF-16 code units on both sides, as JavaScript
/// and CFIs count them.
class TextSourceMap {
  TextSourceMap._(this._data);

  static final empty = TextSourceMap._(Int32List(0));

  /// `[paragraphStart, paragraphLength, node, nodeStart, nodeLength]*`,
  /// ordered by paragraph offset and, within the paragraph, by node.
  final Int32List _data;

  int get segmentCount => _data.length ~/ 5;

  /// The first document node this paragraph renders, or -1.
  int get firstNode => _data.isEmpty ? -1 : _data[2];

  /// The last document node this paragraph renders, or -1.
  int get lastNode => _data.isEmpty ? -1 : _data[_data.length - 3];

  /// The document position of paragraph offset [offset], as a node and
  /// an offset in it (characters for text, 0 for an element), or null
  /// when the paragraph has no source at all.
  ///
  /// At a boundary between two segments the later one wins, so an offset
  /// is the start of what follows it, as a caret before that character.
  /// Offsets inside generated text map to the next source position.
  ({int node, int offset})? toSource(int offset) {
    if (_data.isEmpty) return null;
    // The last segment that starts at or before [offset].
    var lo = 0;
    var hi = segmentCount - 1;
    var found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_data[mid * 5] <= offset) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (found < 0) return (node: _data[2], offset: _data[3]);
    // Prefer the first segment starting exactly at [offset], so a zero-
    // length segment (dropped whitespace) does not shadow the text after.
    var i = found;
    while (i > 0 && _data[(i - 1) * 5] == offset && _data[i * 5] == offset) {
      i--;
    }
    while (i < segmentCount - 1 &&
        _data[i * 5 + 1] == 0 &&
        _data[(i + 1) * 5] == offset) {
      i++;
    }
    final base = i * 5;
    final start = _data[base];
    final length = _data[base + 1];
    final nodeStart = _data[base + 3];
    final nodeLength = _data[base + 4];
    final into = offset - start;
    if (into > length && i < segmentCount - 1) {
      // Inside generated text after this segment: the next source.
      final next = (i + 1) * 5;
      return (node: _data[next + 2], offset: _data[next + 3]);
    }
    // One to one inside a copied run; otherwise (collapsed whitespace,
    // an expanded transform, an element) only the two ends exist.
    final mapped = length == nodeLength
        ? (into < length ? into : length)
        : (into == 0 ? 0 : nodeLength);
    return (node: _data[base + 2], offset: nodeStart + mapped);
  }

  /// Where a range ending at paragraph offset [offset] ends in the
  /// document: just after the character before it. At a boundary the
  /// earlier segment wins, and an end inside generated text is the end of
  /// the source before it; after an element (an image, a line break) the
  /// offset is 1, after the element. Null when the paragraph has no
  /// source.
  ({int node, int offset})? toSourceEnd(int offset) {
    if (_data.isEmpty) return null;
    // The last segment that starts before [offset].
    var lo = 0;
    var hi = segmentCount - 1;
    var found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_data[mid * 5] < offset) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (found < 0) return (node: _data[2], offset: _data[3]);
    final base = found * 5;
    final into = offset - _data[base];
    final length = _data[base + 1];
    final nodeLength = _data[base + 4];
    if (length == 1 && nodeLength == 0) {
      return (node: _data[base + 2], offset: 1);
    }
    // One to one inside a copied run; otherwise the whole source run.
    final mapped = length == nodeLength
        ? (into < length ? into : length)
        : nodeLength;
    return (node: _data[base + 2], offset: _data[base + 3] + mapped);
  }

  /// The paragraph offset of [offset] in [node], or null when this
  /// paragraph does not render that node. Offsets inside a collapsed
  /// whitespace run map to the run's one character; offsets in dropped
  /// whitespace map to where it was dropped.
  int? toParagraph(int node, int offset) {
    int? atEnd;
    for (var base = 0; base < _data.length; base += 5) {
      if (_data[base + 2] != node) continue;
      final start = _data[base];
      final length = _data[base + 1];
      final nodeStart = _data[base + 3];
      final nodeLength = _data[base + 4];
      if (offset < nodeStart) return atEnd ?? start;
      if (offset < nodeStart + nodeLength ||
          (offset == nodeStart && nodeLength == 0)) {
        final into = offset - nodeStart;
        if (length == nodeLength) return start + into;
        return start + (into == 0 ? 0 : length);
      }
      // At or past this segment's end: a later segment of the node may
      // start exactly here and own the position.
      atEnd = start + length;
    }
    return atEnd;
  }

  /// The paragraph offset of the first source at or after document node
  /// [node] (nodes are numbered in document order, so an element's
  /// content comes after it), or null when everything here is before.
  int? offsetFromNode(int node) {
    for (var base = 0; base < _data.length; base += 5) {
      if (_data[base + 2] >= node) return _data[base];
    }
    return null;
  }

  /// The map of the paragraph's text from [from] on, its offsets counted
  /// from there (`ParagraphBox.tail`): segments before [from] are left
  /// out, one that runs across it keeps its part after it (cut in the
  /// source too when it was copied one to one), and one that ends at it
  /// leaves an empty segment at its source's end.
  TextSourceMap tail(int from) {
    if (from == 0) return this;
    final out = <int>[];
    for (var base = 0; base < _data.length; base += 5) {
      final start = _data[base];
      final length = _data[base + 1];
      final end = start + length;
      if (end < from) continue;
      if (end == from && length > 0) {
        // Ends where the tail starts: kept as the empty segment dropped
        // whitespace makes, at the source's end, so a caret there maps.
        out.addAll([
          0,
          0,
          _data[base + 2],
          _data[base + 3] + _data[base + 4],
          0,
        ]);
        continue;
      }
      if (start >= from) {
        out
          ..add(start - from)
          ..addAll(_data.sublist(base + 1, base + 5));
        continue;
      }
      final cut = from - start;
      final nodeStart = _data[base + 3];
      final nodeLength = _data[base + 4];
      final oneToOne = length == nodeLength;
      out.addAll([
        0,
        length - cut,
        _data[base + 2],
        oneToOne ? nodeStart + cut : nodeStart,
        oneToOne ? nodeLength - cut : nodeLength,
      ]);
    }
    return TextSourceMap._(Int32List.fromList(out));
  }

  /// The document nodes the segments render, in order, with repeats.
  Iterable<int> get nodes sync* {
    for (var base = 2; base < _data.length; base += 5) {
      yield _data[base];
    }
  }

  /// The segments as records, for tests and debugging.
  List<({int start, int length, int node, int nodeStart, int nodeLength})>
  get segments => [
    for (var base = 0; base < _data.length; base += 5)
      (
        start: _data[base],
        length: _data[base + 1],
        node: _data[base + 2],
        nodeStart: _data[base + 3],
        nodeLength: _data[base + 4],
      ),
  ];
}

/// Collects segments while a paragraph is built, merging neighbours that
/// continue each other one to one.
class TextSourceMapBuilder {
  final _data = <int>[];

  bool get isEmpty => _data.isEmpty;

  /// Paragraph range `[start, start + length)` renders [node]'s range
  /// `[nodeStart, nodeStart + nodeLength)`.
  void add(int start, int length, int node, int nodeStart, int nodeLength) {
    final n = _data.length;
    if (n >= 5 &&
        length == nodeLength &&
        _data[n - 3] == node &&
        _data[n - 4] == _data[n - 1] &&
        _data[n - 5] + _data[n - 4] == start &&
        _data[n - 2] + _data[n - 1] == nodeStart) {
      _data[n - 4] += length;
      _data[n - 1] += nodeLength;
      return;
    }
    _data
      ..add(start)
      ..add(length)
      ..add(node)
      ..add(nodeStart)
      ..add(nodeLength);
  }

  TextSourceMap build() => _data.isEmpty
      ? TextSourceMap.empty
      : TextSourceMap._(Int32List.fromList(_data));
}
