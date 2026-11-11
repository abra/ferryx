import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:pagecraft/all_formats.dart';

import 'document_format.dart';
import 'preview_search.dart';
import 'document_page_image.dart';

class DocumentAppearance {
  const DocumentAppearance({
    required this.style,
    required this.fonts,
    required this.settings,
    required this.textScaler,
  });

  final BookStyle style;
  final BookFonts fonts;
  final TextPageSettings settings;
  final TextScaler textScaler;
}

class DocumentContentsEntry {
  const DocumentContentsEntry({required this.label, this.index, this.href});

  final String label;
  final int? index;
  final String? href;
}

/// An opened document and its rendering resources. The host closes this before
/// releasing the local file lease, including when opening finished too late.
abstract class DocumentSession extends ChangeNotifier
    implements PreviewSearchTarget {
  bool get searchable => false;
  bool _searchClosed = false;
  final _searchReads = <Future<Object?>>{};
  Future<T> readForSearch<T>(Future<T> Function() read) async {
    if (_searchClosed) throw StateError('Document closed');
    final future = read();
    _searchReads.add(future);
    try {
      return await future;
    } finally {
      _searchReads.remove(future);
    }
  }

  Future<void> closeSearch() async {
    _searchClosed = true;
    await Future.wait(
      _searchReads.map((f) async {
        try {
          await f;
        } on Object {
          /* The search reports its own failure. */
        }
      }),
    );
  }

  @override
  Stream<List<PreviewSearchHit>> search(String query) => const Stream.empty();
  @override
  Future<void> reveal(PreviewSearchHit hit) async {}

  TextPagesController? get textController;
  FixedPageSource? get fixedPages;
  int get index;
  int get count;
  bool get canPrevious;
  bool get canNext;
  bool get ready;
  Object? get error;
  List<DocumentContentsEntry> get contents;
  Future<void> previous();
  Future<void> next();
  Future<void> goTo(int index);
  Future<void> goToContents(DocumentContentsEntry entry);
  Future<void> first();
  Future<void> last();
  void updateAppearance(DocumentAppearance appearance);
  Future<void> close();
}

typedef DocumentOpener = Future<DocumentSession> Function(
  String path,
  DocumentFormat format,
  DocumentAppearance appearance,
);

Future<DocumentSession> openDocumentSession(
  String path,
  DocumentFormat format,
  DocumentAppearance appearance,
) async {
  switch (format) {
    case DocumentFormat.pdf:
      await initializePdfEngine();
      final book = await PdfBook.open(path);
      return _FixedSession(
        PdfPages(book),
        book.close,
        _pdfContents(book.outline),
        pageSearch: (page, query) async {
          final layer = await PdfTextLayer.load(book, page);
          return [
            for (final match in searchText(
              layer.text,
              query,
              maxMatches: PreviewSearchController.maxMatches + 1,
            ))
              PreviewSearchHit(page, '${match.pre}${match.match}${match.post}'),
          ];
        },
      );
    case DocumentFormat.djvu:
      final book = await DjvuBook.open(path);
      return _FixedSession(
        DjvuPages(book),
        book.close,
        _contents(book.toc, fixed: true),
        pageSearch: (page, query) async {
          final layer = await book.pageText(page);
          return [
            for (final match in searchText(
              layer.text,
              query,
              maxMatches: PreviewSearchController.maxMatches + 1,
            ))
              PreviewSearchHit(page, '${match.pre}${match.match}${match.post}'),
          ];
        },
      );
    case DocumentFormat.cbz:
      final book = await ComicBook.open(
        path,
        pageOrderVersion: currentComicPageOrderVersion,
      );
      return _FixedSession(
        DocumentComicPages(book),
        book.close,
        [
          for (final page in book.pages)
            DocumentContentsEntry(label: page.name, index: page.index),
        ],
      );
    case DocumentFormat.epub:
    case DocumentFormat.fb2:
    case DocumentFormat.mobi:
      final Object book = switch (format) {
        DocumentFormat.epub => await EpubBook.open(path),
        DocumentFormat.fb2 => await Isolate.run(() => Fb2Book.open(path)),
        _ => await MobiBook.open(path),
      };
      final source = textBookSourceOf(book);
      try {
        if (source.isFixedLayout) {
          throw const UnsupportedTextBookException(
            TextBookUnsupported.fixedLayout,
          );
        }
        return _TextSession(source, appearance);
      } catch (_) {
        await source.close();
        rethrow;
      }
  }
}

