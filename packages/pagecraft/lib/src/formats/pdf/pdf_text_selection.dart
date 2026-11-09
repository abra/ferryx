import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'pdf_text_layer.dart';

/// The text selection on a PDF page, owned by the app and shown by
/// `PdfTextOverlay`, as `ComicImageAreaDraft` holds an image-area draft.
///
/// The app clears it after a text action and restyles it when a highlight
/// colour is previewed.
class PdfTextSelection extends ChangeNotifier {
  int? _page;
  PdfTextRange? _range;
  Color _baseColor = defaultColor;
  Color? _previewColor;

  /// The selection tint before the app styles it: a translucent blue, as
  /// native selections look.
  static const defaultColor = Color(0x663D7BFF);

  int? get page => _page;
  PdfTextRange? get range => _range;
  bool get isActive => _range != null;

  Color get color => _previewColor ?? _baseColor;
  Color get baseColor => _baseColor;

  void start(int page, PdfTextRange range) {
    _page = page;
    _range = range;
    notifyListeners();
  }

  void update(PdfTextRange range) {
    if (_range == null || range == _range) return;
    _range = range;
    notifyListeners();
  }

  void clear() {
    if (_range == null && _page == null) return;
    _page = null;
    _range = null;
    notifyListeners();
  }

  /// The colour the selection is drawn with; alpha included.
  void setColor(Color color) {
    if (color == _previewColor) return;
    _previewColor = color;
    notifyListeners();
  }

  /// The live selection tint, independent of a temporary highlight preview.
  void setBaseColor(Color color) {
    if (color == _baseColor) return;
    _baseColor = color;
    if (_previewColor == null) notifyListeners();
  }

  /// Restores the configured live tint after a highlight preview.
  void resetColor() {
    if (_previewColor == null) return;
    _previewColor = null;
    notifyListeners();
  }
}

/// A saved text highlight drawn on a page.
@immutable
class PdfTextHighlight {
  const PdfTextHighlight({
    required this.id,
    required this.page,
    required this.range,
    required this.color,
  });

  final String id;
  final int page;
  final PdfTextRange range;

  /// Fill colour, alpha included.
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is PdfTextHighlight &&
      other.id == id &&
      other.page == page &&
      other.range == range &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, page, range, color);
}
