import 'package:flutter/widgets.dart';

/// One line of text that keeps its end when it is too long: the middle
/// gives way to an ellipsis, as Finder shortens a file name so that its
/// extension stays in view (`analysis_o…ions.yaml`).
///
/// [tail] is how many characters stay at the end; by default the
/// extension with a couple of characters before it, or the last three.
/// When not even the tail fits, the end is cut instead.
class AppMiddleEllipsis extends StatelessWidget {
  const AppMiddleEllipsis(
    this.text, {
    required this.style,
    this.tail,
    this.textAlign,
    super.key,
  });

  final String text;
  final TextStyle style;
  final int? tail;
  final TextAlign? textAlign;

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
      return Text(
        shown,
        style: style,
        textAlign: textAlign,
        maxLines: 1,
        softWrap: false,
        overflow: overflow,
      );
    },
  );

  /// The text to show in [maxWidth], and how its end is cut when even the
  /// tail does not fit.
  (String, TextOverflow) _fit(BuildContext context, double maxWidth) {
    if (!maxWidth.isFinite) return (text, TextOverflow.clip);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    try {
      if (painter.width <= maxWidth) return (text, TextOverflow.clip);
      final chars = text.characters.toList();
      final keep = (tail ?? defaultTail(text)).clamp(0, chars.length);
      final end = chars.sublist(chars.length - keep).join();
      double widthOf(int head) {
        painter.text = TextSpan(
          text: '${chars.sublist(0, head).join()}\u2026$end',
          style: style,
        );
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
      if (low == 0) return (text, TextOverflow.ellipsis);
      return ('${chars.sublist(0, low).join()}\u2026$end', TextOverflow.clip);
    } finally {
      painter.dispose();
    }
  }
}
