import 'dart:typed_data';

import '../../container/zip_archive.dart';
import 'comic_page.dart';
import 'comic_page_order.dart';
import 'comic_page_source.dart';

/// A CBZ comic: the images of a ZIP archive in reading order.
///
/// The counterpart of `comic-book.js`. Every page is one section of equal
/// weight, so progress reads as `(pageIndex + 1) / pageCount`; the first page is
/// the cover; the table of contents lists page names. Bytes are read on
/// demand and never cached here: decoding to the screen size and the memory
/// budget belong to the image layer above.
class ComicBook implements ComicPageSource {
  ComicBook._(this._archive, this.pages, this.title, this.pageOrderVersion);

  /// Opens the archive at [path] and lists its pages.
  ///
  /// [pageOrderVersion] is the book's stored ordering rule; new imports use
  /// [currentComicPageOrderVersion]. Throws `PagecraftException` when the file
  /// is not a ZIP archive or holds no page images.
  static Future<ComicBook> open(
    String path, {
    required int pageOrderVersion,
  }) async {
    final archive = await ZipArchive.open(path);
    try {
      return ComicBook.fromArchive(archive, pageOrderVersion: pageOrderVersion);
    } catch (_) {
      await archive.close();
      rethrow;
    }
  }

  /// Lists the pages of an already open [archive], which the book then
  /// owns and closes.
  factory ComicBook.fromArchive(
    ZipArchive archive, {
    required int pageOrderVersion,
  }) {
    final byName = {for (final entry in archive.entries) entry.name: entry};
    final names = selectComicPages(
      byName.keys,
      pageOrderVersion: pageOrderVersion,
    );
    final pages = [
      for (final (index, name) in names.indexed)
        ComicPage(index: index, entry: byName[name]!),
    ];
    return ComicBook._(
      archive,
      List.unmodifiable(pages),
      titleFromFileName(archive.path),
      pageOrderVersion,
    );
  }

  final ZipArchive _archive;

  /// Pages in reading order; never empty.
  final List<ComicPage> pages;

  /// The file name without its directory and comic extension, which is
  /// what the library shows when the archive carries no metadata.
  final String title;

  final int pageOrderVersion;

  String get path => _archive.path;

  @override
  int get pageCount => pages.length;

  @override
  int pageSize(int index) => pages[index].size;

  /// Reads the encoded image of [pages]`[index]`. [maxBytes] refuses pages
  /// above a budget before reading.
  @override
  Future<Uint8List> readPage(int index, {int? maxBytes}) =>
      _archive.read(pages[index].entry, maxBytes: maxBytes);

  /// The cover is the first page, as in every comic reader.
  Future<Uint8List> readCover({int? maxBytes}) =>
      readPage(0, maxBytes: maxBytes);

  /// The page an internal link or table-of-contents entry names, or null.
  ComicPage? resolveHref(String href) {
    for (final page in pages) {
      if (page.name == href) return page;
    }
    return null;
  }

  Future<void> close() => _archive.close();

  /// Strips the directory and a comic archive extension, keeping other
  /// extensions so a mislabelled file still shows its full name.
  static String titleFromFileName(String path) {
    final slash = path.lastIndexOf('/');
    final name = slash < 0 ? path : path.substring(slash + 1);
    return name.replaceFirst(_comicExtension, '');
  }

  static final _comicExtension = RegExp(
    r'\.(cbz|cbr|cb7|cbt)$',
    caseSensitive: false,
  );
}
