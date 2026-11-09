import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../document/content_document.dart';
import '../epubcfi/fake_cfi.dart';
import '../formats/book_navigation.dart';
import '../text_book/text_anchor.dart';
import '../text_book/text_book_source.dart';
import 'article_document.dart';

/// An article the reader saved: one HTML file with its pictures in an
/// `images/` folder beside it, read as a text book of one section, the
/// article as the WebView shell showed it ([articleDocumentHtml]) with the
/// shell's layout ([articleStyleSheet]) and contents ([articleToc]).
class ArticleTextSource implements TextBookSource {
  ArticleTextSource._(this._directory, this._html, this.toc, this.language);

  /// Reads the article at [path], in [language] when it is known; its
  /// markup is cleaned and its contents listed in a short-lived isolate.
  static Future<ArticleTextSource> open(String path, {String? language}) async {
    final file = File(path);
    final (html, toc) = await Isolate.run(() {
      final html = articleDocumentHtml(file.readAsStringSync());
      return (html, articleToc(ContentDocument.parseHtml(html)));
    });
    return ArticleTextSource._(file.parent.path, html, toc, language);
  }

  /// An article from its [html] as saved, its pictures in [directory]:
  /// what [open] reads, for tests.
  @visibleForTesting
  factory ArticleTextSource.fromHtml(
    String html, {
    String directory = '.',
    String? language,
  }) {
    final document = articleDocumentHtml(html);
    return ArticleTextSource._(
      directory,
      document,
      articleToc(ContentDocument.parseHtml(document)),
      language,
    );
  }

  /// The address the article's links and pictures resolve from.
  static const href = 'article.html';

  final String _directory;
  final String _html;

  @override
  final List<BookNavItem> toc;

  @override
  int get sectionCount => 1;

  @override
  bool isLinear(int index) => true;

  @override
  Future<TextSection> section(int index) async =>
      TextSection(text: _html, href: href, mediaType: 'text/html');

  @override
  int sectionSize(int index) => _html.length;

  @override
  String sectionCfi(int index) => fakeCfiFromIndex(index);

  @override
  int? sectionOfCfi(String cfi) => 0;

  @override
  List<BookNavItem>? get pageList => null;

  /// `#id`: an element of the article.
  @override
  Future<TextTarget?> resolveHref(String href) async {
    if (!href.startsWith('#') || href.length < 2) return null;
    return TextTarget(0, TextAnchor.id(href.substring(1)));
  }

  @override
  String resolveLink(int index, String href) => href;

  /// Anything but a fragment leaves the article.
  @override
  bool isExternal(String href) => !href.startsWith('#');

  /// The article's language as the library knows it: it is in no
  /// markup the import keeps.
  @override
  final String? language;

  @override
  bool get rtl => false;

  @override
  List<String> get defaultStyleSheets => const [articleStyleSheet];

  @override
  Future<String?> readStyleSheet(String href) async => null;

  @override
  bool get isFixedLayout => false;

  @override
  BookCssRewrite? get cssRewrite => null;

  @override
  String imageKey(String sectionHref, String src) => src;

  /// Only the article's own pictures ([articleDocumentHtml] kept no
  /// other `src`).
  @override
  Future<Uint8List?> readImage(String key) async {
    if (!_picture.hasMatch(key)) return null;
    final file = File('$_directory/$key');
    try {
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  static final _picture = RegExp(
    r'^images/[a-zA-Z0-9_-]+\.(?:png|jpe?g|gif|webp|avif)$',
  );

  @override
  Future<void> close() async {}
}
