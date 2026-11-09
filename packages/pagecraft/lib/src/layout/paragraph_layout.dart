import 'dart:ui'
    as ui
    show BoxHeightStyle, LineMetrics, ParagraphBuilder, PlaceholderAlignment;

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../css/css_values.dart';
import 'box_tree.dart';
import 'column_decoration.dart';
import 'column_decoration_painter.dart';
import 'inline_styler.dart';
import 'line_exclusions.dart';
import 'math_layout.dart';

/// The intrinsic pixel size of an image, by its source as the paragraph
/// wrote it, or null when unknown (missing, or not probed yet).
typedef ImageSizeLookup = Size? Function(String src);

/// What paragraph layout needs besides the paragraph: styles and fonts
/// through [styler], image sizes, and the tallest an image may be (the
/// page's content height), since an image never breaks across pages.
class TextLayoutEnvironment {
  const TextLayoutEnvironment({
    required this.styler,
    required this.imageSize,
    required this.maxImageHeight,
    this.textScaler = TextScaler.noScaling,
  });

  final InlineStyler styler;
  final ImageSizeLookup imageSize;
  final double maxImageHeight;
  final TextScaler textScaler;
}

/// Where each line but the first starts in [painter], as offsets of a
/// paragraph text [length] long that the painter's text holds after
/// [shift] placeholders.
List<int> _lineStarts(TextPainter painter, int shift, int length) => [
  for (final start in _painterLineStarts(painter).skip(1)) start - shift,
];

/// Where each line of [painter] starts, as painter offsets: the position
/// at the start edge of each line, one cheap query a line
/// (`getLineBoundary` computes every line's metrics on each call).
List<int> _painterLineStarts(TextPainter painter) {
  final metrics = painter.computeLineMetrics();
  final rtl = painter.textDirection == TextDirection.rtl;
  return [
    0,
    for (var i = 1; i < metrics.length; i++)
      painter
          .getPositionForOffset(
            Offset(
              rtl
                  ? metrics[i].left + metrics[i].width + 1
                  : metrics[i].left - 1,
              metrics[i].baseline,
            ),
          )
          .offset,
  ];
}

/// Which of a paragraph's soft hyphens (U+00AD: a book's `&shy;`, or
/// what `hyphens: auto` put there) break its lines, decided line by line
/// as a browser does. Flutter breaks at a soft hyphen but draws nothing,
/// so one at a line end is shown as a hyphen (`-`, which every font
/// has), and the text keeps its length, so offsets stay the
/// paragraph's.
///
/// The lines are decided on a layout with natural line widths (start
/// aligned: justification stretches them): a soft hyphen at a line end
/// fits when its line and a hyphen do, and is shown with no new layout;
/// one that does not fit is disabled (U+2060, no break) with every other
/// on its line past the last place that fits, a soft hyphen or a space
/// found from the caret positions, and the lines from there on are laid
/// out again. Then the paragraph is laid out once with its own
/// alignment and checked as the lines settle: a hyphen that no longer
/// ends the line it was shown for is disabled and the lines after it are
/// decided again (a shown hyphen is a break of its own: kept after its
/// line moved, it would break a word that now fits). Soft hyphens in
/// `hyphens: none` text never break. At most [maxLines] lines in a row
/// end with a hyphen (`-webkit-hyphenate-limit-lines`).
class _Hyphens {
  _Hyphens(
    ParagraphBox box,
    this.shift,
    this.layOut, {
    required this.width,
    required this.hyphenWidthAt,
    required this.natural,
    required this.rtl,
    this.maxLines,
  }) : _codes = List.of(box.text.codeUnits) {
    for (final run in box.runs) {
      final none = run.style.hyphens == CssHyphens.none;
      for (var i = run.start; i < run.end; i++) {
        if (_codes[i] != _soft) continue;
        if (none) {
          _codes[i] = _disabled;
        } else {
          _candidates.add(i);
        }
      }
    }
  }

  static const _soft = 0x00AD;
  static const _shown = 0x002D;
  static const _disabled = 0x2060;

  /// Characters a line may break after (UAX #14 HY, BA dashes, B2): a
  /// hyphen on its line is the text's own, never a shown soft hyphen.
  static const _breaksAfter = {0x2D, 0x2010, 0x2012, 0x2013, 0x2014};

  /// What a line may overshoot by and still fit, for float rounding.
  static const _epsilon = 0.01;

  /// Rounds before a paragraph that keeps changing loses its hyphens;
  /// most need none.
  static const _rounds = 24;

  final int shift;
  final TextPainter Function(String text, {bool natural}) layOut;
  final double width;
  final double Function(int offset) hyphenWidthAt;

  /// Whether [layOut]'s lines are natural without `natural: true` (the
  /// paragraph is not justified).
  final bool natural;
  final bool rtl;
  final int? maxLines;
  final List<int> _codes;

  /// Text offsets of the soft hyphens that may break, in order.
  final _candidates = <int>[];

  /// Where the line each shown hyphen ends started when it was shown.
  final _lineStarts = <int, int>{};

  String get _text => String.fromCharCodes(_codes);

  /// The painter to keep, and the offsets of the hyphens it shows.
  (TextPainter, Set<int>, String) resolve() {
    if (_candidates.isEmpty) return (layOut(_text), const {}, _text);
    var painter = _decide(layOut(_text, natural: true));
    // A single line is not justified: its natural layout is the one.
    final same = natural || painter.computeLineMetrics().length < 2;
    if (!same || _laidOut != _text) {
      painter.dispose();
      painter = layOut(_text);
    }
    for (var round = 0; round < _rounds; round++) {
      if (!_settle(painter)) {
        return (
          painter,
          {
            for (final offset in _candidates)
              if (_codes[offset] == _shown) offset,
          },
          _text,
        );
      }
      painter = _relaid(painter);
    }
    for (final offset in _candidates) {
      _codes[offset] = _disabled;
    }
    return (_relaid(painter), const {}, _text);
  }

  /// The text the last natural layout of [_decide] had.
  String? _laidOut;

  /// Decides each line's hyphen on natural layouts, from the top: one
  /// new layout for each line whose end moves.
  TextPainter _decide(TextPainter first) {
    var painter = first;
    _laidOut = _text;
    var from = 0;
    for (var round = 0; round < _rounds; round++) {
      final lines = _lines(painter);
      final metrics = painter.computeLineMetrics();
      int? moved;
      for (var i = from; i < lines.length && i < metrics.length; i++) {
        final offset = lines[i].end - shift - 1;
        if (offset < 0 || _codes[offset] != _soft) continue;
        final limit = maxLines;
        final hyphenated = limit != null && _endsHyphenated(lines, i, limit);
        if (!hyphenated &&
            metrics[i].width + hyphenWidthAt(offset) <= width + _epsilon) {
          _codes[offset] = _shown;
          _lineStarts[offset] = lines[i].start;
          continue;
        }
        _breakEarlier(
          painter,
          lines[i],
          metrics[i],
          offset,
          hyphen: !hyphenated,
        );
        moved = i;
        break;
      }
      if (moved == null) return painter;
      painter.dispose();
      _laidOut = _text;
      painter = layOut(_laidOut!, natural: true);
      from = moved;
    }
    return painter;
  }

