import 'dart:convert';
import 'dart:typed_data';

import 'package:pagecraft/all_formats.dart';

/// Visible text the boxes do not account for: every non-whitespace
/// character of a text node outside hidden and skipped elements must be
/// covered by a paragraph's source map. Returns a description per text
/// node that loses characters.
List<String> lostCharacters(
  ContentDocument doc,
  ComputedStyles styles,
  SectionBoxes boxes,
) {
  const skipped = {
    'video',
    'audio',
    'iframe',
    'embed',
    'canvas',
    'input',
    'select',
    'textarea',
    'source',
    'track',
    // Drawn as one box of their own (an image, a formula).
    'svg',
    'math',
  };
  final covered = <int, List<(int, int)>>{};
  for (final paragraph in [
    for (final p in boxes.paragraphs) ...[p, ...p.nestedParagraphs],
  ]) {
    for (final s in paragraph.sourceMap.segments) {
      if (s.length == 0 || !doc.isText(s.node)) continue;
      covered.putIfAbsent(s.node, () => []).add((
        s.nodeStart,
        s.nodeStart + s.nodeLength,
      ));
    }
  }
  bool hidden(int node) {
    for (
      var e = doc.parentOf(node);
      e != ContentDocument.none;
      e = doc.parentOf(e)
    ) {
      if (styles[e].display == CssDisplay.none) return true;
      if (skipped.contains(doc.localNameOf(e).toLowerCase())) return true;
      final display = styles[e].display;
      // Text loose in a table or row (not in a cell) makes no box in v1.
      if (display == CssDisplay.table ||
          display == CssDisplay.tableRow ||
          display == CssDisplay.tableRowGroup ||
          display == CssDisplay.tableHeaderGroup ||
          display == CssDisplay.tableFooterGroup) {
        if (doc.parentOf(node) == e) return true;
      }
    }
    return false;
  }

  final out = <String>[];
  for (var n = 0; n < doc.nodeCount; n++) {
    if (!doc.isText(n)) continue;
    final text = doc.textOf(n);
    if (text.trim().isEmpty || hidden(n)) continue;
    final ranges = covered[n] ?? const [];
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) continue;
      if (!ranges.any((r) => i >= r.$1 && i < r.$2)) {
        out.add(
          'node $n lost "${text.substring(i, (i + 20).clamp(0, text.length))}"',
        );
        break;
      }
    }
  }
  return out;
}

/// The parsed book behind [path], as the reader opens it.
Future<Object> openBook(String path) async {
  final lower = path.toLowerCase();
  if (lower.endsWith('.epub')) return EpubBook.open(path);
  if (lower.endsWith('.fb2') ||
      lower.endsWith('.fb2.zip') ||
      lower.endsWith('.fbz')) {
    return Fb2Book.open(path);
  }
  return MobiBook.open(path);
}

/// Whether [path] is a book the corpus test reads.
bool isCorpusBook(String path) {
  final lower = path.toLowerCase();
  return const [
    '.epub',
    '.fb2',
    '.fb2.zip',
    '.fbz',
    '.mobi',
    '.azw3',
    '.azw',
    '.prc',
  ].any(lower.endsWith);
}

typedef LoadedSection = ({int bytes});

/// One opened book behind a format-neutral face, so the corpus test reads
/// EPUB, FB2 and MOBI alike.
abstract class CorpusBook {
  static Future<CorpusBook> open(String path) async =>
      switch (await openBook(path)) {
        final EpubBook book => _EpubCorpusBook(book),
        final Fb2Book book => _Fb2CorpusBook(book),
        final MobiBook book => _MobiCorpusBook(book),
        final other => throw StateError('Not a corpus book: $other'),
      };

  String get kind;
  int get sectionCount;

  /// The stylesheets of section [index], when the format has any.
  Future<List<CssStyleSheet>> styleSheets(
    int index,
    ContentDocument doc,
  ) async => const [];

  /// Section [index] as a [ContentDocument], or null when it has no
  /// document or does not parse.
  Future<ContentDocument?> contentDocument(int index);
  Future<Uint8List?> readCover();

  /// Every href of the contents, landmarks and page list.
  List<String> navHrefs();
  Future<int?> resolveHrefIndex(String href);

  /// Loads every section's text once, for timing and memory.
  Future<List<LoadedSection>> loadAllSections();
  Future<void> close();
}

List<String> _hrefs(List<BookNavItem>? items) => [
  for (final item in items ?? const <BookNavItem>[]) ...[
    if (item.href case final href? when href.isNotEmpty) href,
    ..._hrefs(item.subitems),
  ],
];

