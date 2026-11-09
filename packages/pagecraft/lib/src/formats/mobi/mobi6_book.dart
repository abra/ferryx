/// MOBI 6 books (`class MOBI6` in `mobi.js`): one HTML stream split at
/// `<mbp:pagebreak>` into sections, `filepos` byte offsets as the link
/// targets, the guide from `<reference>` tags and the table of contents
/// from the guide's TOC page.
library;

import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:meta/meta.dart';

import '../book_navigation.dart';
import 'mobi6_markup.dart';
import 'mobi_container.dart';

/// One section: a byte range of the text stream.
@immutable
class Mobi6Section {
  const Mobi6Section({
    required this.index,
    required this.start,
    required this.end,
  });

  final int index;

  /// `filepos` range of the section in the whole text.
  final int start;
  final int end;

  int get size => end - start;
}

/// Where a `filepos:` link points.
@immutable
class Mobi6HrefTarget {
  const Mobi6HrefTarget({required this.index, required this.anchorId});

  /// The section index, or -1 past the text.
  final int index;

  /// The id of the anchor inserted at the target (`filepos<n>`).
  final String anchorId;
}

/// An opened MOBI 6 book.
class Mobi6Book {
  Mobi6Book._(this.container, this._text, this.sections, this._fileposList);

  /// Reads every text record of [container] and splits the stream.
  static Future<Mobi6Book> load(MobiContainer container) async {
    final text = await container.loadAllText();
    // Byte offsets, not characters: `filepos` counts bytes.
    final starts = [0, ...mobiPagebreakStarts(text)];
    final sections = <Mobi6Section>[];
    for (var i = 0; i < starts.length; i++) {
      final end = i + 1 < starts.length ? starts[i + 1] : text.length;
      sections.add(Mobi6Section(index: i, start: starts[i], end: end));
    }
    // Every distinct `filepos` string, as written (leading zeros kept:
    // the anchor ids repeat the string), in byte order.
    final seen = <String>{};
    final fileposList = <({String text, int number})>[
      for (final filepos in mobiFileposValues(text))
        if (seen.add(filepos)) (text: filepos, number: int.parse(filepos)),
    ]..sort((a, b) => a.number.compareTo(b.number));
    final book = Mobi6Book._(container, text, sections, fileposList);
    await book._readNavigation();
    return book;
  }

  static final _pagebreak = RegExp(
    r'<\s*(?:mbp:)?pagebreak[^>]*>',
    caseSensitive: false,
  );

  final MobiContainer container;
  final Uint8List _text;
  final List<Mobi6Section> sections;

  /// Every `filepos` referenced in the book, ascending.
  final List<({String text, int number})> _fileposList;
  final _textCache = <int, String>{};
  final _anchorsMoved = <int, int>{};

  /// How many `filepos` anchors of section [index] fell inside a tag and
  /// went before it ([mobiAnchorOffset]), once the section is loaded.
  @visibleForTesting
  int anchorsMovedOutOfTags(int index) => _anchorsMoved[index] ?? 0;

  List<BookNavItem>? toc;
  List<BookNavItem>? landmarks;

  MobiMetadata get metadata => container.metadata;

  Future<MobiCover?> readCover() => container.readCover();

  /// The HTML of section [index]: the section's bytes with an
  /// `<a id="filepos<n>"></a>` anchor at every referenced `filepos` and
  /// the pagebreak tags removed, decoded in the book's charset.
  String loadText(int index) {
    final cached = _textCache[index];
    if (cached != null) return cached;
    final section = sections[index];
    final raw = Uint8List.sublistView(_text, section.start, section.end);
    final anchors = <({String text, int offset})>[];
    var moved = 0;
    for (final filepos in _fileposList) {
      if (filepos.number < section.start || filepos.number >= section.end) {
        continue;
      }
      final offset = filepos.number - section.start;
      final placed = mobiAnchorOffset(raw, offset);
      if (placed != offset) moved++;
      anchors.add((text: filepos.text, offset: placed));
    }
    _anchorsMoved[index] = moved;
    final Uint8List bytes;
    if (anchors.isEmpty) {
      bytes = raw;
    } else {
      final out = BytesBuilder(copy: false);
      var from = 0;
      for (final (:text, :offset) in anchors) {
        out.add(Uint8List.sublistView(raw, from, offset));
        out.add(Uint8List.fromList('<a id="filepos$text"></a>'.codeUnits));
        from = offset;
      }
      out.add(Uint8List.sublistView(raw, from));
      bytes = out.toBytes();
    }
    final text = container.decode(bytes).replaceAll(_pagebreak, '');
    _textCache[index] = text;
    return text;
  }

