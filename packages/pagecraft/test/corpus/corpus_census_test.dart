import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagecraft/src/container/book_url.dart';
import 'package:pagecraft/all_formats.dart';

/// What the real books in `PAGECRAFT_CORPUS` ask of the engine that pagecraft
/// does not draw yet, and how often: the list the native reader's
/// coverage is planned from.
///
/// For every section of every EPUB, FB2 and MOBI, the census runs the
/// section's style sheets as pagecraft reads them and records:
///
/// - each declaration pagecraft drops (an unknown property or a value it
///   does not parse) with the number of elements it would have styled,
///   pseudo-elements (`::before`, `::first-letter` …) by their
///   originating elements;
/// - rules pagecraft skips or applies unconditionally: `@supports` blocks,
///   `@media` feature queries;
/// - layout pagecraft reads but does not draw yet, from its own cascade:
///   floats inside a line (other than images: they stay in it),
///   `inline-block` around block-level content (laid out as inline
///   content);
/// - markup without a box yet: ruby, media, embedded documents; and
///   fixed-layout or right-to-left books.
///
///     PAGECRAFT_CORPUS=~/Books PAGECRAFT_CENSUS_REPORT=census.md \
///         fvm flutter test test/corpus/corpus_census_test.dart
///
/// Skipped when `PAGECRAFT_CORPUS` is not set: the corpus is not in the repo.
void main() {
  final corpus = Platform.environment['PAGECRAFT_CORPUS'];
  if (corpus == null || corpus.isEmpty) {
    test(
      'corpus census',
      () {},
      skip: 'set PAGECRAFT_CORPUS to count features in real books',
    );
    return;
  }

  test('corpus census', () async {
    final census = _Census();
    final files =
        Directory(corpus)
            .listSync(followLinks: true)
            .whereType<File>()
            .where((f) => _isBook(f.path))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final name = file.path.split('/').last;
      final Object book;
      try {
        book = await _open(file.path);
      } on Exception catch (e) {
        census.failures[name] = '$e';
        continue;
      }
      final source = textBookSourceOf(book);
      try {
        await census.addBook(name, book, source);
      } finally {
        await source.close();
      }
    }
    final report = census.toMarkdown(files.length);
    // ignore: avoid_print
    print(report);
    final out = Platform.environment['PAGECRAFT_CENSUS_REPORT'];
    if (out != null && out.isNotEmpty) File(out).writeAsStringSync(report);
  }, timeout: const Timeout(Duration(minutes: 30)));
}

bool _isBook(String path) {
  final lower = path.toLowerCase();
  return const [
    '.epub',
    '.fb2',
    '.fb2.zip',
    '.fbz',
    '.mobi',
    '.azw3',
    '.azw',
  ].any(lower.endsWith);
}

Future<Object> _open(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.epub')) return EpubBook.open(path);
  if (lower.endsWith('.fb2') ||
      lower.endsWith('.fb2.zip') ||
      lower.endsWith('.fbz')) {
    return Fb2Book.open(path);
  }
  return MobiBook.open(path);
}

/// How often one feature occurs: in which books, in how many sections,
/// on how many elements.
class _Count {
  final books = <String>{};
  var sections = 0;
  var elements = 0;
}

class _Census {
  final counts = <String, _Count>{};

  /// Per dropped property: elements by value, for the report's detail.
  final values = <String, Map<String, int>>{};
  final failures = <String, String>{};
  var sections = 0;
  var books = 0;

  /// Per section: elements already counted for a key.
  final _seen = <String, Set<int>>{};

  void _record(String key, String book, Iterable<int> elements) {
    final seen = _seen.putIfAbsent(key, () => <int>{});
    final before = seen.length;
    seen.addAll(elements);
    final added = seen.length - before;
    if (added == 0) return;
    final count = counts.putIfAbsent(key, _Count.new);
    if (before == 0) count.sections++;
    count.books.add(book);
    count.elements += added;
  }

