import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../epubcfi/fake_cfi.dart';
import '../book_navigation.dart';
import 'djvu_text_layer.dart';
import 'native/djvu_worker.dart';

/// An oriented page's original dimensions, without decoding its bitmap.
class DjvuPageInfo {
  const DjvuPageInfo({
    required this.index,
    required this.width,
    required this.height,
    required this.dpi,
  });

  final int index;
  final int width;
  final int height;
  final int dpi;
  double get aspectRatio => width / height;
}

/// Owned, tightly packed RGBA8888 pixels. No native allocation outlives a reply.
class DjvuPagePixels {
  const DjvuPagePixels({
    required this.width,
    required this.height,
    required this.pixels,
  });

  final int width;
  final int height;
  final Uint8List pixels;
}

/// A self-contained DjVu document, decoded by DjVuLibre on its worker isolate.
/// Opening reads page headers and navigation; pixels and text remain on demand.
class DjvuBook {
  DjvuBook._(
    this.path,
    this._worker,
    this.pages,
    this.toc,
    this._title,
    this.author,
  );

  /// [timeout] bounds each native wait, not the sum of all page-header reads.
  static Future<DjvuBook> open(
    String path, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (path.isEmpty || path.contains('\u0000')) {
      throw ArgumentError.value(path, 'path', 'must be a nonempty file path');
    }
    if (timeout.inMilliseconds <= 0 || timeout.inMilliseconds > 120000) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'must be between 1ms and 2min',
      );
    }
    final opened = await DjvuWorker.open(path, timeout: timeout);
    try {
      final rawPages = opened.metadata['pages'] as List;
      final pages = <DjvuPageInfo>[];
      for (final (index, raw) in rawPages.indexed) {
        final info = (raw as List).cast<int>();
        if (info.length != 3 || info[0] <= 0 || info[1] <= 0) {
          throw StateError('Invalid DjVu page dimensions');
        }
        pages.add(
          DjvuPageInfo(
            index: index,
            width: info[0],
            height: info[1],
            dpi: info[2],
          ),
        );
      }
      final metadata = (opened.metadata['metadata'] as Map)
          .cast<String, Object?>();
      return DjvuBook._(
        path,
        opened.worker,
        List.unmodifiable(pages),
        _navigation(opened.metadata['toc'] as List, pages.length),
        _nonempty(metadata['title'] as String?),
        _nonempty(metadata['author'] as String?),
      );
    } on Object {
      await opened.worker.close();
      rethrow;
    }
  }

  final String path;
  final DjvuWorker _worker;
  final List<DjvuPageInfo> pages;
  final List<BookNavItem>? toc;
  final String? _title;
  final String? author;
  Future<void>? _closeFuture;

  int get pageCount => pages.length;
  bool get isClosed => _closeFuture != null;

  /// Document metadata, falling back to the filename when absent.
  String get title {
    if (_title != null) return _title;
    final name = path.replaceAll('\\', '/').split('/').last;
    return name.replaceFirst(RegExp(r'\.djvu?$', caseSensitive: false), '');
  }

  /// At most 24 MiB of output per request, independently of original scan size.
  static const maxPixels = 6000000;

  /// Full-page dimensions accepted by the native renderer, including tiles.
  static const maxRenderDimension = 131072;

  /// Renders a full page or a bounded region at [targetWidth] full-page pixels.
  /// Regions use top-left scaled-page coordinates, allowing sharp zoom tiles.
  Future<DjvuPagePixels> renderPage(
    int index, {
    required int targetWidth,
    ({int x, int y, int width, int height})? region,
  }) async {
    _checkPage(index);
    if (targetWidth <= 0 || targetWidth > 1000000) {
      throw RangeError.range(targetWidth, 1, 1000000, 'targetWidth');
    }
    final page = pages[index];
    final width = region == null
        ? boundedDjvuRenderWidth(targetWidth, page.aspectRatio)
        : targetWidth;
    final height = (width / page.aspectRatio).round().clamp(1, 1 << 30);
    if (width > maxRenderDimension || height > maxRenderDimension) {
      throw ArgumentError.value(
        targetWidth,
        'targetWidth',
        'full page exceeds native dimension limit',
      );
    }
    final area = region ?? (x: 0, y: 0, width: width, height: height);
    if (area.x < 0 ||
        area.y < 0 ||
        area.width <= 0 ||
        area.height <= 0 ||
        area.x + area.width > width ||
        area.y + area.height > height ||
        area.width * area.height > maxPixels) {
      throw ArgumentError.value(
        region,
        'region',
        'outside page or pixel budget',
      );
    }
    final data = await _worker.request('render', [
      index,
      width,
      height,
      area.x,
      area.y,
      area.width,
      area.height,
    ]);
    final pixels = (data as TransferableTypedData).materialize().asUint8List();
    if (pixels.length != area.width * area.height * 4) {
      throw StateError('DjVu decoder returned an invalid pixel buffer');
    }
    return DjvuPagePixels(
      width: area.width,
      height: area.height,
      pixels: pixels,
    );
  }

  Future<DjvuTextLayer> pageText(int index) async {
    _checkPage(index);
    final data = await _worker.request('text', [index]);
    return DjvuTextLayer.fromJson(index, (data as Map).cast<String, Object?>());
  }

  int? resolveHref(String href) {
    final match = RegExp(r'^#page=(\d+)$').firstMatch(href);
    final page = match == null ? fakeCfiToIndex(href) : int.tryParse(match[1]!);
    return page != null && page >= 0 && page < pageCount ? page : null;
  }

  void _checkPage(int index) {
    if (isClosed) throw StateError('DjVu document is closed');
    RangeError.checkValidIndex(index, pages, 'index');
  }

  /// Drains accepted work and releases the decoder once. New calls are refused.
  Future<void> close() => _closeFuture ??= _worker.close();
}