  /// Section [index] parsed as HTML.
  dom.Document createDocument(int index) => html.parse(loadText(index));

  /// Image [recindex] (1-based, as the `recindex` attribute counts).
  Future<Uint8List> loadRecindex(int recindex) =>
      container.loadResource(recindex - 1);

  /// Where a `filepos:` link points (`resolveHref`).
  Mobi6HrefTarget resolveHref(String href) {
    final match = RegExp(r'filepos:(.*)').firstMatch(href);
    final filepos = match?.group(1) ?? '';
    final number = _jsNumber(filepos);
    final index = number == null
        ? -1
        : sections.indexWhere((s) => s.end > number);
    return Mobi6HrefTarget(index: index, anchorId: 'filepos$filepos');
  }

  /// [text] as JavaScript's `Number` reads it (blank is 0), or null for
  /// NaN: a guide reference without `filepos` gives `filepos:null`,
  /// which `mobi.js` resolves to no section.
  static num? _jsNumber(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    final number = int.tryParse(trimmed) ?? double.tryParse(trimmed);
    return number == null || number.isNaN ? null : number;
  }

  /// Whether [uri] leaves the book: a scheme other than `filepos:`.
  bool isExternal(String uri) => _external.hasMatch(uri);

  static final _external = RegExp(
    r'^(?!blob|filepos)\w+:',
    caseSensitive: false,
  );

  Future<void> close() => container.close();

  /// The guide from the first section's `<reference>` tags and the table
  /// of contents from the guide's `toc` page, nested by indentation.
  Future<void> _readNavigation() async {
    try {
      final guide = _readGuide();
      landmarks = guide;
      final tocHref = guide
          .where((item) => item.type?.contains('toc') ?? false)
          .firstOrNull
          ?.href;
      if (tocHref == null) return;
      final target = resolveHref(tocHref);
      if (target.index < 0) return;
      toc = _readToc(createDocument(target.index));
    } on Object {
      // mobi.js warns and leaves the navigation empty.
    }
  }

  List<BookNavItem> _readGuide() {
    final document = createDocument(0);
    return [
      for (final ref in document.getElementsByTagName('reference'))
        BookNavItem(
          label: ref.attributes['title'] ?? '',
          type: ref.attributes['type']?.split(RegExp(r'\s')),
          href: 'filepos:${ref.attributes['filepos']}',
        ),
    ];
  }

  /// `a[filepos]` links nested by their `p`/`blockquote` indentation,
  /// as `mobi.js` rebuilds a tree the HTML never had.
  static List<BookNavItem> _readToc(dom.Document document) {
    final roots = <_TocNode>[];
    _TocNode? last;
    var lastLevel = 0;
    var lastIndent = 0.0;
    final lastLevelOfIndent = <double, int>{};
    final lastParentOfLevel = <int, _TocNode>{};
    for (final a in document.querySelectorAll('a[filepos]')) {
      final indent = _indent(a);
      final item = _TocNode(
        label: a.text.trim(),
        href: 'filepos:${a.attributes['filepos']}',
      );
      final level = indent > lastIndent
          ? lastLevel + 1
          : indent == lastIndent
          ? lastLevel
          : lastLevelOfIndent[indent] ??
                (lastLevel - 1 < 0 ? 0 : lastLevel - 1);
      if (level > lastLevel) {
        if (last != null) {
          last.children.add(item);
          lastParentOfLevel[level] = last;
        } else {
          roots.add(item);
        }
      } else {
        final parent = lastParentOfLevel[level];
        if (parent != null) {
          parent.children.add(item);
        } else {
          roots.add(item);
        }
      }
      last = item;
      lastLevel = level;
      lastIndent = indent;
      lastLevelOfIndent[indent] = level;
    }
    return roots.map((n) => n.toItem()).toList();
  }

  static double _indent(dom.Element element) {
    var x = 0.0;
    dom.Element? current = element;
    while (current != null) {
      final parent = current.parent;
      if (parent != null) {
        final tag = parent.localName;
        if (tag == 'p') {
          x += 1.5;
        } else if (tag == 'blockquote') {
          x += 2;
        }
      }
      current = parent;
    }
    return x;
  }
}

class _TocNode {
  _TocNode({required this.label, required this.href});

  final String label;
  final String href;
  final children = <_TocNode>[];

  BookNavItem toItem() => BookNavItem(
    label: label,
    href: href,
    subitems: children.isEmpty
        ? null
        : children.map((c) => c.toItem()).toList(),
  );
}
