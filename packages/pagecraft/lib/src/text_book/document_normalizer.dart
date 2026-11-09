/// Section normalization based on the former WebView reader's
/// `readflex_document_normalizer.js`: missing language and direction
/// attributes on the root/body, and a class on blocks
/// that look like code, which the reader's style sheet treats as code.
/// Both go into the document's added attributes, so text, ids and CFIs
/// stay the book's. Pure Dart.
library;

import '../css/computed_style.dart';
import '../css/style_resolver.dart';
import '../document/content_document.dart';
import 'reading_direction.dart';

/// The class the reader's style sheet styles code blocks by.
const codeBlockClass = 'readflex-code-block';

/// Gives the root element the book's [language] unless it declares one,
/// and, outside the legacy `zh`, `ja` and `kr` language tags, a direction
/// unless the root or body declares one: right to left for a right-to-left
/// language or mostly right-to-left text, following the former reader's
/// `normalizeDocumentLanguageAndDirection`.
void normalizeLanguageAndDirection(ContentDocument doc, {String? language}) {
  const root = ContentDocument.rootIndex;
  final canonical = _canonicalLanguage(language);
  if (canonical != null && (doc.attributeOf(root, 'lang') ?? '').isEmpty) {
    doc.addAttributeIfAbsent(root, 'lang', canonical);
  }
  final primary = canonical?.split('-').first;
  // foliate-js's list, `kr` and all.
  if (primary == 'zh' || primary == 'ja' || primary == 'kr') return;
  final body = _body(doc);
  final explicit = [
    doc.attributeOf(root, 'dir'),
    if (body != null) doc.attributeOf(body, 'dir'),
  ].firstWhere((d) => d != null && d.isNotEmpty, orElse: () => null);
  final languageDirection = primary == null
      ? null
      : isRtlLanguage(primary)
      ? 'rtl'
      : 'ltr';
  final direction =
      explicit ??
      (languageDirection == 'rtl' ? 'rtl' : _inferredDirection(doc, body)) ??
      languageDirection;
  if (direction == null || direction.isEmpty) return;
  doc.addAttributeIfAbsent(root, 'dir', direction);
  if (body != null) doc.addAttributeIfAbsent(body, 'dir', direction);
}

/// Marks blocks that look like code with [codeBlockClass], as the
/// former reader's `normalizeCodeLikeBlocks` did after the book's styles
/// apply: a `div`, `p`, `section`, `article` or `li` of at least 80
/// characters, not inside `pre` or a marked block nor itself a caption
/// of one, shown as a block, whose class or id says code, or whose font
/// is monospace and that keeps its whitespace or reads like code.
/// Returns whether anything was marked (the styles then need resolving
/// again).
bool markCodeLikeBlocks(ContentDocument doc, ComputedStyles styles) {
  var marked = false;
  for (var node = 0; node < doc.nodeCount; node++) {
    if (!doc.isElement(node)) continue;
    if (!_candidates.contains(doc.localNameOf(node).toLowerCase())) continue;
    if (_insideCodeOrPre(doc, node)) continue;
    final classAndId =
        '${doc.attributeOf(node, 'class') ?? ''} ${doc.idOf(node) ?? ''}';
    if (_codeDescriptionClass.hasMatch(
      classAndId.replaceAllMapped(_camelCase, (m) => '${m[1]}-${m[2]}'),
    )) {
      continue;
    }
    final text = doc.textContentOf(node).trim();
    if (text.length < _minimumTextLength) continue;
    final style = styles[node];
    if (!_isBlockish(style.display)) continue;
    final codeClass = _hasCodeClass(classAndId);
    final monospace = _monospaceFont.hasMatch(style.fontFamily.join(', '));
    // `/pre|nowrap/`: every value but normal.
    final keepsWhitespace = style.whiteSpace != CssWhiteSpace.normal;
    if (codeClass ||
        (monospace && (keepsWhitespace || _codeText.hasMatch(text)))) {
      doc.addClass(node, codeBlockClass);
      marked = true;
    }
  }
  return marked;
}