List<DocumentContentsEntry> _contents(
  List<BookNavItem>? items, {
  bool fixed = false,
}) => [
  for (final item in items ?? const <BookNavItem>[]) ...[
    if (item.href != null)
      DocumentContentsEntry(
        label: item.label,
        href: item.href,
        index: fixed ? fakeCfiToIndex(item.href!) : null,
      ),
    ..._contents(item.subitems, fixed: fixed),
  ],
];

List<DocumentContentsEntry> _pdfContents(List<PdfOutlineEntry> entries) => [
  for (final entry in entries) ...[
    if (entry.pageIndex != null)
      DocumentContentsEntry(label: entry.title, index: entry.pageIndex),
    ..._pdfContents(entry.children),
  ],
];

class _TextSession extends DocumentSession {
  _TextSession(this.source, DocumentAppearance appearance)
    : images = BookImageCache(read: source.readImage) {
    _controller = TextPagesController(
      source: source,
      style: appearance.style,
      fonts: appearance.fonts,
      images: images,
      settings: appearance.settings,
      textScaler: appearance.textScaler,
    )..addListener(notifyListeners);
  }

  final TextBookSource source;
  final BookImageCache images;
  late final _contentsEntries = _contents(source.toc);
  late final _linearBounds = _findLinearBounds();
  late final TextPagesController _controller;
  Future<void>? _closing;

  ({int first, int last}) _findLinearBounds() {
    // An empty range keeps both section transitions disabled when every
    // section is non-linear, matching Pagecraft's reading order.
    var first = source.sectionCount;
    var last = -1;
    for (var i = 0; i < source.sectionCount; i++) {
      if (!source.isLinear(i)) continue;
      first = math.min(first, i);
      last = i;
    }
    return (first: first, last: last);
  }

  @override
  bool get searchable => true;
  @override
  Stream<List<PreviewSearchHit>> search(String query) async* {
    if (query.isEmpty) return;
    // One section at a time: closing waits for the one active source read.
    for (
      var section = 0;
      section < source.sectionCount && !_searchClosed;
      section++
    ) {
      final events = await readForSearch(
        () => searchTextBook(
          source,
          query,
          section: section,
          parallel: 1,
          maxMatches: PreviewSearchController.maxMatches + 1,
        ).toList(),
      );
      if (_searchClosed) return;
      for (final event in events.whereType<TextSearchResults>()) {
        yield [
          for (final hit in event.hits)
            PreviewSearchHit(hit.cfi, '${hit.pre}${hit.match}${hit.post}'),
        ];
      }
    }
  }

  @override
  Future<void> reveal(PreviewSearchHit hit) async {
    if (!_searchClosed) await _controller.goToCfi(hit.anchor as String);
  }

  @override
  TextPagesController get textController => _controller;
  @override
  FixedPageSource? get fixedPages => null;
  @override
  int get index => _controller.position?.section ?? 0;
  @override
  int get count => source.sectionCount;
  @override
  bool get ready => _controller.isReady;
  @override
  Object? get error => _controller.error;
  @override
  bool get canPrevious =>
      ready &&
      (index > _linearBounds.first || (_controller.position?.spread ?? 0) > 0);
  @override
  bool get canNext {
    final position = _controller.position;
    return ready &&
        (index < _linearBounds.last ||
            position?.spreadCount == null ||
            position!.spread < position.spreadCount! - 1);
  }

  @override
  List<DocumentContentsEntry> get contents => _contentsEntries;
  @override
  Future<void> previous() async => _controller.previous();
  @override
  Future<void> next() async => _controller.next();
  @override
  Future<void> goTo(int index) => _controller.goToSection(index);
  @override
  Future<void> goToContents(DocumentContentsEntry entry) async {
    if (entry.href != null) await _controller.goToHref(entry.href!);
  }

