import 'dart:async';

import 'package:flutter/painting.dart';

import '../fonts/book_font_loader.dart';
import '../fonts/font_ink.dart';
import '../layout/book_fonts.dart';
import '../layout/book_image_cache.dart';
import '../layout/book_style.dart';
import '../layout/column_layout.dart';
import '../layout/column_pages.dart';
import '../layout/inline_styler.dart';
import '../layout/paragraph_layout.dart';
import 'footnotes.dart';
import 'section_preparer.dart';
import 'text_anchor.dart';
import 'text_book_source.dart';
import 'text_book_support.dart';
import 'text_locator.dart';

/// One section laid out for a page geometry: its column, decided page by
/// page until the section is done, and where things are in it.
class TextSectionLayout {
  TextSectionLayout._(
    this.prepared,
    this.sectionCfi,
    this._task,
    this.pageHeight,
  );

  final PreparedSection prepared;
  final String sectionCfi;
  final ColumnLayoutTask _task;
  final double pageHeight;
  List<ColumnPage> _pages = const [];
  bool _disposed = false;
  bool _retired = false;

  int get index => prepared.index;
  ColumnLayout get column => _task.column;
  bool get isComplete => _task.isComplete;
  bool get isDisposed => _disposed;

  /// Dropped by a change of geometry, style or fonts: no longer the
  /// book's layout, though a view may still draw it until it is disposed.
  bool get isStale => _retired || _disposed;

  /// The pages decided so far; all of them once [isComplete].
  List<ColumnPage> get pages => _pages;

  late final TextLocator locator = TextLocator(
    prepared,
    column,
    sectionCfi: sectionCfi,
  );

  /// Lays out until page [page] is decided (or the section ends).
  void ensurePage(int page) {
    while (!isStale && !isComplete && _pages.length <= page) {
      _task.advance(untilHeight: column.height + pageHeight * 2);
      _paginate();
    }
  }

  /// Lays out until height [y] of the column is decided.
  void ensureHeight(double y) {
    if (isStale || isComplete || column.height > y + pageHeight) return;
    _task.advance(untilHeight: y + pageHeight * 2);
    _paginate();
  }

  /// Lays the rest out at once.
  void complete() {
    if (isStale || isComplete) return;
    _task.advance();
    _paginate();
  }

  /// Lays the rest out in slices, frames drawn between them; [onPages]
  /// after each slice that decided pages.
  Future<void> completeInSlices({VoidCallback? onPages}) async {
    while (!isStale && !isComplete) {
      final before = _pages.length;
      _task.advance(budget: const Duration(milliseconds: 6));
      _paginate();
      if (_pages.length != before) onPages?.call();
      if (!isComplete) await Future<void>.delayed(Duration.zero);
    }
  }

  void _paginate() {
    if (!isStale) _pages = paginateColumn(column, pageHeight: pageHeight);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    column.dispose();
  }
}

/// Lays a text book out for one page geometry and style: prepares
/// sections (in isolates, a few kept), loads the fonts they embed, and
/// keeps the sections near the reader laid out, dropping the rest.
/// Changing the geometry, the style or the fonts lays everything out
/// again; a style change prepares again too.
class TextBookLayout {
  TextBookLayout({
    required this.source,
    required BookStyle style,
    required BookFonts fonts,
    required this.images,
    TextScaler textScaler = TextScaler.noScaling,
    BookFontLoader? fontLoader,
    this.preparedLimit = 6,
  }) : _style = style,
       _fonts = fonts,
       _textScaler = textScaler,
       _preparer = SectionPreparer(source),
       _fontLoader = fontLoader ?? BookFontLoader(source);

  final TextBookSource source;
  final BookImageCache images;
  final SectionPreparer _preparer;
  final BookFontLoader _fontLoader;

  /// Prepared sections kept, most recently used last.
  final int preparedLimit;

  BookStyle _style;
  BookFonts _fonts;
  TextScaler _textScaler;
  InlineStyler? _styler;
  double _columnWidth = 0;
  double _pageHeight = 0;
  int _generation = 0;
  bool _disposed = false;

  final _prepared = <int, Future<PreparedSection>>{};
  final _layouts = <int, TextSectionLayout>{};
  final _pending = <int, Future<TextSectionLayout>>{};

  BookStyle get style => _style;

  /// Changes whenever laid-out sections are dropped: what a caller holding
  /// a [TextSectionLayout] compares to know it is stale.
  int get generation => _generation;

  double get columnWidth => _columnWidth;
  double get pageHeight => _pageHeight;

  /// Sets the column size; a change lays everything out again.
  void setPageSize(double columnWidth, double pageHeight) {
    if (columnWidth == _columnWidth && pageHeight == _pageHeight) return;
    _columnWidth = columnWidth;
    _pageHeight = pageHeight;
    _dropLayouts();
  }

