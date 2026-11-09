import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../document/content_document.dart';
import '../formats/book_navigation.dart';
import 'article_anchor.dart';

/// An article as the reader saved it, made what the WebView article
/// shell showed: its HTML cleaned as the shell's DOMPurify call cleans it
/// (`articleContentFragment` in `readflex_content_security.js`), inside
/// the shell's `<main id="article-content">`.
///
/// Elements outside [_allowedTags] are unwrapped, their text kept, except
/// those whose content goes too ([_droppedWithContent]: scripts, styles,
/// media, SVG and MathML); attributes outside [_allowedAttributes] and
/// `data-*` go, as do `href`s with a script scheme; an image keeps its
/// `src` only when it is a file in the article's `images/` folder.
/// Comments go. What is left is the text the article's anchors count.
String articleDocumentHtml(String html) {
  final fragment = html_parser.parseFragment(html);
  _clean(fragment);
  final out = StringBuffer(
    '<!DOCTYPE html><html><head></head><body>'
    '<main id="${ArticleAnchor.contentId}">',
  );
  for (final node in fragment.nodes) {
    out.write(_outerHtml(node));
  }
  out.write('</main></body></html>');
  return out.toString();
}

const _allowedTags = {
  'p',
  'span',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'figure',
  'img',
  'figcaption',
  'ul',
  'ol',
  'li',
  'blockquote',
  'pre',
  'code',
  'em',
  'strong',
  'b',
  'i',
  'br',
  'hr',
  'a',
  'div',
  'table',
  'thead',
  'tbody',
  'tfoot',
  'tr',
  'th',
  'td',
  'caption',
  'kbd',
  'samp',
};

const _allowedAttributes = {
  'id',
  'alt',
  'title',
  'src',
  'href',
  'lang',
  'dir',
  'class',
  'colspan',
  'rowspan',
  'scope',
};

/// DOMPurify's `FORBID_CONTENTS`: elements dropped with what is in them.
const _droppedWithContent = {
  'annotation-xml',
  'audio',
  'colgroup',
  'desc',
  'foreignobject',
  'head',
  'iframe',
  'math',
  'mi',
  'mn',
  'mo',
  'ms',
  'mtext',
  'noembed',
  'noframes',
  'noscript',
  'plaintext',
  'script',
  'style',
  'svg',
  'template',
  'title',
  'video',
  'xmp',
};

final _dataAttribute = RegExp(r'^data-[\-\w.·-￿]+$');
final _safeUri = RegExp(
  r'^(?:(?:(?:f|ht)tps?|mailto|tel|callto|sms|cid|xmpp|matrix):|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))',
  caseSensitive: false,
);
final _localImage = RegExp(
  r'^images/[a-zA-Z0-9_-]+\.(?:png|jpe?g|gif|webp|avif)$',
);

void _clean(dom.Node parent) {
  for (final node in List.of(parent.nodes)) {
    switch (node) {
      case dom.Element():
        final name = node.localName?.toLowerCase() ?? '';
        if (_droppedWithContent.contains(name)) {
          node.remove();
          continue;
        }
        _clean(node);
        if (!_allowedTags.contains(name)) {
          // Unwrapped: its content takes its place.
          final index = parent.nodes.indexOf(node);
          final children = List.of(node.nodes);
          node.remove();
          parent.nodes.insertAll(index, children);
          continue;
        }
        node.attributes.removeWhere((key, value) {
          final attribute = key.toString().toLowerCase();
          if (_dataAttribute.hasMatch(attribute)) return false;
          if (!_allowedAttributes.contains(attribute)) return true;
          if (attribute == 'href' || attribute == 'src') {
            final uri = value.replaceAll(RegExp(r'[\u0000- ]'), '');
            if (!_safeUri.hasMatch(uri)) return true;
          }
          return false;
        });
        if (name == 'img' &&
            !_localImage.hasMatch(node.attributes['src'] ?? '')) {
          node.attributes.remove('src');
        }
      case dom.Text():
        break;
      default:
        node.remove();
    }
  }
}