  @override
  Future<void> first() => _controller.goToFraction(0);
  @override
  Future<void> last() => _controller.goToFraction(1);
  @override
  void updateAppearance(DocumentAppearance appearance) {
    _controller
      ..style = appearance.style
      ..fonts = appearance.fonts
      ..settings = appearance.settings
      ..textScaler = appearance.textScaler;
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    await closeSearch();
    try {
      _controller.removeListener(notifyListeners);
      _controller.dispose();
    } finally {
      try {
        images.dispose();
        dispose();
      } finally {
        await source.close();
      }
    }
  }
}

class _FixedSession extends DocumentSession {
  _FixedSession(
    FixedPageSource pages,
    this._closeBook,
    this.contents, {
    this.pageSearch,
  }) : _pages = _TrackedPages(pages);

  final Future<List<PreviewSearchHit>> Function(int page, String query)?
  pageSearch;
  @override
  bool get searchable => pageSearch != null;
  @override
  Stream<List<PreviewSearchHit>> search(String query) async* {
    final searchPage = pageSearch;
    if (query.isEmpty || searchPage == null) return;
    for (var page = 0; page < count && !_searchClosed; page++) {
      final hits = await readForSearch(() => searchPage(page, query));
      if (_searchClosed) return;
      if (hits.isNotEmpty) yield hits;
    }
  }

  @override
  Future<void> reveal(PreviewSearchHit hit) => goTo(hit.anchor as int);

  final _TrackedPages _pages;
  final Future<void> Function() _closeBook;
  Future<void>? _closing;
  int _index = 0;

  @override
  final List<DocumentContentsEntry> contents;
  @override
  TextPagesController? get textController => null;
  @override
  FixedPageSource get fixedPages => _pages;
  @override
  int get index => _index;
  @override
  int get count => _pages.pageCount;
  @override
  bool get canPrevious => _index > 0;
  @override
  bool get canNext => _index + 1 < count;
  @override
  bool get ready => count > 0;
  @override
  Object? get error =>
      count == 0 ? const PagecraftException('The document has no pages') : null;
  @override
  Future<void> previous() => goTo(_index - 1);
  @override
  Future<void> next() => goTo(_index + 1);
  @override
  Future<void> first() => goTo(0);
  @override
  Future<void> last() => goTo(count - 1);
  @override
  Future<void> goTo(int index) async {
    if (_closing != null || count == 0) return;
    final next = index.clamp(0, count - 1);
    if (_index == next) return;
    _index = next;
    notifyListeners();
  }

  @override
  Future<void> goToContents(DocumentContentsEntry entry) async {
    if (entry.index != null) await goTo(entry.index!);
  }

  @override
  void updateAppearance(DocumentAppearance appearance) {}
  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    await closeSearch();
    dispose();
    try {
      await _pages.clear();
    } finally {
      await _closeBook();
    }
  }
}

/// Do not retain every visited page's native document in Flutter's image cache.
class _TrackedPages implements FixedPageSource {
  _TrackedPages(this.source);
  final FixedPageSource source;
  final _images = <ImageProvider>{};
  @override
  int get pageCount => source.pageCount;
  @override
  double? pageAspect(int index) => source.pageAspect(index);
  @override
  ImageProvider pageImage(int index, {required int targetWidth}) {
    final aspect = pageAspect(index);
    const maxSide = DocumentComicPageImage.maxSide;
    if (aspect != null &&
        (!aspect.isFinite || aspect < 1 / maxSide || aspect > maxSide)) {
      return const DocumentUnrenderablePage();
    }
    final maxWidth = aspect == null
        ? 4096
        : math
              .min(math.sqrt(6000000 * aspect), maxSide * aspect)
              .floor()
              .clamp(1, 4096);
    final image = source.pageImage(
      index,
      targetWidth: targetWidth.clamp(1, maxWidth),
    );
    _images.remove(image);
    _images.add(image);
    while (_images.length > 8) {
      final old = _images.first;
      _images.remove(old);
      unawaited(old.evict());
    }
    return image;
  }

  @override
  ImageProvider pageThumbnail(int index) => pageImage(index, targetWidth: 240);
  @override
  ImageProvider? pageTile(
    int index, {
    required int fullWidth,
    required ({int x, int y, int width, int height}) region,
  }) => null;

  Future<void> clear() async {
    final images = _images.toList();
    _images.clear();
    await Future.wait(images.map((image) => image.evict()));
  }
}