  Future<void> addBook(String name, Object book, TextBookSource source) async {
    books++;
    if (book is EpubBook) {
      if (book.isFixedLayout) _record('book: fixed layout', name, const [0]);
      if (book.resources.pageProgressionDirection == 'rtl') {
        _record('book: right-to-left spine', name, const [0]);
      }
    }
    _seen.clear();
    final cache = StyleSheetCache();
    for (var i = 0; i < source.sectionCount; i++) {
      final TextSection section;
      try {
        section = await source.section(i);
      } on Exception {
        continue;
      }
      sections++;
      _seen.clear();
      final doc = parseSectionDocument(
        section.text,
        mediaType: section.mediaType,
      );
      final sheets = [
        for (final css in source.defaultStyleSheets) CssStyleSheet.parse(css),
        ...await loadDocumentStyleSheets(
          doc,
          documentHref: section.href,
          read: source.readStyleSheet,
          cache: cache,
        ),
      ];
      for (final sheet in sheets) {
        _rules(name, doc, sheet.rules);
      }
      final sheetTexts = <String, String>{};
      for (final href in _hrefsOf(doc, section.href)) {
        final text = await source.readStyleSheet(href);
        if (text != null) sheetTexts[href] = text;
      }
      final (:styles, fontFaces: _) = await resolveSectionStyles(
        doc,
        href: section.href,
        styleSheets: sheetTexts,
        defaultStyleSheets: source.defaultStyleSheets,
        style: const BookStyle(),
      );
      _layout(name, doc, styles);
      _markup(name, doc);
    }
  }

  /// Declarations pagecraft drops, by the elements their rules match.
  void _rules(String book, ContentDocument doc, List<CssRule> rules) {
    for (final rule in rules) {
      switch (rule) {
        case CssQualifiedRule(:final prelude)
            when CssSelectorList.parse(prelude) == null &&
                CssSelectorList.parseText(
                      prelude.join().replaceAll(_pseudoElement, ''),
                    ) ==
                    null:
          // The whole rule is lost: count it by what in it fails.
          _record(_selectorKey(prelude.join()), book, [rules.indexOf(rule)]);
        case CssQualifiedRule(:final prelude, :final declarations):
          final dropped = [
            for (final d in declarations)
              if (parseCssDeclaration(d).isEmpty) d,
          ];
          if (dropped.isEmpty) continue;
          final (:pseudo, :elements) = _matching(doc, prelude.join());
          if (elements.isEmpty) continue;
          for (final d in dropped) {
            final key = _droppedKey(d);
            _record(pseudo == null ? key : '$pseudo $key', book, elements);
            if (key.startsWith('property ')) {
              final byValue = values.putIfAbsent(key, () => {});
              final value = _valueText(d);
              byValue[value] = (byValue[value] ?? 0) + elements.length;
            }
          }
        case CssAtRule(name: 'media', :final prelude, :final rules?):
          final query = prelude.join().trim().toLowerCase();
          if (query.contains('(')) {
            // pagecraft applies these as if the query held.
            _ruleTargets(book, doc, rules, '@media ${_features(query)}');
          }
          _rules(book, doc, rules);
        case CssAtRule(name: 'supports', :final prelude, :final rules?):
          _ruleTargets(
            book,
            doc,
            rules,
            '@supports ${_features(prelude.join().toLowerCase())}',
          );
        case CssAtRule(:final name) when name != 'font-face':
          _record('@$name', book, const [0]);
        case CssAtRule():
          break;
      }
    }
  }

  /// Every element some rule in [rules] styles, under [key].
  void _ruleTargets(
    String book,
    ContentDocument doc,
    List<CssRule> rules,
    String key,
  ) {
    for (final rule in rules) {
      if (rule is! CssQualifiedRule) continue;
      final (pseudo: _, :elements) = _matching(doc, rule.prelude.join());
      _record(key, book, elements);
    }
  }