  /// Whether the [limit] lines before line [index] all end hyphenated.
  bool _endsHyphenated(List<TextRange> lines, int index, int limit) {
    if (index < limit) return false;
    for (var i = index - limit; i < index; i++) {
      final offset = lines[i].end - shift - 1;
      if (offset < 0 || _codes[offset] != _shown) return false;
    }
    return true;
  }

  /// Ends [line] at the last place before [offset] that fits: a soft
  /// hyphen with its hyphen (unless [hyphen] is false), a space, or after
  /// a hyphen or dash of the text; the soft hyphens after it on the line
  /// no longer break.
  void _breakEarlier(
    TextPainter painter,
    TextRange line,
    ui.LineMetrics metrics,
    int offset, {
    required bool hyphen,
  }) {
    final start = line.start - shift;
    var best = -1;
    for (var p = offset - 1; p > start; p--) {
      final code = _codes[p];
      final soft = hyphen && code == _soft;
      // A space hangs past the line end; a dash stays on its line.
      final dash = _breaksAfter.contains(code);
      if (!soft && code != 0x20 && !dash) continue;
      final x = painter
          .getOffsetForCaret(
            TextPosition(offset: p + shift + (dash ? 1 : 0)),
            Rect.zero,
          )
          .dx;
      final advance = rtl ? metrics.left + metrics.width - x : x - metrics.left;
      if (advance + (soft ? hyphenWidthAt(p) : 0) <= width + _epsilon) {
        best = dash ? p + 1 : p;
        break;
      }
    }
    for (final other in _candidates) {
      if (other > best && other <= offset) _codes[other] = _disabled;
    }
    if (best >= 0 && _codes[best] == _soft) {
      _codes[best] = _shown;
      _lineStarts[best] = line.start;
    }
  }

  TextPainter _relaid(TextPainter old) {
    old.dispose();
    return layOut(_text);
  }

  /// One round against [painter]: checks the hyphens shown, then shows
  /// the soft hyphens at line ends; whether anything changed.
  bool _settle(TextPainter painter) {
    final lines = _lines(painter);
    final lineByEnd = {for (var i = 0; i < lines.length; i++) lines[i].end: i};
    int? lineOf(int offset) => lineByEnd[offset + shift + 1];

    // A hyphen that did not fit moved its line's end: it no longer ends
    // the line it was shown for.
    for (final offset in _candidates) {
      if (_codes[offset] != _shown) continue;
      final line = lineOf(offset);
      if (line == null || lines[line].start != _lineStarts[offset]) {
        _codes[offset] = _disabled;
        _redecideAfter(offset);
        return true;
      }
    }
    final limit = maxLines;
    if (limit != null) {
      var run = 0;
      int? previous;
      for (final offset in _candidates) {
        if (_codes[offset] != _shown) continue;
        final line = lineOf(offset)!;
        run = previous != null && line == previous + 1 ? run + 1 : 1;
        previous = line;
        if (run <= limit) continue;
        // That line breaks without a hyphen.
        final range = lines[line];
        for (final other in _candidates) {
          final at = other + shift;
          if (at >= range.start && at < range.end) _codes[other] = _disabled;
        }
        _redecideAfter(offset);
        return true;
      }
    }
    var changed = false;
    for (final offset in _candidates) {
      final line = lineOf(offset);
      if (_codes[offset] == _soft && line != null) {
        _codes[offset] = _shown;
        _lineStarts[offset] = lines[line].start;
        changed = true;
      }
    }
    return changed;
  }

  /// The lines after [offset]'s move: their hyphens are decided again.
  void _redecideAfter(int offset) {
    for (final other in _candidates) {
      if (other > offset) {
        _codes[other] = _soft;
        _lineStarts.remove(other);
      }
    }
  }

  /// Each line's range in painter offsets, but the last line's.
  List<TextRange> _lines(TextPainter painter) {
    final starts = _painterLineStarts(painter);
    return [
      for (var i = 0; i + 1 < starts.length; i++)
        TextRange(start: starts[i], end: starts[i + 1]),
    ];
  }
}

/// An atomic inline where the layout put it.
/// The line among [lines] whose baseline lies in `[top, bottom]` (half a
/// pixel of slack), by binary search: baselines increase down a
/// paragraph.
int _lineWithBaselineIn(List<ui.LineMetrics> lines, double top, double bottom) {
  var lo = 0;
  var hi = lines.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].baseline < top - 0.5) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo < lines.length && lines[lo].baseline <= bottom + 0.5 ? lo : -1;
}

