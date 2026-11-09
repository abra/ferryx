/// MOBI 6 and KF8 as `TextBookSource`s: MOBI 6 as HTML split at page
/// breaks with `recindex` images, KF8 as XHTML sections with
/// `kindle:` resources; fake CFIs for both.
library;

import 'dart:typed_data';

import '../../epubcfi/fake_cfi.dart';
import '../../text_book/book_resources.dart';
import '../../text_book/text_anchor.dart';
import '../../text_book/text_book_source.dart';
import '../book_navigation.dart';
import 'kf8_book.dart';
import 'mobi6_book.dart';
import 'mobi_book.dart';

class Mobi6TextSource implements TextBookSource {
  Mobi6TextSource(this.book);

  final Mobi6Book book;

  @override
  bool get isFixedLayout => false;

  @override
  BookCssRewrite? get cssRewrite => null;

  @override
  int get sectionCount => book.sections.length;

  @override
  bool isLinear(int index) => true;

  @override
  Future<TextSection> section(int index) async => TextSection(
    text: book.loadText(index),
    href: 'section-$index.html',
    mediaType: 'text/html',
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
  String? get language => book.metadata.language?.firstOrNull;

  @override
  bool get rtl => false;

  @override
  bool isExternal(String href) => book.isExternal(href);

  @override
  Future<TextTarget?> resolveHref(String href) async {
    final target = book.resolveHref(href);
    if (target.index < 0) return null;
    return TextTarget(target.index, TextAnchor.id(target.anchorId));
  }

  @override
  List<String> get defaultStyleSheets => const [];

  @override
  Future<String?> readStyleSheet(String href) async => null;

  @override
  String imageKey(String sectionHref, String src) => src;

  /// `recindex:N`, the builder's name for `<img recindex="N">`, or a
  /// `data:` URI (an SVG drawn in the markup).
  @override
  Future<Uint8List?> readImage(String key) async {
    if (key.startsWith('data:')) return decodeDataUri(key);
    if (!key.startsWith('recindex:')) return null;
    final index = int.tryParse(key.substring('recindex:'.length));
    if (index == null) return null;
    try {
      return await book.loadRecindex(index);
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> close() => book.close();
}

class Kf8TextSource implements TextBookSource {
  Kf8TextSource(this.book);

  final Kf8Book book;

  @override
  bool get isFixedLayout => book.isFixedLayout;

  @override
  BookCssRewrite? get cssRewrite => null;

  @override
  int get sectionCount => book.sections.length;

  @override
  bool isLinear(int index) => book.sections[index].isLinear;

  @override
  Future<TextSection> section(int index) async => TextSection(
    text: await book.loadText(index),
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
  String? get language => book.metadata.language?.firstOrNull;

  @override
  bool get rtl => book.dir == 'rtl';

  @override
  bool isExternal(String href) => book.isExternal(href);

  @override
  Future<TextTarget?> resolveHref(String href) async {
    final target = await book.resolveHref(href);
    if (target == null || target.index < 0) return null;
    final selector = target.selector;
    return TextTarget(
      target.index,
      selector == null ? null : TextAnchor.selector(selector),
    );
  }

  @override
  List<String> get defaultStyleSheets => const [];

  @override
  Future<String?> readStyleSheet(String href) async {
    final bytes = await book.loadResource(href);
    return bytes == null ? null : decodeStyleSheetText(bytes);
  }

  /// `kindle:embed:` URIs are absolute.
  @override
  String imageKey(String sectionHref, String src) => src;

  @override
  Future<Uint8List?> readImage(String key) async =>
      key.startsWith('data:') ? decodeDataUri(key) : book.loadResource(key);

  @override
  Future<void> close() => book.close();
}

/// The source for an opened MOBI file, whichever part it holds.
TextBookSource mobiTextSource(MobiBook book) => switch (book) {
  MobiLegacy(:final book) => Mobi6TextSource(book),
  MobiKf8(:final book) => Kf8TextSource(book),
};
