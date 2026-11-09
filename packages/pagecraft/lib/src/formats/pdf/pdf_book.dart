import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_dart;
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../../pagecraft_exception.dart';
import 'pdf_native_task.dart';

/// A PDF over pdfium (`pdfrx_engine`): the pages with their sizes, the
/// outline and the Info dictionary. The counterpart of `pdf.js` in the
/// WebView reader, which read the same three things to open a document.
///
/// Opening reads the size of every page in the engine's worker isolate;
/// this cost grows with page count. Nothing is rendered
/// until a page is asked for. The engine must be loaded first:
/// `initializePdfEngine()` in the app, `preparePdfEngineForTests()` in
/// tests.
class PdfBook {
  PdfBook._(
    this._document,
    this.path, {
    required this.pages,
    required this.outline,
    required this.title,
    required this.author,
  });

  /// Opens the file at [path].
  ///
  /// Throws [PdfPasswordRequiredException] when the file is encrypted and
  /// [password] is missing or wrong, and [PagecraftException] when the file is
  /// missing or not a PDF pdfium can read.
  static Future<PdfBook> open(String path, {String? password}) async {
    final PdfDocument document;
    try {
      document = await PdfDocument.openFile(
        path,
        passwordProvider: password == null
            ? null
            : createSimplePasswordProvider(password),
      );
    } on PdfPasswordException {
      throw PdfPasswordRequiredException(path);
    } on PdfException catch (e) {
      throw PagecraftException('Cannot open PDF $path: ${e.message}');
    }
    try {
      final pages = [
        for (final page in document.pages)
          PdfPageInfo(
            index: page.pageNumber - 1,
            width: page.width,
            height: page.height,
            rotation: page.rotation.index,
          ),
      ];
      final outline = pdfOutlineEntriesFrom(
        await document.loadOutline(),
        pageCount: pages.length,
      );
      final title = await _metaText(document, 'Title');
      final author = await _metaText(document, 'Author');
      return PdfBook._(
        document,
        path,
        pages: List.unmodifiable(pages),
        outline: outline,
        title: title,
        author: author,
      );
    } catch (_) {
      await runPdfDocumentTask(document.dispose);
      rethrow;
    }
  }

  final PdfDocument _document;
  bool _closed = false;
  Future<void>? _closeFuture;

  final String path;

  /// Pages in document order; sizes are in points, as displayed (the
  /// page's own rotation already applied).
  final List<PdfPageInfo> pages;

  /// The document outline (bookmarks), empty when the PDF has none.
  final List<PdfOutlineEntry> outline;

  /// `Title` and `Author` of the Info dictionary, null when absent or blank.
  final String? title;
  final String? author;

  int get pageCount => pages.length;

  /// The engine's document, for the rendering layer. Not for the app.
  @internal
  PdfDocument get document {
    if (_closed) throw StateError('PdfBook is closed: $path');
    return _document;
  }

  /// Releases the document; safe to call more than once.
  Future<void> close() {
    final pending = _closeFuture;
    if (pending != null) return pending;
    _closed = true;
    return _closeFuture = runPdfDocumentTask(_document.dispose);
  }
}

/// A page's index, display size in points and rotation.
class PdfPageInfo {
  const PdfPageInfo({
    required this.index,
    required this.width,
    required this.height,
    required this.rotation,
  });

  final int index;
  final double width;
  final double height;

  /// Clockwise quarter turns the page's `/Rotate` applies to its content,
  /// 0–3; [width] and [height] are already the turned size.
  final int rotation;

  double get aspectRatio => width / height;

  @override
  String toString() =>
      'PdfPageInfo(#$index ${width}x$height pt, rotation: $rotation)';
}

/// An outline (bookmark) entry: its title, the page it opens and nested
/// entries. [pageIndex] is null for an entry without a usable destination;
/// the WebView reader showed such entries too and ignored taps on them.
class PdfOutlineEntry {
  const PdfOutlineEntry({
    required this.title,
    required this.pageIndex,
    this.children = const [],
  });

  final String title;
  final int? pageIndex;
  final List<PdfOutlineEntry> children;

  @override
  String toString() =>
      'PdfOutlineEntry($title -> $pageIndex, ${children.length} children)';
}

/// Maps the engine's outline to [PdfOutlineEntry]s; destinations outside
/// `0 ≤ page < pageCount` become null, since pdfium numbers pages from 1.
List<PdfOutlineEntry> pdfOutlineEntriesFrom(
  List<PdfOutlineNode> nodes, {
  required int pageCount,
}) {
  return List.unmodifiable([
    for (final node in nodes)
      PdfOutlineEntry(
        title: node.title,
        pageIndex: switch (node.dest?.pageNumber) {
          final number? when number >= 1 && number <= pageCount => number - 1,
          _ => null,
        },
        children: pdfOutlineEntriesFrom(node.children, pageCount: pageCount),
      ),
  ]);
}

/// Thrown by [PdfBook.open] for an encrypted file without the right
/// password. The host can retry with a password; Readflex currently reports an
/// open/import error and has no password-entry UI.
class PdfPasswordRequiredException extends PagecraftException {
  const PdfPasswordRequiredException(String path)
    : super('PDF is password-protected: $path');
}

pdfium_dart.PDFium? _bindings;

/// The pdfium bindings the engine itself loaded: the same library handle,
/// so a call between the engine's own calls is one more pdfium call.
pdfium_dart.PDFium get _pdfium =>
    _bindings ??= pdfium_dart.getPdfium(modulePath: Pdfrx.pdfiumModulePath);

/// `FPDF_GetMetaText` for [tag], which `pdfrx_engine` does not expose. The
/// engine's worker is paused for the call, as pdfium allows one caller at
/// a time; the text comes back as UTF-16LE with a terminator.
Future<String?> _metaText(PdfDocument document, String tag) {
  return runPdfNativeDocumentTask(document, (handle) {
    return using((arena) {
      final pdfium = _pdfium;
      final doc = pdfium_dart.FPDF_DOCUMENT.fromAddress(handle);
      final key = tag.toNativeUtf8(allocator: arena).cast<Char>();
      final length = pdfium.FPDF_GetMetaText(doc, key, nullptr, 0);
      if (length <= 2) return null;
      final buffer = arena<Uint8>(length);
      pdfium.FPDF_GetMetaText(doc, key, buffer.cast<Void>(), length);
      final units = buffer.cast<Uint16>().asTypedList(length ~/ 2);
      final end = units.indexOf(0);
      final text = String.fromCharCodes(
        end < 0 ? units : units.sublist(0, end),
      ).trim();
      return text.isEmpty ? null : text;
    });
  });
}
