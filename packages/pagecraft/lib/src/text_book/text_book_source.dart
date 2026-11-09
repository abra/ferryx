/// What the text engine reads from a reflowable book, whatever its
/// format: sections as markup, style sheets, images. Each format adapts
/// its parser to it in its own module (`EpubTextSource`, `Fb2TextSource`,
/// `Mobi6TextSource`, `Kf8TextSource`, `ArticleTextSource`), so
/// preparation, layout and the view never look at a format.
library;

import 'dart:typed_data';

import '../formats/book_navigation.dart';
import 'text_anchor.dart';

/// Rewrites a book's CSS text before it is parsed, for a window
/// [windowWidth] × [windowHeight] CSS px. Runs in the section's isolate,
/// so it is a top-level function.
typedef BookCssRewrite =
    String Function(
      String css, {
      required double windowWidth,
      required double windowHeight,
    });

/// One section's markup.
class TextSection {
  const TextSection({
    required this.text,
    required this.href,
    this.mediaType,
  });

  /// XHTML, or HTML for `text/html` and MOBI 6.
  final String text;

  /// Where relative links in [text] resolve from.
  final String href;
  final String? mediaType;
}

abstract interface class TextBookSource {
  int get sectionCount;

  /// Whether section [index] is in the reading order (`linear="no"`
  /// sections and FB2 notes bodies are reached by links only).
  bool isLinear(int index);

  Future<TextSection> section(int index);

  /// The section's size, the weight it has in progress (foliate-js's
  /// `section.size`).
  int sectionSize(int index);

  /// The CFI of the section itself, which positions inside it extend:
  /// the spine item's for EPUB, `fakeCfiFromIndex` otherwise.
  String sectionCfi(int index);

  /// The section a CFI points into, or null.
  int? sectionOfCfi(String cfi);

  List<BookNavItem>? get toc;
  List<BookNavItem>? get pageList;

  /// Where [href] points (a table of contents entry, a link), or null.
  Future<TextTarget?> resolveHref(String href);

  /// A link's `href` in section [index] as the book resolves it: relative
  /// to the section for EPUB, as written otherwise (`section.resolveHref`).
  String resolveLink(int index, String href);

  /// Whether a resolved link leaves the book (`isExternal`).
  bool isExternal(String href);

  /// The book's language as it declares it, or null.
  String? get language;

  /// The format's declared right-to-left page progression.
  /// The paged controller also considers language and sampled body text.
  bool get rtl;

  /// Style sheets every section gets, before its own (FB2's built-in
  /// rules, as fb2.js links them).
  List<String> get defaultStyleSheets;

  /// The text of the style sheet at [href] (resolved), or null.
  Future<String?> readStyleSheet(String href);

  /// Pages of a fixed size: not a book to reflow (`TextBookUnsupported`).
  bool get isFixedLayout;

  /// How the book's CSS (sheets, `<style>`, `style`) is rewritten before
  /// it is read, or null to read it as written: EPUB's is read as
  /// foliate-js read it (`rewriteEpubCss`).
  BookCssRewrite? get cssRewrite;

  /// The image cache key of image [src] as section [sectionHref] writes
  /// it.
  String imageKey(String sectionHref, String src);

  Future<Uint8List?> readImage(String key);

  Future<void> close();
}