  static final _pseudoElement = RegExp(
    r'::?(before|after|first-letter|first-line|marker|selection|placeholder)\b',
    caseSensitive: false,
  );

  /// The elements [selectorText] matches, pseudo-elements read as their
  /// originating elements.
  static ({String? pseudo, List<int> elements}) _matching(
    ContentDocument doc,
    String selectorText,
  ) {
    final pseudo = _pseudoElement.firstMatch(selectorText)?.group(1);
    final list = CssSelectorList.parseText(
      selectorText.replaceAll(_pseudoElement, ''),
    );
    if (list == null) return (pseudo: null, elements: const []);
    final elements = <int>[];
    for (var node = 0; node < doc.nodeCount; node++) {
      if (!doc.isElement(node)) continue;
      if (list.selectors.any((s) => s.matches(doc, node))) elements.add(node);
    }
    return (
      pseudo: pseudo == null ? null : '::${pseudo.toLowerCase()}',
      elements: elements,
    );
  }

  /// `selector :has()` (the pseudo-class, function or syntax a dropped
  /// selector uses), or the selector itself.
  static String _selectorKey(String text) {
    final functional = RegExp(r':([a-z-]+)\(').firstMatch(text);
    if (functional != null) return 'selector :${functional[1]}()';
    if (text.contains('|')) return 'selector namespace prefix';
    final pseudo = RegExp(r':([a-z-]+)').firstMatch(text);
    if (pseudo != null) return 'selector :${pseudo[1]}';
    final short = text.trim();
    return 'selector ${short.length > 40 ? '${short.substring(0, 40)}…' : short}';
  }

  /// `property foo` for a property pagecraft does not know, `value foo: v`
  /// for a value it does not parse.
  static String _droppedKey(CssDeclaration d) {
    final name = d.name.toLowerCase();
    final known = parseCssDeclaration(
      CssDeclaration(name, const [
        CssTokenValue(CssToken(CssTokenType.ident, value: 'inherit')),
      ]),
    ).isNotEmpty;
    if (!known) return 'property $name';
    return 'value $name: ${_valueText(d)}';
  }

  static String _valueText(CssDeclaration d) {
    final value = d.value.join().trim().replaceAll(RegExp(r'\s+'), ' ');
    return value.length > 40 ? '${value.substring(0, 40)}…' : value;
  }

  /// The media or support features a query tests, without their values.
  static String _features(String query) {
    final features = RegExp(
      r'\(\s*([a-z-]+)',
    ).allMatches(query).map((m) => m.group(1)!).toSet().toList()..sort();
    return features.isEmpty ? query : '(${features.join(', ')})';
  }

  /// Whether an ancestor of [node] is not shown, so it has no box.
  static bool _insideHidden(
    ContentDocument doc,
    ComputedStyles styles,
    int node,
  ) {
    for (
      var parent = doc.parentOf(node);
      parent != ContentDocument.none;
      parent = doc.parentOf(parent)
    ) {
      if (doc.isElement(parent) && styles[parent].display == CssDisplay.none) {
        return true;
      }
    }
    return false;
  }

  /// Whether a shown descendant of [node] is block-level.
  static bool _hasBlockContent(
    ContentDocument doc,
    ComputedStyles styles,
    int node,
  ) {
    for (final child in doc.childrenOf(node)) {
      if (!doc.isElement(child)) continue;
      final display = styles[child].display;
      if (display == CssDisplay.none) continue;
      if (display.isBlockLevel || _hasBlockContent(doc, styles, child)) {
        return true;
      }
    }
    return false;
  }

