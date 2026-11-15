import 'package:component_library/component_library.dart';
import 'package:material_ui/material_ui.dart';

import 'source_syntax.dart';
import 'text_window.dart';

/// Token boundaries and search ranges share one text stream. Search keeps its
/// own background and the current match remains readable over syntax colours.
TextSpan sourceSpans(
  BuildContext context,
  String text,
  TextStyle style,
  List<SourceToken> tokens,
  List<ViewerMatch> matches,
  ViewerMatch? current, {
  int sourceOffset = 0,
}) {
  final colors = context.appColors;
  final sourceEnd = sourceOffset + text.length;
  final cuts = <int>{0, text.length};
  var t = _firstEndingAfter(tokens, (token) => token.end, sourceOffset);
  var m = _firstEndingAfter(matches, (match) => match.end, sourceOffset);
  for (var i = t; i < tokens.length && tokens[i].start < sourceEnd; i++) {
    cuts.add((tokens[i].start - sourceOffset).clamp(0, text.length));
    cuts.add((tokens[i].end - sourceOffset).clamp(0, text.length));
  }
  for (var i = m; i < matches.length && matches[i].start < sourceEnd; i++) {
    cuts.add((matches[i].start - sourceOffset).clamp(0, text.length));
    cuts.add((matches[i].end - sourceOffset).clamp(0, text.length));
  }
  final points = cuts.toList()..sort();
  final spans = <TextSpan>[];
  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    final sourceStart = sourceOffset + start;
    while (t < tokens.length && tokens[t].end <= sourceStart) {
      t++;
    }
    while (m < matches.length && matches[m].end <= sourceStart) {
      m++;
    }
    final scope = t < tokens.length && tokens[t].start <= sourceStart
        ? tokens[t].scope.split('.').first
        : '';
    var ink = switch (scope) {
      'keyword' || 'selector-tag' => colors.ink(5),
      'string' || 'regexp' || 'addition' => colors.ink(3),
      'number' || 'literal' || 'symbol' => colors.ink(1),
      'type' || 'built_in' || 'title' || 'attr' || 'attribute' => colors.link,
      'comment' || 'quote' => colors.textMuted,
      'deletion' => colors.danger,
      _ => style.color,
    };
    Color? background;
    if (m < matches.length && matches[m].start <= sourceStart) {
      final active = matches[m] == current;
      background = active ? colors.accent : colors.highlight;
      if (active) ink = colors.onAccent;
    }
    spans.add(
      TextSpan(
        text: text.substring(start, end),
        style: style.copyWith(color: ink, backgroundColor: background),
      ),
    );
  }
  return TextSpan(style: style, children: spans);
}

// Source tokens and non-overlapping search matches are ordered. A fragment
// near the end of a minified line must not walk all earlier ranges per frame.
int _firstEndingAfter<T>(List<T> ranges, int Function(T) endOf, int offset) {
  var low = 0;
  var high = ranges.length;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    if (endOf(ranges[mid]) <= offset) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}