String? _nonempty(String? value) =>
    value == null || value.trim().isEmpty ? null : value;

int boundedDjvuRenderWidth(int targetWidth, double aspectRatio) {
  if (targetWidth <= 0) throw RangeError.value(targetWidth, 'targetWidth');
  if (!aspectRatio.isFinite || aspectRatio <= 0) {
    throw ArgumentError.value(aspectRatio, 'aspectRatio');
  }
  var width = math.min(targetWidth, DjvuBook.maxRenderDimension);
  final widthAtMaxHeight = DjvuBook.maxRenderDimension * aspectRatio;
  if (widthAtMaxHeight < width) {
    width = math.max(1, widthAtMaxHeight.floor());
  }
  if (width / aspectRatio > DjvuBook.maxRenderDimension + 0.49) {
    throw ArgumentError.value(
      aspectRatio,
      'aspectRatio',
      'cannot fit within the native dimension limit',
    );
  }
  int pixelsAt(int value) =>
      value * (value / aspectRatio).round().clamp(1, 1 << 30);
  if (pixelsAt(width) <= DjvuBook.maxPixels) return width;
  width = math.min(
    width,
    math.max(1, math.sqrt(DjvuBook.maxPixels * aspectRatio).floor()),
  );
  while (width > 1 && pixelsAt(width) > DjvuBook.maxPixels) {
    width--;
  }
  return width;
}

List<BookNavItem>? _navigation(List values, int pageCount, [int depth = 0]) {
  if (depth > 32) return null;
  final result = <BookNavItem>[];
  for (final value in values) {
    final item = (value as Map).cast<String, Object?>();
    final page = item['page'] as int?;
    result.add(
      BookNavItem(
        label: item['title'] as String,
        href: page != null && page >= 0 && page < pageCount
            ? '#page=$page'
            : null,
        subitems: _navigation(
          item['children'] as List? ?? const [],
          pageCount,
          depth + 1,
        ),
      ),
    );
  }
  return result.isEmpty ? null : List.unmodifiable(result);
}