/// The line of [count] at [y], by their [tops]; clamped to the lines.
int _lineAtY(List<double> tops, int count, double y) {
  if (count == 0) return 0;
  var lo = 0;
  var hi = count - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (tops[mid] <= y) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

class PlacedAtomic {
  const PlacedAtomic(
    this.atomic,
    this.rect, {
    this.text,
    this.textAt = Offset.zero,
    this.math,
  });

  final InlineAtomic atomic;

  /// Its box, relative to the paragraph's top left: an inline block's
  /// margin box.
  final Rect rect;

  /// The laid-out paragraph of an [InlineText].
  final ParagraphLayout? text;

  /// Where [text] starts in [rect]: inside an inline block's margin,
  /// border and padding.
  final Offset textAt;

  /// Where [text] is, relative to the paragraph's top left.
  Offset get textOffset => rect.topLeft + textAt;

  /// The laid-out formula of an [InlineMath], drawn over [rect].
  final MathLayout? math;
}

/// An atomic's placeholder, the paragraph laid out for raised text or an
/// inline block, and where that paragraph starts in the placeholder.
typedef _Measured = ({
  PlaceholderDimensions dims,
  ParagraphLayout? text,
  Offset textAt,
  MathLayout? math,
});

/// One [ParagraphBox] laid out at a width: a [TextPainter] over the
/// paragraph's runs, with placeholders for images, raised text and the
/// first-line indent. A paragraph beside a float is several of these
/// ([ParagraphLayout]).
///
/// Offsets are the laid-out box's text offsets; the indent placeholder
/// some paragraphs start with is hidden.
class _Band {
  _Band._(
    this.box,
    this._painter,
    this._shift,
    this.width,
    this.atomics,
    this._hyphens,
  ) : lines = _painter.computeLineMetrics() {
    _lineTops = _computeLineTops();
  }

  /// Lays [box] out [width] wide; see [ParagraphLayout.layout].
  /// [containerWidth] is the paragraph's own width, which inline
  /// blocks' percentages are of: a band beside a float is narrower.
  factory _Band.layout(
    ParagraphBox box, {
    required double width,
    required double containerWidth,
    required TextLayoutEnvironment environment,
    required bool listItem,
    required bool nested,
  }) {
    final styler = environment.styler;
    final block = box.style;
    final prose = box.isProse && !nested;
    final indent = nested
        ? 0.0
        : styler.firstLineIndent(box, width, listItem: listItem);
    final align = nested
        ? TextAlign.start
        : styler.textAlign(block, prose: prose);
    final shift = indent > 0 ? 1 : 0;
    // Atomics are measured once; the text may be laid out a few times.
    final measured = [
      for (final atomic in box.atomics)
        ParagraphLayout._measure(
          atomic,
          width,
          environment,
          containerWidth: containerWidth,
        ),
    ];

    /// A painter over [text]: [box]'s text, or the same with some soft
    /// hyphens shown or disabled; runs are cut at [lineStarts], so each
    /// line's part takes the line height of its own glyphs. A [natural]
    /// layout is start aligned: its lines keep their natural widths.
    TextPainter layOut(
      String text, {
      List<int> lineStarts = const [],
      bool natural = false,
    }) {
      final spans = <InlineSpan>[];
      final dimensions = <PlaceholderDimensions>[];
      if (indent > 0) {
        spans.add(
          const _AtomicSpan(alignment: ui.PlaceholderAlignment.baseline),
        );
        dimensions.add(
          PlaceholderDimensions(
            size: Size(indent, 0),
            alignment: ui.PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            baselineOffset: 0,
          ),
        );
      }
      var atomicIndex = 0;
      var cut = 0;
      for (final run in box.runs) {
        var from = run.start;
        while (from < run.end) {
          while (cut < lineStarts.length && lineStarts[cut] <= from) {
            cut++;
          }
          final to = cut < lineStarts.length && lineStarts[cut] < run.end
              ? lineStarts[cut]
              : run.end;
          final style = styler.textStyle(
            run.style,
            block,
            prose: prose,
            text: text,
            start: from,
            end: to,
          );
          var start = from;
          while (start < to) {
            final next = atomicIndex < box.atomics.length
                ? box.atomics[atomicIndex].offset
                : text.length;
            if (next >= to || next < start) {
              spans.add(
                TextSpan(text: text.substring(start, to), style: style),
              );
              start = to;
              break;
            }
            if (next > start) {
              spans.add(
                TextSpan(text: text.substring(start, next), style: style),
              );
            }
            final dims = measured[atomicIndex++].dims;
            spans.add(_AtomicSpan(alignment: dims.alignment, style: style));
            dimensions.add(dims);
            start = next + 1;
          }
          from = to;
        }
      }
      final painter = TextPainter(
        text: TextSpan(children: spans),
        textAlign: natural ? TextAlign.start : align,
        textDirection: InlineStyler.direction(block),
        strutStyle: styler.strut(block, prose: prose),
        textScaler: environment.textScaler,
        textWidthBasis: nested
            ? TextWidthBasis.longestLine
            : TextWidthBasis.parent,
      )..setPlaceholderDimensions(dimensions);
      // A block's lines are as wide as the block: alignment works against
      // that width. (Without minWidth the painter shrinks to its text and
      // centred, right-aligned and RTL lines move to the left edge.)
      painter.layout(minWidth: nested ? 0 : width, maxWidth: width);
      return painter;
    }

    TextPainter painter;
    var text = box.text;
    var hyphens = const <int>{};
    if (text.contains(softHyphen)) {
      (painter, hyphens, text) = _Hyphens(
        box,
        shift,
        layOut,
        width: width,
        hyphenWidthAt: (offset) {
          final run = box.runs.lastWhere(
            (r) => r.start <= offset,
            orElse: () => box.runs.first,
          );
          return styler.hyphenWidth(
            styler.textStyle(run.style, block, prose: prose),
            environment.textScaler,
          );
        },
        natural: align != TextAlign.justify,
        rtl: InlineStyler.direction(block) == TextDirection.rtl,
        maxLines: styler.bookStyle.hyphenation.maxLines,
      ).resolve();
    } else {
      painter = layOut(text);
    }
    // WebKit's glyph line boxes hold each line's own glyphs: a run over
    // several lines is cut where they break and laid out again, which
    // keeps the breaks (the text and its widths are the same).
    if (box.runs.any(
      (r) => styler.holdsGlyphs(r.style, block, prose: prose),
    )) {
      final starts = _lineStarts(painter, shift, text.length);
      if (starts.isNotEmpty) {
        painter.dispose();
        painter = layOut(text, lineStarts: starts);
      }
    }

    final boxes = painter.inlinePlaceholderBoxes ?? const <TextBox>[];
    final atomics = <PlacedAtomic>[
      for (var i = 0; i < measured.length && i + shift < boxes.length; i++)
        PlacedAtomic(
          box.atomics[i],
          boxes[i + shift].toRect().shift(
            ParagraphLayout._relativeOffset(box.atomics[i].style, width),
          ),
          text: measured[i].text,
          textAt: measured[i].textAt,
          math: measured[i].math,
        ),
    ];
    return _Band._(box, painter, shift, width, atomics, hyphens);
  }

  final ParagraphBox box;
  final TextPainter _painter;

  /// 1 when an indent placeholder leads the painter's text.
  final int _shift;

  /// Text offsets of soft hyphens shown as hyphens, at line ends.
  final Set<int> _hyphens;

  final double width;
  final List<PlacedAtomic> atomics;
  final List<ui.LineMetrics> lines;
  late final List<double> _lineTops;

  double get height => _painter.height;

  double get longestLine => _painter.width;

  double get minIntrinsicWidth => _painter.minIntrinsicWidth;
  double get maxIntrinsicWidth => _painter.maxIntrinsicWidth;

  /// The top of line [index], or the band's height for `lines.length`.
  double lineTop(int index) => _lineTops[index];

  /// Line tops from the full-line selection boxes: `LineMetrics.height`
  /// leaves out the strut, which is most of a line's height in body
  /// text. Each box spans its whole line, so the line is the one whose
  /// baseline the box contains; a line with no box (an empty line)
  /// starts where the line above it ends.
  List<double> _computeLineTops() {
    final n = lines.length;
    final tops = List<double>.filled(n + 1, double.nan);
    final bottoms = List<double>.filled(n, double.nan);
    if (n == 0) return [0];
    final length = box.text.length + _shift;
    final boxes = length == 0
        ? const <TextBox>[]
        : _painter.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: length),
            boxHeightStyle: ui.BoxHeightStyle.max,
          );
    for (final b in boxes) {
      final line = _lineWithBaselineIn(lines, b.top, b.bottom);
      if (line < 0) continue;
      if (tops[line].isNaN || b.top < tops[line]) tops[line] = b.top;
      if (bottoms[line].isNaN || b.bottom > bottoms[line]) {
        bottoms[line] = b.bottom;
      }
    }
    tops[0] = 0;
    tops[n] = _painter.height;
    for (var i = 1; i < n; i++) {
      if (tops[i].isNaN) {
        tops[i] = bottoms[i - 1].isNaN
            ? lines[i].baseline - lines[i].ascent
            : bottoms[i - 1];
      }
      if (tops[i] < tops[i - 1]) tops[i] = tops[i - 1];
    }
    return tops;
  }

  int lineAt(int offset) => _lineAtY(
    _lineTops,
    lines.length,
    _painter
        .getOffsetForCaret(TextPosition(offset: offset + _shift), Rect.zero)
        .dy,
  );

  int lineStart(int line) {
    final middle = (lineTop(line) + lineTop(line + 1)) / 2;
    final position = _painter.getPositionForOffset(Offset(width / 2, middle));
    final range = _painter.getLineBoundary(position);
    return (range.start - _shift).clamp(0, box.text.length);
  }

  TextPosition positionAt(Offset position) {
    final p = _painter.getPositionForOffset(position);
    return TextPosition(
      offset: (p.offset - _shift).clamp(0, box.text.length),
      affinity: p.affinity,
    );
  }

  List<TextBox> boxesFor(int start, int end, ui.BoxHeightStyle heightStyle) =>
      _painter.getBoxesForSelection(
        TextSelection(baseOffset: start + _shift, extentOffset: end + _shift),
        boxHeightStyle: heightStyle,
      );

  Offset caretBottom(int offset) {
    final position = TextPosition(offset: offset + _shift);
    return _painter.getOffsetForCaret(position, Rect.zero) +
        Offset(0, _painter.getFullHeightForCaret(position, Rect.zero));
  }

  double caretHeight(int offset) => _painter.getFullHeightForCaret(
    TextPosition(offset: offset + _shift),
    Rect.zero,
  );

  bool showsHyphenAt(int offset) => _hyphens.contains(offset);

  /// The painter's word around [offset], which a shown hyphen splits.
  TextRange wordBoundary(int offset) {
    final range = _painter.getWordBoundary(
      TextPosition(offset: offset + _shift),
    );
    return TextRange(
      start: (range.start - _shift).clamp(0, box.text.length),
      end: (range.end - _shift).clamp(0, box.text.length),
    );
  }

  void paint(Canvas canvas, Offset offset) {
    _painter.paint(canvas, offset);
    for (final atomic in atomics) {
      atomic.text?.paint(canvas, offset + atomic.textOffset);
      atomic.math?.paint(canvas, offset + atomic.rect.topLeft);
    }
  }

  void dispose() {
    _painter.dispose();
    for (final atomic in atomics) {
      atomic.text?.dispose();
      atomic.math?.dispose();
    }
  }
}