const _candidates = {'div', 'p', 'section', 'article', 'li'};
const _minimumTextLength = 80;

final _codeBlockClassPattern = RegExp(
  r'(?:^|[-_\s])(?:programcode|paratypeprogramcode|programlisting|screen|sourcecode|source|codeblock|listing|literal|literallayout|verbatim|console|terminal|cmd|shell|highlight|hljs)(?:$|[-_\s])',
  caseSensitive: false,
);
final _codeClassFragment = RegExp(
  r'(?:program|source|sample|example|syntax|highlight)?code(?:block|listing|sample|example|snippet|source|area|container|fragment|line|text)?',
  caseSensitive: false,
);
final _nonCodeClassFragment = RegExp(
  r'(?:decode|encode|unicode|barcode|postcode|zipcode|classificationcode)',
  caseSensitive: false,
);
final _codeDescriptionClass = RegExp(
  r'(?:^|[-_\s])(?:annotations?|captions?|callouts?|descriptions?|explanations?|titles?)(?:$|[-_\s])',
  caseSensitive: false,
);
final _camelCase = RegExp('([a-z0-9])([A-Z])');
final _monospaceFont = RegExp(
  r'\b(?:mono|menlo|monaco|consolas|courier|source code|jetbrains|fira code|cascadia|ui-monospace)\b',
  caseSensitive: false,
);
final _codeText = RegExp(
  r'[{};<>]|(?:^|\s)(?:import|package|public|private|protected|class|interface|return|throw|new|if|else|for|while|try|catch|@Bean|@Configuration)\b',
);

bool _hasCodeClass(String classAndId) =>
    _codeBlockClassPattern.hasMatch(classAndId) ||
    classAndId
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .any(
          (t) =>
              _codeClassFragment.hasMatch(t) &&
              !_nonCodeClassFragment.hasMatch(t),
        );

/// `closest('pre, .readflex-code-block')`, the element itself included.
bool _insideCodeOrPre(ContentDocument doc, int node) {
  for (var e = node; e != ContentDocument.none; e = doc.parentOf(e)) {
    if (doc.localNameOf(e).toLowerCase() == 'pre') return true;
    final classes = doc.attributeOf(e, 'class');
    if (classes != null &&
        classes.split(RegExp(r'\s+')).contains(codeBlockClass)) {
      return true;
    }
  }
  return false;
}

/// `/block|flow-root|list-item|table/` on the computed display.
bool _isBlockish(CssDisplay display) => switch (display) {
  CssDisplay.inline ||
  CssDisplay.none ||
  CssDisplay.contents ||
  CssDisplay.ruby ||
  CssDisplay.rubyBase ||
  CssDisplay.rubyText => false,
  _ => true,
};

int? _body(ContentDocument doc) {
  for (final child in doc.childrenOf(ContentDocument.rootIndex)) {
    if (doc.isElement(child) &&
        doc.localNameOf(child).toLowerCase() == 'body') {
      return child;
    }
  }
  return null;
}

/// `rtl` when the first 5000 characters of the body's text have more
/// right-to-left letters than Latin ones, else null.
String? _inferredDirection(ContentDocument doc, int? body) {
  if (body == null) return null;
  final sample = doc.textContentOf(body).replaceAll(RegExp(r'\s+'), ' ');
  final text = sample.length > 5000 ? sample.substring(0, 5000) : sample;
  if (text.trim().isEmpty) return null;
  final counts = directionCharacterCounts(text);
  return counts.rtl > counts.ltr ? 'rtl' : null;
}

/// The language tag with its subtags' conventional case (`en-US`,
/// `zh-Hant-TW`), as `Intl.getCanonicalLocales` gives it; null for none.
String? _canonicalLanguage(String? language) {
  final tag = language?.trim().replaceAll('_', '-');
  if (tag == null || tag.isEmpty) return null;
  final parts = tag.split('-');
  return [
    parts.first.toLowerCase(),
    for (final part in parts.skip(1))
      if (part.length == 4)
        '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}'
      else if (part.length == 2)
        part.toUpperCase()
      else
        part.toLowerCase(),
  ].join('-');
}
