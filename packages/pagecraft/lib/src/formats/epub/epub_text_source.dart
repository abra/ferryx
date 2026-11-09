/// EPUB as a `TextBookSource`: spine items as sections, the manifest's
/// style sheets and images, EPUB CFIs, and its CSS read as foliate-js
/// read it.
library;

import 'dart:typed_data';

import '../../container/book_url.dart';
import '../../epubcfi/cfi.dart';
import '../../text_book/book_resources.dart';
import '../../text_book/text_anchor.dart';
import '../../text_book/text_book_source.dart';
import '../book_navigation.dart';
import 'epub_book.dart';
import 'epub_css.dart';

class EpubTextSource implements TextBookSource {
  EpubTextSource(this.book);

  final EpubBook book;

  @override
  bool get isFixedLayout => book.isFixedLayout;

  @override
  BookCssRewrite? get cssRewrite => rewriteEpubCss;

  @override
  int get sectionCount => book.sections.length;

  @override
  bool isLinear(int index) => book.sections[index].isLinear;

  @override
  Future<TextSection> section(int index) async {
    final s = book.sections[index];
    return TextSection(
      text: await book.readSectionText(index),
      href: s.href,
      mediaType: s.item.mediaType,
    );
  }

  @override
  int sectionSize(int index) => book.sections[index].size;

  @override
  String sectionCfi(int index) => book.sections[index].cfi.toString();

  @override
  int? sectionOfCfi(String cfi) {
    final parsed = Cfi.tryParse(cfi);
    if (parsed == null) return null;
    final index = book.resolveCfi(parsed).index;
    return index < 0 ? null : index;
  }

  @override
  List<BookNavItem>? get toc => book.toc;

  @override
  List<BookNavItem>? get pageList => book.pageList;

  @override
  String resolveLink(int index, String href) =>
      book.sections[index].resolveHref(href);

  @override
  String? get language {
    final languages = book.metadata.language;
    return languages.isEmpty ? null : languages.first;
  }

  @override
  bool get rtl => book.dir == 'rtl';

  @override
  bool isExternal(String href) => book.isExternal(href);

  @override
  Future<TextTarget?> resolveHref(String href) async {
    final target = book.resolveHref(href);
    if (target == null) return null;
    final fragment = target.fragment;
    return TextTarget(
      target.index,
      fragment == null || fragment.isEmpty ? null : TextAnchor.id(fragment),
    );
  }

  @override
  List<String> get defaultStyleSheets => const [];

  @override
  Future<String?> readStyleSheet(String href) async {
    final bytes = await book.readResource(href);
    return bytes == null ? null : decodeStyleSheetText(bytes);
  }

  @override
  String imageKey(String sectionHref, String src) =>
      src.startsWith('data:') ? src : resolveBookUrl(src, sectionHref);

  @override
  Future<Uint8List?> readImage(String key) async =>
      key.startsWith('data:') ? decodeDataUri(key) : book.readResource(key);

  @override
  Future<void> close() => book.close();
}