/// A band of a paragraph beside floats: text `[from, to)` of the
/// paragraph on the band's first [lineCount] lines, [dx] from the
/// paragraph's left edge and [dy] from its top. The band's painter holds
/// the rest of the paragraph too, on lines that are not used: the last
/// line used is then not the painter's last, and justified text stays
/// justified up to the band's end.
class _PlacedBand {
  _PlacedBand(
    this.band, {
    required this.from,
    required this.to,
    required this.dx,
    required this.dy,
    required this.firstLine,
    required this.lineCount,
  });

  final _Band band;
  final int from;
  final int to;
  final double dx;
  final double dy;

  /// The paragraph's line index of the band's first line.
  final int firstLine;
  final int lineCount;

  double get height => band.lineTop(lineCount);

  Offset get offset => Offset(dx, dy);

  bool get isWhole => from == 0 && dx == 0 && dy == 0;
}

/// One [ParagraphBox] laid out at a width: its lines, what is where on
/// them, and painting.
///
/// Lines beside floats are shorter (CSS 2.1 §9.5): the paragraph is laid
/// out in bands, each over the rest of the text at the width the floats
/// leave, keeping the lines that start beside them; a paragraph with
/// nothing beside it is one band.
///
/// Offsets in this API are the paragraph's text offsets
/// (`ParagraphBox.text`); the indent placeholder some paragraphs start
/// with is hidden. Owns native resources: [dispose] when done.
class ParagraphLayout {
  ParagraphLayout._(this.box, this.width, this._bands)
    : lines = _linesOf(_bands),
      _lineTops = _lineTopsOf(_bands),
      atomics = _atomicsOf(box, _bands);

  /// Lays [box] out [width] wide. [listItem] says the paragraph is a
  /// list item's own text (no prose indent); [nested] lays out raised
  /// text: start-aligned, as narrow as its longest line. [exclusions]
  /// are the floats beside the paragraph.
  factory ParagraphLayout.layout(
    ParagraphBox box, {
    required double width,
    required TextLayoutEnvironment environment,
    bool listItem = false,
    bool nested = false,
    LineExclusions? exclusions,
  }) {
    _Band layOut(ParagraphBox box, double room) => _Band.layout(
      box,
      width: room,
      containerWidth: width,
      environment: environment,
      listItem: listItem,
      nested: nested,
    );

    if (exclusions == null || exclusions.isEmpty || box.text.isEmpty) {
      final band = layOut(box, width);
      return ParagraphLayout._(box, width, [
        _PlacedBand(
          band,
          from: 0,
          to: box.text.length,
          dx: 0,
          dy: 0,
          firstLine: 0,
          lineCount: band.lines.length,
        ),
      ]);
    }
    // Less room than this beside the floats takes no text: the lines
    // move down below them, as a browser's do when a word does not fit.
    final minWidth = box.style.fontSize * 2;
    final bands = <_PlacedBand>[];
    var from = 0;
    var y = 0.0;
    var line = 0;
    while (true) {
      final (:left, :right) = exclusions.insetsAt(y, width);
      final change = exclusions.nextChange(y);
      final room = width - left - right;
      if (change != null && room < minWidth) {
        y = change;
        continue;
      }
      final band = layOut(box.tail(from), room < 1 ? 1 : room);
      var used = band.lines.length;
      if (change != null) {
        used = 0;
        while (used < band.lines.length && y + band.lineTop(used) < change) {
          used++;
        }
      }
      final to = used < band.lines.length
          ? from + band.lineStart(used)
          : box.text.length;
      if (to <= from && used < band.lines.length) {
        // No text fits on the lines beside the floats: none is taken.
        band.dispose();
        y = change!;
        continue;
      }
      bands.add(
        _PlacedBand(
          band,
          from: from,
          to: to,
          dx: left,
          dy: y,
          firstLine: line,
          lineCount: used,
        ),
      );
      if (to >= box.text.length) break;
      y += band.lineTop(used);
      line += used;
      from = to;
    }
    return ParagraphLayout._(box, width, bands);
  }

