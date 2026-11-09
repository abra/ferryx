import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'djvu_text_layer.dart';

/// The text selection on a DjVu page, owned by the app and shown by
/// `DjvuTextOverlay`, as `ComicImageAreaDraft` holds an image-area draft.
///
/// The app clears it after a text action and restyles it when a highlight
/// colour is previewed.
class DjvuTextSelection extends ChangeNotifier {
  int? _page;
  DjvuTextRange? _range;
  Color _color = defaultColor;

  /// The selection tint before the app styles it: a translucent blue, as
  /// native selections look.
  static const defaultColor = Color(0x663D7BFF);

  int? get page => _page;
  DjvuTextRange? get range => _range;
  bool get isActive => _range != null;

  Color get color => _color;

  void start(int page, DjvuTextRange range) {
    _page = page;
    _range = range;
    notifyListeners();
  }

  void update(DjvuTextRange range) {
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
    if (color == _color) return;
    _color = color;
    notifyListeners();
  }
}

/// A saved text highlight drawn on a page.
@immutable
class DjvuTextHighlight {
  const DjvuTextHighlight({
    required this.id,
    required this.page,
    required this.range,
    required this.color,
  });

  final String id;
  final int page;
  final DjvuTextRange range;

  /// Fill colour, alpha included.
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is DjvuTextHighlight &&
      other.id == id &&
      other.page == page &&
      other.range == range &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, page, range, color);
}