class _EpubCorpusBook extends CorpusBook {
  _EpubCorpusBook(this.book);

  final EpubBook book;

  @override
  String get kind => 'epub';

  @override
  int get sectionCount => book.sections.length;

  @override
  Future<Uint8List?> readCover() async => (await book.readCover())?.bytes;

  @override
  List<String> navHrefs() => [
    ..._hrefs(book.toc),
    ..._hrefs(book.landmarks),
    ..._hrefs(book.pageList),
  ];

  @override
  Future<int?> resolveHrefIndex(String href) async =>
      book.resolveHref(href)?.index;

  @override
  Future<List<LoadedSection>> loadAllSections() async => [
    for (var i = 0; i < book.sections.length; i++)
      (bytes: utf8.encode(await book.readSectionText(i)).length),
  ];

  @override
  Future<ContentDocument?> contentDocument(int index) async {
    final text = await book.readSectionText(index);
    try {
      return ContentDocument.parse(
        text,
        mediaType: book.sections[index].item.mediaType,
      );
    } on ContentParseException {
      return null;
    }
  }

  final _sheetCache = StyleSheetCache();

  @override
  Future<List<CssStyleSheet>> styleSheets(int index, ContentDocument doc) =>
      loadDocumentStyleSheets(
        doc,
        documentHref: book.sections[index].href,
        cache: _sheetCache,
        read: (href) async {
          final bytes = await book.readResource(href);
          return bytes == null
              ? null
              : utf8.decode(bytes, allowMalformed: true);
        },
      );

  @override
  Future<void> close() => book.close();
}

class _Fb2CorpusBook extends CorpusBook {
  _Fb2CorpusBook(this.book);

  final Fb2Book book;

  @override
  String get kind => 'fb2';

  @override
  int get sectionCount => book.sections.length;

  @override
  Future<Uint8List?> readCover() async => book.readCover()?.bytes;

  @override
  List<String> navHrefs() => _hrefs(book.toc);

  @override
  Future<int?> resolveHrefIndex(String href) async {
    final index = book.resolveHref(href).index;
    return index < 0 ? null : index;
  }

  @override
  Future<List<LoadedSection>> loadAllSections() async => [
    for (final s in book.sections) (bytes: utf8.encode(s.xhtml).length),
  ];

  @override
  Future<ContentDocument?> contentDocument(int index) async =>
      ContentDocument.parseXml(book.sections[index].xhtml);

  @override
  Future<void> close() async {}
}

class _MobiCorpusBook extends CorpusBook {
  _MobiCorpusBook(this.book);

  final MobiBook book;

  @override
  String get kind => book is MobiKf8 ? 'kf8' : 'mobi6';

  @override
  int get sectionCount => switch (book) {
    MobiKf8(:final book) => book.sections.length,
    MobiLegacy(:final book) => book.sections.length,
  };

  @override
  Future<Uint8List?> readCover() async {
    final cover = await switch (book) {
      MobiKf8(:final book) => book.readCover(),
      MobiLegacy(:final book) => book.readCover(),
    };
    return cover?.bytes;
  }

  @override
  List<String> navHrefs() => switch (book) {
    MobiKf8(:final book) => [..._hrefs(book.toc), ..._hrefs(book.landmarks)],
    MobiLegacy(:final book) => [
      ..._hrefs(book.toc),
      ..._hrefs(book.landmarks),
    ],
  };

  @override
  Future<int?> resolveHrefIndex(String href) async => switch (book) {
    MobiKf8(:final book) => (await book.resolveHref(href))?.index,
    MobiLegacy(:final book) => book.resolveHref(href).index,
  };

  @override
  Future<List<LoadedSection>> loadAllSections() async => switch (book) {
    MobiLegacy(:final book) => [
      for (var i = 0; i < book.sections.length; i++)
        (bytes: book.createDocument(i).outerHtml.length),
    ],
    MobiKf8(:final book) => [
      for (var i = 0; i < book.sections.length; i++)
        if (book.sections[i].isLinear)
          (bytes: utf8.encode(await book.loadText(i)).length),
    ],
  };

  @override
  Future<ContentDocument?> contentDocument(int index) async {
    switch (book) {
      case MobiLegacy(:final book):
        return ContentDocument.parseHtml(book.loadText(index));
      case MobiKf8(:final book):
        if (!book.sections[index].isLinear) return null;
        try {
          return ContentDocument.parseXml(await book.loadText(index));
        } on ContentParseException {
          return null;
        }
    }
  }

  @override
  Future<void> close() => book.close();
}