  final ParagraphBox box;
  final List<_PlacedBand> _bands;

  /// The width the paragraph was laid out at.
  final double width;

  /// Images, raised text and inline blocks where the lines put them.
  final List<PlacedAtomic> atomics;
  final List<ui.LineMetrics> lines;
  final List<double> _lineTops;

  static List<ui.LineMetrics> _linesOf(List<_PlacedBand> bands) {
    if (bands.length == 1 && bands.single.isWhole) {
      return bands.single.band.lines;
    }
    return [
      for (final placed in bands)
        for (var i = 0; i < placed.lineCount; i++)
          _shiftedLine(
            placed.band.lines[i],
            placed.offset,
            placed.firstLine + i,
          ),
    ];
  }

  static ui.LineMetrics _shiftedLine(
    ui.LineMetrics line,
    Offset by,
    int lineNumber,
  ) => ui.LineMetrics(
    hardBreak: line.hardBreak,
    ascent: line.ascent,
    descent: line.descent,
    unscaledAscent: line.unscaledAscent,
    height: line.height,
    width: line.width,
    left: line.left + by.dx,
    baseline: line.baseline + by.dy,
    lineNumber: lineNumber,
  );

  static List<double> _lineTopsOf(List<_PlacedBand> bands) => [
    for (final placed in bands)
      for (var i = 0; i < placed.lineCount; i++)
        placed.dy + placed.band.lineTop(i),
    bands.last.dy + bands.last.height,
  ];

  /// The bands' atomics on their lines, as the paragraph's own.
  static List<PlacedAtomic> _atomicsOf(
    ParagraphBox box,
    List<_PlacedBand> bands,
  ) {
    if (bands.length == 1 && bands.single.isWhole) {
      return bands.single.band.atomics;
    }
    final out = <PlacedAtomic>[];
    var index = 0;
    for (final placed in bands) {
      while (index < box.atomics.length &&
          box.atomics[index].offset < placed.from) {
        index++;
      }
      for (final atomic in placed.band.atomics) {
        if (placed.from + atomic.atomic.offset >= placed.to) break;
        out.add(
          PlacedAtomic(
            box.atomics[index++],
            atomic.rect.shift(placed.offset),
            text: atomic.text,
            textAt: atomic.textAt,
            math: atomic.math,
          ),
        );
      }
    }
    return out;
  }

  double get height => _lineTops.last;

  /// The widest line, for shrink-to-fit boxes.
  double get longestLine {
    var longest = 0.0;
    for (final placed in _bands) {
      final right = placed.dx + placed.band.longestLine;
      if (right > longest) longest = right;
    }
    return longest;
  }

  /// The widest word (CSS's min-content width) and the text on one line
  /// (max-content), whatever width it was laid out at: table columns.
  double get minIntrinsicWidth => _bands.first.band.minIntrinsicWidth;
  double get maxIntrinsicWidth => _bands.first.band.maxIntrinsicWidth;

  /// The top of line [index], or the paragraph's height for
  /// `lines.length`. A line spans from its top to the next one's.
  double lineTop(int index) => _lineTops[index];

  /// The alphabetic baseline of the first line.
  double get firstBaseline => lines.isEmpty ? 0 : lines.first.baseline;

  /// The band holding text offset [offset]: at a band's end, the next
  /// one, whose first line starts there.
  _PlacedBand _bandAt(int offset) {
    for (final placed in _bands) {
      if (offset < placed.to) return placed;
    }
    return _bands.last;
  }

  /// The band whose lines are at [y], clamped to the first and last.
  _PlacedBand _bandAtY(double y) {
    for (final placed in _bands) {
      if (y < placed.dy + placed.height) return placed;
    }
    return _bands.last;
  }

  /// The line holding text offset [offset].
  int lineAt(int offset) {
    final placed = _bandAt(offset);
    final line = placed.band.lineAt(offset - placed.from);
    return placed.firstLine +
        (line < placed.lineCount ? line : placed.lineCount - 1);
  }

  /// The line at [y] from the paragraph's top, clamped to the lines.
  int lineAtY(double y) => _lineAtY(_lineTops, lines.length, y);

  /// The text offset line [line] starts at.
  int lineStart(int line) {
    for (final placed in _bands) {
      if (line < placed.firstLine + placed.lineCount) {
        return placed.from + placed.band.lineStart(line - placed.firstLine);
      }
    }
    return box.text.length;
  }

  /// The text offset under [position], relative to the paragraph.
  TextPosition positionAt(Offset position) {
    final placed = _bandAtY(position.dy);
    final p = placed.band.positionAt(position - placed.offset);
    return TextPosition(
      offset: (placed.from + p.offset).clamp(placed.from, placed.to),
      affinity: p.affinity,
    );
  }

  /// The boxes covering text range `[start, end)`; with
  /// [ui.BoxHeightStyle.max] each spans its whole line.
  List<TextBox> boxesFor(
    int start,
    int end, {
    ui.BoxHeightStyle heightStyle = ui.BoxHeightStyle.tight,
  }) {
    if (_bands.length == 1 && _bands.single.isWhole) {
      return _bands.single.band.boxesFor(start, end, heightStyle);
    }
    return [
      for (final placed in _bands)
        if (start < placed.to && end > placed.from)
          for (final b in placed.band.boxesFor(
            (start > placed.from ? start : placed.from) - placed.from,
            (end < placed.to ? end : placed.to) - placed.from,
            heightStyle,
          ))
            TextBox.fromLTRBD(
              b.left + placed.dx,
              b.top + placed.dy,
              b.right + placed.dx,
              b.bottom + placed.dy,
              b.direction,
            ),
    ];
  }

  /// The bottom of the caret before text offset [offset]: where a
  /// selection handle hangs.
  Offset caretBottom(int offset) {
    final placed = _bandAt(offset);
    return placed.band.caretBottom(offset - placed.from) + placed.offset;
  }

  /// The height of the caret before text offset [offset].
  double caretHeight(int offset) {
    final placed = _bandAt(offset);
    return placed.band.caretHeight(offset - placed.from);
  }

  /// Whether the soft hyphen at text offset [offset] breaks a line and
  /// shows as a hyphen.
  bool showsHyphenAt(int offset) {
    final placed = _bandAt(offset);
    return placed.band.showsHyphenAt(offset - placed.from);
  }

