import 'dart:math' as math;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:pagecraft/pagecraft.dart';

class MarkupSearchResult {
  const MarkupSearchResult(this.html, this.excerpts);
  final String html;
  final List<String> excerpts;
}

/// Search visible text across inline markup, preserving the document's nodes.
MarkupSearchResult searchMarkup((String, String) input) {
  final (source, query) = input;
  if (query.isEmpty) return MarkupSearchResult(source, const []);
  final root = html.parseFragment(source);
  final nodes = <(dom.Text, int)>[];
  final text = StringBuffer();
  const blocks = {
    'p',
    'div',
    'li',
    'tr',
    'td',
    'th',
    'h1',
    'h2',
    'h3',
    'h4',
    'pre',
    'br',
    'section',
    'article',
  };
  void visit(dom.Node node) {
    if (node is dom.Text) {
      nodes.add((node, text.length));
      text.write(node.data);
      return;
    }
    if (node is dom.Element &&
        const {'script', 'style', 'template'}.contains(node.localName)) {
      return;
    }
    final block = node is dom.Element && blocks.contains(node.localName);
    if (block) text.write(' ');
    for (final child in node.nodes) {
      visit(child);
    }
    if (block) text.write(' ');
  }

  visit(root);
  // One extra result lets the host report truncation explicitly.
  final matches = searchText(
    text.toString(),
    query,
    maxMatches: 1001,
  ).take(1001).toList();
  var lastEnd = -1;
  matches.removeWhere((match) {
    if (match.start < lastEnd) return true;
    lastEnd = match.end;
    return false;
  });
  var firstMatch = 0;
  for (final (node, offset) in nodes) {
    final end = offset + node.data.length;
    while (firstMatch < matches.length && matches[firstMatch].end <= offset) {
      firstMatch++;
    }
    var at = 0;
    final replacement = <dom.Node>[];
    for (
      var i = firstMatch;
      i < matches.length && matches[i].start < end;
      i++
    ) {
      final match = matches[i];
      final start = math
          .max(at, match.start - offset)
          .clamp(0, node.data.length);
      final stop = (match.end - offset).clamp(start, node.data.length);
      if (start > at) replacement.add(dom.Text(node.data.substring(at, start)));
      if (stop > start) {
        replacement.add(
          dom.Element.tag('mark')
            ..attributes['id'] =
                'ferryx-find-$i-${offset <= match.start ? 'start' : 'part'}'
            ..nodes.add(dom.Text(node.data.substring(start, stop))),
        );
      }
      at = stop;
    }
    if (replacement.isEmpty) continue;
    if (at < node.data.length) {
      replacement.add(dom.Text(node.data.substring(at)));
    }
    final parent = node.parentNode!;
    final index = parent.nodes.indexOf(node);
    node.remove();
    parent.nodes.insertAll(index, replacement);
  }
  return MarkupSearchResult(root.outerHtml, [
    for (final match in matches) '${match.pre}${match.match}${match.post}',
  ]);
}