  /// Sets the reader's style; sections are prepared again.
  set style(BookStyle value) {
    if (value == _style) return;
    final restyle = value.restylesFrom(_style);
    _style = value;
    if (restyle) _prepared.clear();
    _styler = null;
    _dropLayouts();
  }

  set fonts(BookFonts value) {
    if (value == _fonts) return;
    _fonts = value;
    _styler = null;
    _dropLayouts();
  }

  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    _dropLayouts();
  }

  /// The section if it is laid out (or being laid out) for the current
  /// geometry, without waiting.
  TextSectionLayout? laidOut(int index) => _layouts[index];

  /// Section [index] laid out at least to its first pages.
  Future<TextSectionLayout> section(int index) {
    final ready = _layouts[index];
    if (ready != null) return Future.value(ready);
    // A block body: `remove` returns this very future, which
    // `whenComplete` would wait for.
    return _pending[index] ??= _layOut(index).whenComplete(() {
      _pending.remove(index);
    });
  }

  Future<TextSectionLayout> _layOut(int index) async {
    final prepared = await _prepare(index);
    if (prepared.boxes.writingMode.isVertical) {
      throw const UnsupportedTextBookException(
        TextBookUnsupported.verticalWriting,
      );
    }
    if (await _fontLoader.load(prepared.fontFaces)) {
      // New families change how every section measures.
      _styler = null;
      if (_layouts.isNotEmpty) _dropLayouts();
    }
    await images.probe(prepared.imageKeys.values);
    if (_disposed) throw StateError('TextBookLayout disposed');
    // Laid out with whatever settings hold now.
    final existing = _layouts[index];
    if (existing != null) return existing;
    final styler = _styler ??= InlineStyler(
      bookStyle: _style,
      fonts: _fonts.withBookFamilies(
        _fontLoader.families,
        bookInk: _fontLoader.ink,
      ),
    );
    final task = ColumnLayoutTask(
      prepared.boxes,
      width: _columnWidth,
      pageHeight: _pageHeight,
      bookStyle: _style,
      text: TextLayoutEnvironment(
        styler: styler,
        imageSize: (src) {
          final key = prepared.imageKeys[src];
          return key == null ? null : images.sizeOf(key);
        },
        maxImageHeight: _pageHeight,
        textScaler: _textScaler,
      ),
    );
    final layout = TextSectionLayout._(
      prepared,
      source.sectionCfi(index),
      task,
      _pageHeight,
    );
    layout.ensurePage(0);
    _layouts[index] = layout;
    return layout;
  }

  Future<PreparedSection> _prepare(int index) {
    final cached = _prepared.remove(index);
    if (cached != null) {
      _prepared[index] = cached;
      return cached;
    }
    final future = _preparer.prepare(index, _style);
    _prepared[index] = future;
    while (_prepared.length > preparedLimit) {
      _prepared.remove(_prepared.keys.first);
    }
    // A failed preparation is not kept.
    future.then<void>((_) {}, onError: (Object _) => _prepared.remove(index));
    return future;
  }

  /// The book's embedded families loaded so far, CSS name to engine name.
  Map<String, String> get bookFamilies => _fontLoader.families;

  /// The ink of the book's embedded fonts, by registered family.
  Map<String, FontInk> get bookInk => _fontLoader.ink;

  /// The note [target] points to, prepared with the reader's style and its
  /// fonts loaded (see `SectionPreparer.prepareFootnote`).
  Future<PreparedFootnote?> prepareFootnote(
    TextTarget target, {
    bool extract = false,
  }) async {
    final note = await _preparer.prepareFootnote(
      target,
      _style,
      extract: extract,
    );
    if (note != null) await _fontLoader.load(note.content.fontFaces);
    return note;
  }

  /// Keeps the layouts of [indices] and drops the others.
  void retain(Iterable<int> indices) {
    final keep = indices.toSet();
    for (final index in _layouts.keys.toList()) {
      if (!keep.contains(index)) _layouts.remove(index)!.dispose();
    }
  }

  /// Layouts dropped by a change, kept drawable until [releaseRetired]:
  /// the view shows the old page while the new one is laid out.
  final _retired = <TextSectionLayout>[];

  void _dropLayouts() {
    _generation++;
    for (final layout in _layouts.values) {
      layout._retired = true;
      _retired.add(layout);
    }
    _layouts.clear();
  }

  bool get hasRetired => _retired.isNotEmpty;

  /// Disposes the layouts earlier changes dropped, once nothing draws
  /// them.
  void releaseRetired() {
    for (final layout in _retired) {
      layout.dispose();
    }
    _retired.clear();
  }

  void dispose() {
    _disposed = true;
    _dropLayouts();
    releaseRetired();
    _prepared.clear();
  }
}