String _outerHtml(dom.Node node) => switch (node) {
  dom.Element() => node.outerHtml,
  dom.Text() => _escape(node.text),
  _ => '',
};

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// The article's contents as the shell listed them: its headings with
/// an `id`, each at its level; without any, up to twelve of its blocks
/// with some text, spread over it, by their first words.
List<BookNavItem> articleToc(ContentDocument doc) {
  final content = doc.elementIndexById(ArticleAnchor.contentId);
  if (content == ContentDocument.none) return const [];
  final headings = <({String label, String href, int level})>[];
  final blocks = <int>[];
  for (final node in doc.descendantsOf(content)) {
    if (!doc.isElement(node)) continue;
    final name = doc.localNameOf(node).toLowerCase();
    final id = doc.attributeOf(node, 'id');
    final level = switch (name) {
      'h1' => 1,
      'h2' => 2,
      'h3' => 3,
      'h4' => 4,
      'h5' => 5,
      'h6' => 6,
      _ => null,
    };
    if (level != null && id != null && id.isNotEmpty) {
      final label = normalizeArticleText(textContentOf(doc, node));
      if (label.isNotEmpty) {
        headings.add((label: label, href: '#$id', level: level));
      }
    }
    if (doc.attributeOf(node, 'data-rf-block-id') != null &&
        id != null &&
        id.isNotEmpty &&
        normalizeArticleText(textContentOf(doc, node)).length >= 48) {
      blocks.add(node);
    }
  }
  if (headings.isNotEmpty) return _nested(headings);
  if (blocks.isEmpty) return const [];
  const maxItems = 12;
  final step = (blocks.length / maxItems).ceil().clamp(1, blocks.length);
  return [
    for (var i = 0; i < blocks.length; i += step)
      BookNavItem(
        label: _blockLabel(doc, blocks[i], i ~/ step),
        href: '#${doc.attributeOf(blocks[i], 'id')}',
      ),
  ];
}

/// Headings in order with their levels as a tree: each under the last
/// heading of a higher level before it.
List<BookNavItem> _nested(List<({String label, String href, int level})> list) {
  var index = 0;
  List<BookNavItem> under(int level) {
    final items = <BookNavItem>[];
    while (index < list.length && list[index].level > level) {
      final heading = list[index++];
      final children = under(heading.level);
      items.add(
        BookNavItem(
          label: heading.label,
          href: heading.href,
          subitems: children.isEmpty ? null : children,
        ),
      );
    }
    return items;
  }

  return under(0);
}

String _blockLabel(ContentDocument doc, int block, int index) {
  final text = normalizeArticleText(textContentOf(doc, block));
  if (text.isEmpty) return 'Section ${index + 1}';
  if (text.length <= 72) return text;
  final clipped = text.substring(0, 72).replaceFirst(RegExp(r'\s+\S*$'), '');
  return '${clipped.isEmpty ? text.substring(0, 72) : clipped}...';
}

/// The shell's layout of an article that does not change with the
/// reader's settings: pictures, figures, quotes, code and tables. The
/// text's font, size, spacing and colours are the reader's
/// (`BookStyle`), as for books.
const articleStyleSheet = '''
h1, h2, h3, h4, h5, h6 { line-height: 1.18; margin: 1.4em 0 0.55em; text-indent: 0; }
h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
img { display: block; max-width: 100%; height: auto; margin-left: auto; margin-right: auto; }
figure { margin: 1.1em 0; }
figcaption { margin-top: 0.55em; font-size: 0.9em; line-height: 1.35; text-align: center; }
blockquote { border-left: 3px solid currentColor; margin-left: 0; margin-right: 0; padding-left: 1em; text-indent: 0; }
pre, code, kbd, samp { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
pre { margin: 1em 0; padding: 0.85em 1em; white-space: pre-wrap; border-radius: 8px; text-align: start; text-indent: 0; }
pre code, pre kbd, pre samp { font-size: inherit; white-space: inherit; }
.rf-table-scroll { margin: 1em 0; }
table { width: 100%; border-collapse: collapse; font-size: 0.86em; line-height: 1.35; text-align: start; }
th, td { border: 1px solid currentColor; padding: 0.35em 0.5em; vertical-align: top; }
a { text-decoration: none; }
''';
