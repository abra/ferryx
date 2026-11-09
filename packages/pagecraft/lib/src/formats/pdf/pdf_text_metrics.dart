import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium;
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'pdf_native_task.dart';

/// Typographic character cells for the engine's existing structured text.
///
/// Tight glyph bounds can collapse to a baseline when a PDF substitutes a
/// missing font. Loose PDFium cells retain the font's ascent and descent.
/// Text and offsets remain those of [structuredText], preserving saved CFIs.
/// Whitespace retains the formatter's own synthetic rectangles. A text
/// mismatch returns null rather than attaching geometry to another character.
Future<List<PdfRect?>?> loadPdfTextSelectionRects(
  PdfDocument document,
  int pageIndex,
  String structuredText,
) async {
  if (structuredText.isEmpty) return const [];
  return runPdfDocumentTask(() async {
    final handle = await document.useNativeDocumentHandle((value) => value);
    // The hook has resumed the worker before this computation is queued.
    // Font substitution callbacks belong to that isolate too, so these calls
    // must use the engine's worker rather than a new isolate.
    return PdfrxEntryFunctions.instance.compute(_readSelectionRects, (
      documentAddress: handle,
      pageIndex: pageIndex,
      modulePath: Pdfrx.pdfiumModulePath,
      structuredText: structuredText,
    ));
  });
}

typedef _MetricsRequest = ({
  int documentAddress,
  int pageIndex,
  String? modulePath,
  String structuredText,
});

typedef _NativeCharacter = ({int codeUnit, PdfRect? rect});

List<PdfRect?>? _readSelectionRects(_MetricsRequest request) {
  final api = pdfium.getPdfium(modulePath: request.modulePath);
  final document = pdfium.FPDF_DOCUMENT.fromAddress(request.documentAddress);
  final page = api.FPDF_LoadPage(document, request.pageIndex);
  if (page == nullptr) return null;
  try {
    final textPage = api.FPDFText_LoadPage(page);
    if (textPage == nullptr) return null;
    try {
      return using((arena) {
        final bounds = arena<pdfium.FS_RECTF>();
        if (api.FPDF_GetPageBoundingBox(page, bounds) == 0) return null;
        final left = bounds.ref.left.toDouble();
        final bottom = bounds.ref.bottom.toDouble();
        final cell = arena<pdfium.FS_RECTF>();
        final characters = <_NativeCharacter>[];
        final count = api.FPDFText_CountChars(textPage);
        for (var index = 0; index < count; index++) {
          final unicode = api.FPDFText_GetUnicode(textPage, index);
          if (unicode > 0x10FFFF) return null;
          PdfRect? rect;
          if (api.FPDFText_GetLooseCharBox(textPage, index, cell) != 0) {
            final value = cell.ref;
            final candidate = PdfRect(
              value.left - left,
              value.top - bottom,
              value.right - left,
              value.bottom - bottom,
            );
            if (_isUsable(candidate)) rect = candidate;
          }
          // A native character can produce a surrogate pair. Both UTF-16
          // units belong to the same glyph cell, as the layer's offsets do.
          for (final codeUnit in String.fromCharCode(unicode).codeUnits) {
            characters.add((codeUnit: codeUnit, rect: rect));
          }
        }
        return _alignSelectionRects(request.structuredText, characters);
      });
    } finally {
      api.FPDFText_ClosePage(textPage);
    }
  } finally {
    api.FPDF_ClosePage(page);
  }
}

List<PdfRect?>? _alignSelectionRects(
  String structuredText,
  List<_NativeCharacter> characters,
) {
  final result = List<PdfRect?>.filled(structuredText.length, null);
  var nativeIndex = 0;
  for (var index = 0; index < structuredText.length; index++) {
    final codeUnit = structuredText.codeUnitAt(index);
    if (_isWhitespace(codeUnit)) continue;
    while (nativeIndex < characters.length &&
        _isWhitespace(characters[nativeIndex].codeUnit)) {
      nativeIndex++;
    }
    if (nativeIndex == characters.length ||
        characters[nativeIndex].codeUnit != codeUnit) {
      return null;
    }
    result[index] = characters[nativeIndex++].rect;
  }
  while (nativeIndex < characters.length &&
      _isWhitespace(characters[nativeIndex].codeUnit)) {
    nativeIndex++;
  }
  return nativeIndex == characters.length ? result : null;
}

bool _isUsable(PdfRect rect) =>
    rect.left.isFinite &&
    rect.top.isFinite &&
    rect.right.isFinite &&
    rect.bottom.isFinite &&
    rect.width > 0 &&
    rect.height > 0;

bool _isWhitespace(int codeUnit) =>
    (codeUnit >= 0x09 && codeUnit <= 0x0D) ||
    codeUnit == 0x20 ||
    codeUnit == 0xA0 ||
    codeUnit == 0x1680 ||
    (codeUnit >= 0x2000 && codeUnit <= 0x200A) ||
    codeUnit == 0x2028 ||
    codeUnit == 0x2029 ||
    codeUnit == 0x202F ||
    codeUnit == 0x205F ||
    codeUnit == 0x3000 ||
    codeUnit == 0xFEFF;
