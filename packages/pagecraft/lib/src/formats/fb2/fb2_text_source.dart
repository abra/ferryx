/// FB2 as a `TextBookSource`: bodies and sections as XHTML sections
/// with fb2.js's built-in style sheet, images from `<binary>` elements,
/// fake CFIs.
library;

import 'dart:typed_data';

import '../../epubcfi/fake_cfi.dart';
import '../../text_book/book_resources.dart';
import '../../text_book/text_anchor.dart';
import '../../text_book/text_book_source.dart';
import '../book_navigation.dart';
import 'fb2_book.dart';

class Fb2TextSource implements TextBookSource {
  Fb2TextSource(this.book);

  final Fb2Book book;

  @override
  bool get isFixedLayout => false;

  @override
  BookCssRewrite? get cssRewrite => null;

  @override
  int get sectionCount => book.sections.length;

  @override
  bool isLinear(int index) => book.sections[index].isLinear;

  @override
  Future<TextSection> section(int index) async => TextSection(
    text: book.sections[index].xhtml,
    href: 'section-$index.xhtml',
    mediaType: 'application/xhtml+xml',
  );

  @override
  int sectionSize(int index) => book.sections[index].size;

  @override
  String sectionCfi(int index) => fakeCfiFromIndex(index);

  @override
  int? sectionOfCfi(String cfi) => fakeCfiToIndex(cfi);

  @override
  List<BookNavItem>? get toc => book.toc;

  @override
  List<BookNavItem>? get pageList => null;

  @override
  String resolveLink(int index, String href) => href;

  @override
  String? get language =>
      book.metadata.language.isEmpty ? null : book.metadata.language;

  @override
  bool get rtl => false;

  @override
  bool isExternal(String href) => book.isExternal(href);

  @override
  Future<TextTarget?> resolveHref(String href) async {
    final target = book.resolveHref(href);
    if (target.index < 0) return null;
    return switch (target) {
      Fb2TocTarget(:final titleIndex) => TextTarget(
        target.index,
        titleIndex == null
            ? null
            : TextAnchor.attribute(fb2DataIdAttribute, '$titleIndex'),
      ),
      Fb2IdTarget(:final id) => TextTarget(target.index, TextAnchor.id(id)),
    };
  }

  @override
  List<String> get defaultStyleSheets => const [fb2StyleSheet];

  @override
  Future<String?> readStyleSheet(String href) async => null;

  /// FB2 images are `data:` URIs (as fb2.js writes them) or `#id`.
  @override
  String imageKey(String sectionHref, String src) => src;

  @override
  Future<Uint8List?> readImage(String key) async {
    if (key.startsWith('data:')) return decodeDataUri(key);
    if (key.startsWith('#')) return book.readBinary(key.substring(1));
    return null;
  }

  @override
  Future<void> close() async {}
}

/// fb2.js's built-in style sheet, which it links into every section:
/// titles, epigraphs, poems, indents, note references. Namespaced
/// attribute selectors are written with the prefix, as pagecraft matches
/// them; `:before` content is left out (not drawn in v1).
const fb2StyleSheet = r'''
body > img, section > img { display: block; margin: auto; }
.title h1 { text-align: center; }
body > section > .title, body.notesBodyType > .title { margin: 3em 0; }
body.notesBodyType > section .title h1 { text-align: start; }
body.notesBodyType > section .title { margin: 1em 0; }
p { text-indent: 1em; margin: 0; }
:not(p) + p, p:first-child { text-indent: 0; }
.poem p { text-indent: 0; margin: 1em 0; }
.text-author, .date { text-align: end; }
table { border-collapse: collapse; }
td, th { padding: .25em; }
a[epub\:type~="noteref"] { font-size: .75em; vertical-align: super; }
body:not(.notesBodyType) > .title, body:not(.notesBodyType) > .epigraph { margin: 3em 0; }
''';