  /// The word around text offset [offset]; a word hyphenated across
  /// lines is one word.
  TextRange wordAt(int offset) {
    TextRange at(int offset) {
      final placed = _bandAt(offset);
      final range = placed.band.wordBoundary(offset - placed.from);
      return TextRange(
        start: placed.from + range.start,
        end: placed.from + range.end,
      );
    }

    var word = at(offset);
    // The hyphen shown at a line end splits the painter's word.
    while (word.end < box.text.length && showsHyphenAt(word.end)) {
      word = TextRange(start: word.start, end: at(word.end + 1).end);
    }
    while (word.start > 0 && showsHyphenAt(word.start - 1)) {
      word = TextRange(start: at(word.start - 2).start, end: word.end);
    }
    return word;
  }

  /// Paints the backgrounds and borders of the paragraph's inline
  /// elements at [offset] (then those inside its raised text): before
  /// highlights and [paint], so both stay on top.
  void paintDecorations(Canvas canvas, Offset offset) {
    for (final fragment in _decorationFragments) {
      paintColumnDecoration(canvas, fragment.at(fragment.rect.shift(offset)));
    }
    for (final atomic in atomics) {
      if (atomic.atomic
          case InlineBox(:final style) ||
              InlineText(isInlineBlock: true, :final style)) {
        paintColumnDecoration(
          canvas,
          _inlineBoxDecoration(style, atomic.rect.shift(offset)),
        );
      }
      atomic.text?.paintDecorations(canvas, offset + atomic.textOffset);
    }
  }

  /// The paragraph's images, those of its raised text and inline blocks
  /// too, where they are relative to its top left: the caller draws
  /// them.
  Iterable<({String src, Rect rect})> get images sync* {
    for (final atomic in atomics) {
      if (atomic.atomic case InlineImage(:final src)) {
        yield (src: src, rect: atomic.rect);
      }
      final text = atomic.text;
      if (text == null) continue;
      for (final image in text.images) {
        yield (src: image.src, rect: image.rect.shift(atomic.textOffset));
      }
    }
  }

  /// An inline block's background and borders inside its margins.
  ColumnDecoration _inlineBoxDecoration(ComputedStyle s, Rect marginBox) {
    double px(CssLength? length) =>
        length == null ? 0 : InlineStyler.px(length, width);
    return ColumnDecoration(
      rect: Rect.fromLTRB(
        marginBox.left + px(s.margin.left),
        marginBox.top + px(s.margin.top),
        marginBox.right - px(s.margin.right),
        marginBox.bottom - px(s.margin.bottom),
      ),
      background: s.backgroundColor,
      borderWidth: s.borderWidth,
      borderStyle: s.borderStyle,
      borderColor: s.borderColor,
      radius: s.borderRadius,
    );
  }

  /// [box]'s inline decorations as drawn, relative to the paragraph,
  /// one per line each spans: around its text on that line (the content
  /// area, from the font's ascent to its descent) and the padding and
  /// border off it; the start edge only on its first line and the end
  /// edge on its last, as CSS slices an inline box.
  List<ColumnDecoration> get inlineDecorations => _decorationFragments;

  late final List<ColumnDecoration> _decorationFragments = [
    for (final decoration in box.decorations) ..._fragmentsOf(decoration),
  ];

  List<ColumnDecoration> _fragmentsOf(InlineDecoration decoration) {
    final boxes = boxesFor(decoration.start, decoration.end);
    if (boxes.isEmpty) return const [];
    final byLine = <int, Rect>{};
    for (final b in boxes) {
      final rect = b.toRect();
      final line = _lineWithBaselineIn(lines, rect.top, rect.bottom);
      if (line < 0) continue;
      final known = byLine[line];
      // A spacer is a line's height of nothing: it widens, never heightens.
      final grown = known == null
          ? rect
          : rect.height == 0
          ? Rect.fromLTRB(
              rect.left < known.left ? rect.left : known.left,
              known.top,
              rect.right > known.right ? rect.right : known.right,
              known.bottom,
            )
          : known.height == 0
          ? Rect.fromLTRB(
              rect.left < known.left ? rect.left : known.left,
              rect.top,
              rect.right > known.right ? rect.right : known.right,
              rect.bottom,
            )
          : known.expandToInclude(rect);
      byLine[line] = grown;
    }
    if (byLine.isEmpty) return const [];
    final s = decoration.style;
    final rtl = s.direction == CssDirection.rtl;
    double px(CssLength? length) =>
        length == null ? 0 : InlineStyler.px(length, width);
    final padding = CssEdges(
      px(s.padding.top),
      px(s.padding.right),
      px(s.padding.bottom),
      px(s.padding.left),
    );
    final first = byLine.keys.reduce((a, b) => a < b ? a : b);
    final last = byLine.keys.reduce((a, b) => a > b ? a : b);
    final w = s.borderWidth;
    final fragments = <ColumnDecoration>[];
    for (final MapEntry(key: line, value: rect) in byLine.entries) {
      final leftEnd = rtl ? line == last : line == first;
      final rightEnd = rtl ? line == first : line == last;
      // The spacers hold the margin too; the box starts after it.
      final left = rect.left + (leftEnd ? px(s.margin.left) : 0);
      final right = rect.right - (rightEnd ? px(s.margin.right) : 0);
      fragments.add(
        ColumnDecoration(
          rect: Rect.fromLTRB(
            left,
            rect.top - padding.top - w.top,
            right,
            rect.bottom + padding.bottom + w.bottom,
          ),
          background: s.backgroundColor,
          borderWidth: CssEdges(
            w.top,
            rightEnd ? w.right : 0,
            w.bottom,
            leftEnd ? w.left : 0,
          ),
          borderStyle: s.borderStyle,
          borderColor: s.borderColor,
          radius: CssCorners(
            leftEnd ? s.borderRadius.topLeft : CssRadius.zero,
            rightEnd ? s.borderRadius.topRight : CssRadius.zero,
            rightEnd ? s.borderRadius.bottomRight : CssRadius.zero,
            leftEnd ? s.borderRadius.bottomLeft : CssRadius.zero,
          ),
        ),
      );
    }
    return fragments;
  }

  /// Paints the text and raised text at [offset]; images are the
  /// caller's ([atomics] says where).
  void paint(Canvas canvas, Offset offset) {
    for (final (index, placed) in _bands.indexed) {
      final last = index == _bands.length - 1;
      if (last) {
        placed.band.paint(canvas, offset + placed.offset);
        continue;
      }
      // The band's painter goes on past its lines: they end here.
      canvas
        ..save()
        ..clipRect(
          Rect.fromLTRB(
            -_unbounded,
            -_unbounded,
            _unbounded,
            offset.dy + placed.dy + placed.height,
          ),
        );
      placed.band.paint(canvas, offset + placed.offset);
      canvas.restore();
    }
  }

