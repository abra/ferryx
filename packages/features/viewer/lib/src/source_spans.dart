import 'package:component_library/component_library.dart';
import 'package:flutter/material.dart';

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
  ViewerMatch? current,
) {
  final colors = context.appColors;
  final cuts = <int>{0, text.length};
  for (final token in tokens) {
    cuts.add(token.start.clamp(0, text.length));
    cuts.add(token.end.clamp(0, text.length));
  }
  for (final match in matches) {
    cuts.add(match.start.clamp(0, text.length));
    cuts.add(match.end.clamp(0, text.length));
  }
  final points = cuts.toList()..sort();
  final spans = <TextSpan>[];
  var t = 0;
  var m = 0;
  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    while (t < tokens.length && tokens[t].end <= start) {
      t++;
    }
    while (m < matches.length && matches[m].end <= start) {
      m++;
    }
    final scope = t < tokens.length && tokens[t].start <= start
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
    if (m < matches.length && matches[m].start <= start) {
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