  /// Layout pagecraft's cascade gives that the layout does not draw yet.
  void _layout(String book, ContentDocument doc, ComputedStyles styles) {
    // Floats the boxes take out of the flow are drawn; the rest stay in
    // their line.
    final floats = <int>{};
    void collect(LayoutBox box) {
      switch (box) {
        case FloatBox(:final content):
          floats.add(box.node);
          collect(content);
        case BlockBox(:final children):
          children.forEach(collect);
        case TableBox(:final caption, :final rows):
          if (caption != null) collect(caption);
          for (final row in rows) {
            row.cells.forEach(collect);
          }
        case ParagraphBox() || ImageBox():
          break;
      }
    }

    collect(buildSectionBoxes(doc, styles).root);
    for (var node = 0; node < doc.nodeCount; node++) {
      if (!doc.isElement(node)) continue;
      final style = styles[node];
      final name = doc.localNameOf(node).toLowerCase();
      if (style.display == CssDisplay.none) continue;
      if (style.float != CssFloat.none &&
          style.position != CssPosition.absolute &&
          style.position != CssPosition.fixed &&
          !floats.contains(node) &&
          !_insideHidden(doc, styles, node)) {
        _record('layout: float inside a line, $name', book, [node]);
      }
      switch (style.display) {
        case CssDisplay.inlineBlock || CssDisplay.inlineTable:
          // An inline block around inline content is drawn as a block.
          if (name != 'img' &&
              (style.display == CssDisplay.inlineTable ||
                  _hasBlockContent(doc, styles, node))) {
            _record('layout: ${style.display.name} $name', book, [node]);
          }
        case CssDisplay.ruby || CssDisplay.rubyBase || CssDisplay.rubyText:
          _record('layout: ruby', book, [node]);
        default:
          break;
      }
      if (style.direction == CssDirection.rtl) {
        _record('text: right-to-left', book, [node]);
      }
    }
  }

  static const _markupWithoutBoxes = {
    'ruby',
    'video',
    'audio',
    'iframe',
    'object',
    'embed',
    'canvas',
    'input',
    'select',
    'textarea',
    'button',
    'details',
  };

  void _markup(String book, ContentDocument doc) {
    for (var node = 0; node < doc.nodeCount; node++) {
      if (!doc.isElement(node)) continue;
      final name = doc.localNameOf(node).toLowerCase();
      if (_markupWithoutBoxes.contains(name)) {
        _record('markup: $name', book, [node]);
      }
    }
  }

  static Iterable<String> _hrefsOf(ContentDocument doc, String href) sync* {
    for (var node = 0; node < doc.nodeCount; node++) {
      if (!doc.isElement(node)) continue;
      if (doc.localNameOf(node).toLowerCase() != 'link') continue;
      final link = doc.attributeOf(node, 'href');
      if (link != null) yield resolveBookUrl(link, href);
    }
  }

  String toMarkdown(int files) {
    final rows = counts.entries.toList()
      ..sort((a, b) {
        final byBooks = b.value.books.length.compareTo(a.value.books.length);
        return byBooks != 0
            ? byBooks
            : b.value.elements.compareTo(a.value.elements);
      });
    final out = StringBuffer()
      ..writeln('# pagecraft corpus census')
      ..writeln()
      ..writeln(
        '$books of $files books opened, $sections sections. Elements are '
        'the ones each feature lands on; a pseudo-element counts its '
        'originating element.',
      )
      ..writeln()
      ..writeln('| Feature | Books | Sections | Elements |')
      ..writeln('|---|---:|---:|---:|');
    for (final MapEntry(:key, :value) in rows) {
      final byValue = values[key];
      final detail = byValue == null
          ? ''
          : ' (${(byValue.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(4).map((e) => '${e.key}: ${e.value}').join('; ')})';
      out.writeln(
        '| `${key.replaceAll('|', r'\|')}`${detail.replaceAll('|', r'\|')} | '
        '${value.books.length} | ${value.sections} | ${value.elements} |',
      );
    }
    if (failures.isNotEmpty) {
      out
        ..writeln()
        ..writeln('Not opened:');
      for (final MapEntry(:key, :value) in failures.entries) {
        out.writeln('- $key: $value');
      }
    }
    return out.toString();
  }
}