  /// Far enough for any clip edge that should not cut: Skia ignores a
  /// clip with infinite edges.
  static const _unbounded = 1e9;

  void dispose() {
    for (final placed in _bands) {
      placed.band.dispose();
    }
  }

  /// The placeholder size of [atomic] and, for raised text, its layout.
  static _Measured _measure(
    InlineAtomic atomic,
    double width,
    TextLayoutEnvironment environment, {
    required double containerWidth,
  }) {
    switch (atomic) {
      case InlineImage():
        final size = imageSize(
          atomic.style,
          environment.imageSize(atomic.src),
          maxWidth: width,
          maxHeight: environment.maxImageHeight,
        );
        final alignment = switch (atomic.style.verticalAlign) {
          CssVerticalAlign.middle => ui.PlaceholderAlignment.middle,
          CssVerticalAlign.top ||
          CssVerticalAlign.textTop => ui.PlaceholderAlignment.top,
          CssVerticalAlign.bottom ||
          CssVerticalAlign.textBottom => ui.PlaceholderAlignment.bottom,
          _ => ui.PlaceholderAlignment.baseline,
        };
        return (
          dims: PlaceholderDimensions(
            size: size,
            alignment: alignment,
            baseline: TextBaseline.alphabetic,
            baselineOffset: size.height,
          ),
          text: null,
          textAt: Offset.zero,
          math: null,
        );
      case InlineBox(:final style):
        final size = _inlineBoxSize(style, width);
        return (
          dims: PlaceholderDimensions(
            size: size,
            alignment: ui.PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            baselineOffset: size.height,
          ),
          text: null,
          textAt: Offset.zero,
          math: null,
        );
      case InlineSpacer(:final style, :final isStart):
        return (
          dims: PlaceholderDimensions(
            size: Size(_spacerWidth(style, width, isStart: isStart), 0),
            alignment: ui.PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            baselineOffset: 0,
          ),
          text: null,
          textAt: Offset.zero,
          math: null,
        );
      case InlineMath(:final math, :final style):
        final layout = MathLayout.layout(
          math,
          environment.styler.textStyle(style, style, prose: false),
          display: style.display.isBlockLevel,
          textScaler: environment.textScaler,
        );
        return (
          dims: PlaceholderDimensions(
            size: Size(layout.width, layout.height),
            alignment: ui.PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            baselineOffset: layout.ascent,
          ),
          text: null,
          textAt: Offset.zero,
          math: layout,
        );
      case InlineText(isInlineBlock: true):
        return _measureInlineBlock(
          atomic,
          width,
          environment,
          containerWidth: containerWidth,
        );
      case InlineText():
        final text = ParagraphLayout.layout(
          atomic.paragraph,
          width: width,
          environment: environment,
          nested: true,
        );
        return (
          dims: PlaceholderDimensions(
            size: Size(text.longestLine, text.height),
            alignment: ui.PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            baselineOffset: text.firstBaseline + _raise(atomic),
          ),
          text: text,
          textAt: Offset.zero,
          math: null,
        );
    }
  }

  /// How far `vertical-align` lifts raised text or an inline block off
  /// the baseline: `super` and `sub` by the parent's font size, a length
  /// (percentages of the line height).
  static double _raise(InlineText atomic) {
    final style = atomic.style;
    return switch (style.verticalAlign) {
      CssVerticalAlign.sup => atomic.parentFontSize / 3 + 1,
      CssVerticalAlign.sub => -(atomic.parentFontSize / 5 + 1),
      CssVerticalAlign.length => InlineStyler.px(
        style.verticalAlignLength!,
        style.lineHeight.resolve(style.fontSize),
      ),
      // Moved by `position: relative` alone: placed after layout.
      _ => 0.0,
    };
  }

  /// An inline block (CSS 2.1 §10.3.9, §10.8.1): its content laid out at
  /// its width (or shrunk to fit inside the line, [width] wide), as tall
  /// as its content (or its height), inside its padding, border and
  /// margins (percentages of [containerWidth], the paragraph's); its
  /// baseline is its last line's, moved by `vertical-align`, or its edge
  /// for `middle`, `top` and `bottom`.
  static _Measured _measureInlineBlock(
    InlineText atomic,
    double width,
    TextLayoutEnvironment environment, {
    required double containerWidth,
  }) {
    final s = atomic.style;
    double px(CssLength? length) =>
        length == null ? 0 : InlineStyler.px(length, containerWidth);
    final w = s.borderWidth;
    final left = px(s.margin.left) + w.left + px(s.padding.left);
    final right = px(s.margin.right) + w.right + px(s.padding.right);
    final top = px(s.margin.top) + w.top + px(s.padding.top);
    final bottom = px(s.margin.bottom) + w.bottom + px(s.padding.bottom);
    final sizing = s.boxSizing == CssBoxSizing.borderBox;
    final framesX = w.left + w.right + px(s.padding.left) + px(s.padding.right);
    final framesY = w.top + w.bottom + px(s.padding.top) + px(s.padding.bottom);
    final setWidth = s.width == null
        ? null
        : px(s.width) - (sizing ? framesX : 0);
    final room = width - left - right;
    final text = setWidth == null
        ? ParagraphLayout.layout(
            atomic.paragraph,
            width: room < 1 ? 1 : room,
            environment: environment,
            nested: true,
          )
        : ParagraphLayout.layout(
            atomic.paragraph,
            width: setWidth < 1 ? 1 : setWidth,
            environment: environment,
          );
    final contentWidth = setWidth ?? text.longestLine;
    final setHeight = s.height == null || s.height!.hasPercent
        ? null
        : px(s.height) - (sizing ? framesY : 0);
    final contentHeight = setHeight ?? text.height;
    final size = Size(
      left + (contentWidth < 0 ? 0 : contentWidth) + right,
      top + (contentHeight < 0 ? 0 : contentHeight) + bottom,
    );
    final alignment = switch (s.verticalAlign) {
      CssVerticalAlign.middle => ui.PlaceholderAlignment.middle,
      CssVerticalAlign.top ||
      CssVerticalAlign.textTop => ui.PlaceholderAlignment.top,
      CssVerticalAlign.bottom ||
      CssVerticalAlign.textBottom => ui.PlaceholderAlignment.bottom,
      _ => ui.PlaceholderAlignment.baseline,
    };
    final lastBaseline = text.lines.isEmpty
        ? contentHeight
        : text.lines.last.baseline;
    return (
      dims: PlaceholderDimensions(
        size: size,
        alignment: alignment,
        baseline: TextBaseline.alphabetic,
        baselineOffset: top + lastBaseline + _raise(atomic),
      ),
      text: text,
      textAt: Offset(left, top),
      math: null,
    );
  }

