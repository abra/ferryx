import 'package:flutter/widgets.dart';

/// One line of text that keeps its end when it is too long: the middle
/// gives way to an ellipsis, as Finder shortens a file name so that its
/// extension stays in view (`analysis_o…ions.yaml`).
///
/// [tail] is how many characters stay at the end; by default the
/// extension with a couple of characters before it, or the last three.
/// When not even the tail fits, the end is cut instead. [highlights] are
/// ranges of [text] (`[start, end)` in code units, ordered) drawn in
/// [highlightStyle], as a search shows what matched; the part of a range
/// the ellipsis hides is dropped with it.
class AppMiddleEllipsis extends StatelessWidget {
  const AppMiddleEllipsis(
    this.text, {
    required this.style,
    this.tail,
    this.textAlign,
    this.highlights = const [],
    this.highlightStyle,
    super.key,
  });

  final String text;
  final TextStyle style;
  final int? tail;
  final TextAlign? textAlign;
  final List<(int, int)> highlights;

  /// Merged over [style] for the [highlights].
  final TextStyle? highlightStyle;

  /// The extension (with its dot) and two characters before it, at most
  /// a third of the name; three characters for a name without one.
  static int defaultTail(String name) {
    final chars = name.characters;
    final dot = name.lastIndexOf('.');
    final extension = dot > 0
        ? name.characters.length - name.substring(0, dot).characters.length
        : 0;
    final wanted = extension > 0 ? extension + 2 : 3;
    return wanted.clamp(1, (chars.length / 3).ceil().clamp(1, 1 << 20));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final (shown, overflow) = _fit(context, constraints.maxWidth);
      // Plain text unless something is highlighted: a `Text` with data.
      return _highlighted
          ? Text.rich(
              shown,
              style: style,
              textAlign: textAlign,
              maxLines: 1,
              softWrap: false,
              overflow: overflow,
            )
          : Text(
              shown.text!,
              style: style,
              textAlign: textAlign,
              maxLines: 1,
              softWrap: false,
              overflow: overflow,
            );
    },
  );

  bool get _highlighted => highlights.isNotEmpty && highlightStyle != null;

  /// [shown] as spans: the highlights, moved by where [shown] took its
  /// head (`[0, headLength)`) and its tail (from [tailStart] in [text],
  /// after the ellipsis).
  TextSpan _span(String shown, {int? headLength, int? tailStart}) {
    if (!_highlighted) return TextSpan(text: shown);
    final ranges = <(int, int)>[];
    for (final (start, end) in highlights) {
      if (headLength == null || tailStart == null) {
        ranges.add((start, end));
        continue;
      }
      if (start < headLength) ranges.add((start, end.clamp(0, headLength)));
      if (end > tailStart) {
        final shift = headLength + 1 - tailStart;
        ranges.add((start.clamp(tailStart, end) + shift, end + shift));
      }
    }
    final children = <TextSpan>[];
    var at = 0;
    for (final (rawStart, rawEnd) in ranges) {
      final start = rawStart.clamp(at, shown.length);
      final end = rawEnd.clamp(start, shown.length);
      if (end <= start) continue;
      if (start > at) children.add(TextSpan(text: shown.substring(at, start)));
      children.add(
        TextSpan(text: shown.substring(start, end), style: highlightStyle),
      );
      at = end;
    }
    if (at < shown.length) children.add(TextSpan(text: shown.substring(at)));
    return TextSpan(children: children);
  }

  /// The text to show in [maxWidth], and how its end is cut when even the
  /// tail does not fit.
  (TextSpan, TextOverflow) _fit(BuildContext context, double maxWidth) {
    final whole = _span(text);
    if (!maxWidth.isFinite) return (whole, TextOverflow.clip);
    final painter = TextPainter(
      text: TextSpan(style: style, children: [whole]),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    try {
      if (painter.width <= maxWidth) return (whole, TextOverflow.clip);
      final chars = text.characters.toList();
      final keep = (tail ?? defaultTail(text)).clamp(0, chars.length);
      final end = chars.sublist(chars.length - keep).join();
      final tailStart = text.length - end.length;
      TextSpan cut(int head) {
        final start = chars.sublist(0, head).join();
        return _span(
          '$start…$end',
          headLength: start.length,
          tailStart: tailStart,
        );
      }

      double widthOf(int head) {
        painter.text = TextSpan(style: style, children: [cut(head)]);
        painter.layout();
        return painter.width;
      }

      // The longest head that fits with the ellipsis and the tail.
      var low = 0;
      var high = chars.length - keep;
      while (low < high) {
        final mid = (low + high + 1) ~/ 2;
        if (widthOf(mid) <= maxWidth) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      if (low == 0) return (whole, TextOverflow.ellipsis);
      return (cut(low), TextOverflow.clip);
    } finally {
      painter.dispose();
    }
  }
}