  /// An empty inline block's margin box: its width and height (or none)
  /// with its padding, border and margins, percentages of [width].
  static Size _inlineBoxSize(ComputedStyle s, double width) {
    double px(CssLength? length) =>
        length == null ? 0 : InlineStyler.px(length, width);
    final w = s.borderWidth;
    final edgesX = px(s.padding.left) + px(s.padding.right) + w.left + w.right;
    final edgesY = px(s.padding.top) + px(s.padding.bottom) + w.top + w.bottom;
    final border = s.boxSizing == CssBoxSizing.borderBox;
    final contentWidth = s.width == null
        ? 0.0
        : px(s.width) - (border ? edgesX : 0);
    final contentHeight = s.height == null || s.height!.hasPercent
        ? 0.0
        : px(s.height) - (border ? edgesY : 0);
    return Size(
      (contentWidth < 0 ? 0 : contentWidth) +
          edgesX +
          px(s.margin.left) +
          px(s.margin.right),
      (contentHeight < 0 ? 0 : contentHeight) +
          edgesY +
          px(s.margin.top) +
          px(s.margin.bottom),
    );
  }

  /// The room [style]'s element takes in the line at its start (or end):
  /// margin, border and padding on that side, percentages of the
  /// paragraph's [width].
  static double _spacerWidth(
    ComputedStyle style,
    double width, {
    required bool isStart,
  }) {
    final left = isStart != (style.direction == CssDirection.rtl);
    double px(CssLength? length) =>
        length == null ? 0 : InlineStyler.px(length, width);
    final total = left
        ? px(style.margin.left) +
              style.borderWidth.left +
              px(style.padding.left)
        : px(style.margin.right) +
              style.borderWidth.right +
              px(style.padding.right);
    return total > 0 ? total : 0;
  }

  /// How far `position: relative` moves an inline element from where the
  /// line put it, without moving anything else: `top` over `bottom`,
  /// `left` over `right` (`right` over `left` in right-to-left text).
  /// Horizontal percentages are of the paragraph's [width]; vertical
  /// ones are of a height the paragraph does not have, so none.
  static Offset _relativeOffset(ComputedStyle style, double width) {
    if (style.position != CssPosition.relative) return Offset.zero;
    final o = style.offsets;
    double? px(CssLength? length, double percentOf) =>
        length == null ? null : InlineStyler.px(length, percentOf);
    final top = o.top == null || o.top!.hasPercent ? null : px(o.top, 0);
    final bottom = o.bottom == null || o.bottom!.hasPercent
        ? null
        : px(o.bottom, 0);
    final left = px(o.left, width);
    final right = px(o.right, width);
    final dx = style.direction == CssDirection.rtl
        ? (right != null ? -right : left ?? 0)
        : (left ?? (right != null ? -right : 0));
    return Offset(dx, top ?? (bottom != null ? -bottom : 0));
  }

  /// The size an image is drawn at: its CSS width and height (px, or a
  /// percentage of [maxWidth]), else its intrinsic size, keeping the
  /// ratio, then scaled down to fit [maxWidth] and [maxHeight] (the
  /// `max-width: 100%; max-height: 100%` foliate-js gives every image).
  /// An image of unknown size takes no room.
  static Size imageSize(
    ComputedStyle style,
    Size? intrinsic, {
    required double maxWidth,
    required double maxHeight,
  }) {
    final cssWidth = style.width == null
        ? null
        : InlineStyler.px(style.width!, maxWidth);
    final cssHeight = style.height == null || style.height!.hasPercent
        ? null
        : InlineStyler.px(style.height!, 0);
    final ratio = intrinsic == null || intrinsic.height == 0
        ? null
        : intrinsic.width / intrinsic.height;
    double? w;
    double? h;
    if (cssWidth != null && cssHeight != null) {
      w = cssWidth;
      h = cssHeight;
    } else if (cssWidth != null) {
      w = cssWidth;
      h = ratio == null ? null : cssWidth / ratio;
    } else if (cssHeight != null) {
      h = cssHeight;
      w = ratio == null ? null : cssHeight * ratio;
    } else if (intrinsic != null) {
      w = intrinsic.width;
      h = intrinsic.height;
    }
    if (w == null || h == null || w <= 0 || h <= 0) return Size.zero;
    final maxW = style.maxWidth == null
        ? maxWidth
        : InlineStyler.px(
            style.maxWidth!,
            maxWidth,
          ).clamp(0, maxWidth).toDouble();
    var scale = 1.0;
    if (w > maxW) scale = maxW / w;
    if (h * scale > maxHeight) scale = maxHeight / h;
    return Size(w * scale, h * scale);
  }
}

/// A placeholder in a [TextPainter]'s text: the indent, an image or
/// raised text. Its size comes from the dimensions set on the painter.
class _AtomicSpan extends PlaceholderSpan {
  const _AtomicSpan({required super.alignment, super.style})
    : super(baseline: TextBaseline.alphabetic);

  @override
  void build(
    ui.ParagraphBuilder builder, {
    TextScaler textScaler = TextScaler.noScaling,
    List<PlaceholderDimensions>? dimensions,
  }) {
    final dims = dimensions![builder.placeholderCount];
    final style = this.style;
    if (style != null) {
      builder.pushStyle(style.getTextStyle(textScaler: textScaler));
    }
    builder.addPlaceholder(
      dims.size.width,
      dims.size.height,
      alignment,
      baseline: dims.baseline,
      baselineOffset: dims.baselineOffset,
    );
    if (style != null) builder.pop();
  }

  @override
  bool visitChildren(InlineSpanVisitor visitor) => visitor(this);

  @override
  bool visitDirectChildren(InlineSpanVisitor visitor) => true;

  @override
  InlineSpan? getSpanForPositionVisitor(
    TextPosition position,
    Accumulator offset,
  ) {
    if (position.offset == offset.value) return this;
    offset.increment(1);
    return null;
  }

  @override
  int? codeUnitAtVisitor(int index, Accumulator offset) {
    final local = index - offset.value;
    offset.increment(1);
    return local == 0 ? PlaceholderSpan.placeholderCodeUnit : null;
  }

  /// [PlaceholderSpan] asserts in debug builds that only [WidgetSpan]s
  /// reach a painter, for the framework's own widgets; this one never
  /// reaches a `RichText`, and the dimensions it needs are always set.
  @override
  bool debugAssertIsValid() => true;

  @override
  RenderComparison compareTo(InlineSpan other) => identical(this, other)
      ? RenderComparison.identical
      : RenderComparison.layout;
}
